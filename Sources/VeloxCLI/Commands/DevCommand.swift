import ArgumentParser
import Darwin
import Foundation
import Logging
import VeloxRuntime

/// Result of running app with file watching.
///
/// Used internally by the dev command to determine whether to rebuild or restart.
enum WatchResult {
  /// Files changed while the app was running.
  case fileChanged(FileChangeResult)
  /// The app exited on its own (crash or user close).
  case appExited
}

/// Runs the app and file watcher concurrently, returning when either completes.
///
/// - Returns: A ``WatchResult`` indicating whether files changed or the app exited.
func runWithFileWatching(
  processManager: ProcessManager,
  fileWatcher: FileWatcher,
  target: String,
  release: Bool,
  devUrl: String?,
  packageDirectory: URL,
  additionalEnv: [String: String],
  needsRebuild: Bool
) async throws -> WatchResult {
  logger.debug("runWithFileWatching called, needsRebuild=\(needsRebuild)")
  // Use a task group to race between app running and file changes
  return try await withThrowingTaskGroup(of: WatchResult.self) { group in
    // Task 1: Run the app
    group.addTask {
      logger.debug("App task starting")
      if needsRebuild {
        try await processManager.runSwiftApp(
          target: target,
          release: release,
          devUrl: devUrl,
          packageDirectory: packageDirectory,
          additionalEnv: additionalEnv
        )
      } else {
        try await processManager.restartSwiftApp(
          target: target,
          release: release,
          devUrl: devUrl,
          packageDirectory: packageDirectory,
          additionalEnv: additionalEnv
        )
      }
      logger.debug("App task completed (app exited)")
      return .appExited
    }

    // Task 2: Watch for file changes
    group.addTask {
      logger.debug("File watcher task starting")
      let changes = await fileWatcher.waitForChange()
      logger.debug("File watcher task completed with changes")
      return .fileChanged(changes)
    }

    // Return whichever completes first
    logger.debug("Waiting for first task to complete...")
    let result = try await group.next()!
    logger.debug("Got result: \(result)")

    // If file changed, terminate app BEFORE cancelling (otherwise task group deadlocks)
    if case .fileChanged = result {
      logger.debug("Terminating app before cancelling tasks...")
      await processManager.terminateApp()
    }

    // Cancel the other task
    group.cancelAll()
    logger.debug("Cancelled other tasks")

    return result
  }
}

/// Runs the Velox app in development mode with hot reloading.
///
/// The dev command:
/// 1. Loads `velox.json` configuration
/// 2. Runs `beforeDevCommand` if configured (e.g., start Vite)
/// 3. Waits for dev server if `devUrl` is configured
/// 4. Builds and runs the Swift app
/// 5. Watches for file changes and rebuilds/restarts as needed
///
/// Usage:
/// ```bash
/// # Auto-detect executable target
/// velox dev
///
/// # Specify target explicitly
/// velox dev MyAppTarget
///
/// # Override dev server port
/// velox dev --port 3001
///
/// # Run without file watching
/// velox dev --no-watch
/// ```
struct DevCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dev",
    abstract: "Run the app in development mode with hot reloading"
  )

  @Option(name: .long, help: "Override the dev server port")
  var port: Int?

  @Flag(name: .long, help: "Build in release mode")
  var release: Bool = false

  @Flag(name: .long, help: "Disable file watching")
  var noWatch: Bool = false

  @Flag(name: .shortAndLong, help: "Enable verbose logging")
  var verbose: Bool = false

  @Argument(help: "Executable target to run (auto-detected if omitted)")
  var target: String?

  func run() async throws {
    configureLogger(verbose: verbose)
    logger.info("Velox Dev")
    logger.info("=========")

    // 1. Load configuration
    let config: VeloxConfig
    do {
      config = try VeloxConfig.load()
      logger.info("[config] Loaded velox.json")
    } catch {
      throw ValidationError("No velox.json found. Run from project root.\n\(error)")
    }

    // 1.5. Load environment variables
    let envVars = EnvLoader.load(config: config, mode: release ? "production" : "development")
    if !envVars.isEmpty {
      logger.info("[env] Loaded \(envVars.count) environment variable(s)")
    }

    // 2. Detect or validate target
    let (executableTarget, packageDirectory) = try resolveTarget()
    logger.info("[target] Using executable: \(executableTarget)")
    logger.info("[package] Package directory: \(packageDirectory.path)")

    // 3. Set up process manager
    let processManager = ProcessManager()

    // Set up signal handlers for graceful shutdown
    setupSignalHandlers(processManager: processManager)

    // 4. Run beforeDevCommand if configured
    if let beforeDevCommand = config.build?.beforeDevCommand {
      logger.info("[hook] Running beforeDevCommand: \(beforeDevCommand)")
      try await processManager.spawnBackgroundProcess(
        command: beforeDevCommand,
        label: "beforeDevCommand"
      )
      // Give it a moment to start
      try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }

    // 5. Wait for dev server if devUrl is configured
    if let devUrl = effectiveDevUrl(from: config) {
      logger.info("[server] Waiting for dev server at \(devUrl)...")
      let checker = DevServerChecker(url: devUrl)
      let available = await checker.waitUntilAvailable(timeout: 60, retryInterval: 1)
      if !available {
        throw ValidationError("Dev server not responding at \(devUrl) after 60 seconds")
      }
      logger.info("[server] Dev server is ready")
    }

    // 6. Start file watcher (unless disabled)
    var fileWatcher: FileWatcher?
    if !noWatch {
      var watchPaths = ["Sources", "velox.json"]

      // Also watch frontend files if not using external dev server
      if effectiveDevUrl(from: config) == nil {
        if let frontendDist = config.build?.frontendDist {
          watchPaths.append(frontendDist)
          logger.info("[watch] Watching frontend files in \(frontendDist)/")
        }
      }

      fileWatcher = FileWatcher(paths: watchPaths)
    }

    // 7. Build and run loop
    var shouldExit = false
    var needsRebuild = true  // First run always builds
    let devUrl = effectiveDevUrl(from: config)

    while !shouldExit {
      do {
        if needsRebuild {
          logger.info("[build] Building and running \(executableTarget)...")
        } else {
          logger.info("[restart] Restarting \(executableTarget) (frontend-only changes)...")
        }

        // Run app and file watcher concurrently
        if noWatch {
          // No watching - just run the app and exit when it's done
          if needsRebuild {
            try await processManager.runSwiftApp(
              target: executableTarget,
              release: release,
              devUrl: devUrl,
              packageDirectory: packageDirectory,
              additionalEnv: envVars
            )
          } else {
            try await processManager.restartSwiftApp(
              target: executableTarget,
              release: release,
              devUrl: devUrl,
              packageDirectory: packageDirectory,
              additionalEnv: envVars
            )
          }
          shouldExit = true
        } else {
          // Watch mode - run app and file watcher concurrently
          let result = try await runWithFileWatching(
            processManager: processManager,
            fileWatcher: fileWatcher!,
            target: executableTarget,
            release: release,
            devUrl: devUrl,
            packageDirectory: packageDirectory,
            additionalEnv: envVars,
            needsRebuild: needsRebuild
          )

          switch result {
          case .fileChanged(let changes):
            // File changed while app was running - app already terminated in task group
            logger.debug("Processing file change result...")
            if changes.isFrontendOnly {
              logger.info("[watch] Frontend changes detected, restarting...")
              needsRebuild = false
            } else {
              if changes.hasBackendChanges {
                logger.info("[watch] Backend changes detected, rebuilding...")
              } else if changes.hasConfigChanges {
                logger.info("[watch] Config changes detected, rebuilding...")
              }
              needsRebuild = true
            }
            logger.debug("Looping back to rebuild/restart...")
          case .appExited:
            // App exited on its own - wait for file changes
            logger.info("[watch] App exited. Waiting for file changes...")
            if let changes = await fileWatcher?.waitForChange() {
              if changes.isFrontendOnly {
                logger.info("[watch] Frontend changes detected, restarting...")
                needsRebuild = false
              } else {
                needsRebuild = true
              }
            }
          }
        }
      } catch let error as ProcessManager.ProcessError {
        switch error {
        case .buildFailed(let output):
          logger.error("[error] Build failed:\n\(output)")
          if noWatch {
            throw error
          }
          logger.info("[watch] Waiting for file changes to retry...")
          _ = await fileWatcher?.waitForChange()
          needsRebuild = true  // Always rebuild after build failure
        case .terminated:
          // Process was killed (likely by us for file change), continue loop
          break
        case .runtimeError(let output):
          logger.error("[error] Runtime error:\n\(output)")
          if noWatch {
            throw error
          }
          logger.info("[watch] Waiting for file changes to restart...")
          if let changes = await fileWatcher?.waitForChange() {
            needsRebuild = !changes.isFrontendOnly
          }
        }
      }
    }

    // Cleanup
    await processManager.terminateAll()
    logger.info("[done] Velox dev stopped")
  }

  private func resolveTarget() throws -> (target: String, packageDirectory: URL) {
    let detector = TargetDetector()
    let result = try detector.detect()

    if let target = target {
      return (target, result.packageDirectory)
    }

    if result.executables.isEmpty {
      throw ValidationError("No executable targets found in Package.swift")
    }

    if result.executables.count == 1 {
      return (result.executables[0], result.packageDirectory)
    }

    // Multiple targets, user must specify
    let targetList = result.executables.map { "  - \($0)" }.joined(separator: "\n")
    throw ValidationError(
      "Multiple executable targets found. Please specify one:\n\(targetList)\n\nUsage: velox dev <target>"
    )
  }

  private func effectiveDevUrl(from config: VeloxConfig) -> String? {
    // Port override takes precedence
    if let port = port, let baseUrl = config.build?.devUrl {
      if let url = URL(string: baseUrl),
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      {
        components.port = port
        return components.string
      }
    }
    return config.build?.devUrl
  }

  // Store signal sources to prevent deallocation
  private static var signalSources: [DispatchSourceSignal] = []

  private func setupSignalHandlers(processManager: ProcessManager) {
    // Use global queue instead of main - main run loop may not be running in async context
    let signalQueue = DispatchQueue(label: "com.velox.signals")

    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    signal(SIGINT, SIG_IGN)
    signalSource.setEventHandler {
      logger.info("\n[shutdown] Received SIGINT, cleaning up...")
      Task {
        await processManager.terminateAll()
        Darwin.exit(0)
      }
    }
    signalSource.resume()
    DevCommand.signalSources.append(signalSource)

    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
    signal(SIGTERM, SIG_IGN)
    termSource.setEventHandler {
      logger.info("\n[shutdown] Received SIGTERM, cleaning up...")
      Task {
        await processManager.terminateAll()
        Darwin.exit(0)
      }
    }
    termSource.resume()
    DevCommand.signalSources.append(termSource)
  }
}
