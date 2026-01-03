import ArgumentParser
import Darwin
import Foundation
import VeloxRuntime

/// Log with immediate flush to ensure output appears before subprocess output
private func log(_ message: String) {
  // Write to stderr for immediate output (unbuffered)
  fputs(message + "\n", stderr)
}

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

  @Argument(help: "Executable target to run (auto-detected if omitted)")
  var target: String?

  func run() async throws {
    log("Velox Dev")
    log("=========")

    // 1. Load configuration
    let config: VeloxConfig
    do {
      config = try VeloxConfig.load()
      log("[config] Loaded velox.json")
    } catch {
      throw ValidationError("No velox.json found. Run from project root.\n\(error)")
    }

    // 2. Detect or validate target
    let (executableTarget, packageDirectory) = try resolveTarget()
    log("[target] Using executable: \(executableTarget)")
    log("[package] Package directory: \(packageDirectory.path)")

    // 3. Set up process manager
    let processManager = ProcessManager()

    // Set up signal handlers for graceful shutdown
    setupSignalHandlers(processManager: processManager)

    // 4. Run beforeDevCommand if configured
    if let beforeDevCommand = config.build?.beforeDevCommand {
      log("[hook] Running beforeDevCommand: \(beforeDevCommand)")
      try await processManager.spawnBackgroundProcess(
        command: beforeDevCommand,
        label: "beforeDevCommand"
      )
      // Give it a moment to start
      try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }

    // 5. Wait for dev server if devUrl is configured
    if let devUrl = effectiveDevUrl(from: config) {
      log("[server] Waiting for dev server at \(devUrl)...")
      let checker = DevServerChecker(url: devUrl)
      let available = await checker.waitUntilAvailable(timeout: 60, retryInterval: 1)
      if !available {
        throw ValidationError("Dev server not responding at \(devUrl) after 60 seconds")
      }
      log("[server] Dev server is ready")
    }

    // 6. Start file watcher (unless disabled)
    var fileWatcher: FileWatcher?
    if !noWatch {
      fileWatcher = FileWatcher(paths: ["Sources", "velox.json"])
    }

    // 7. Build and run loop
    var shouldExit = false
    while !shouldExit {
      do {
        log("[build] Building and running \(executableTarget)...")
        let devUrl = effectiveDevUrl(from: config)
        try await processManager.runSwiftApp(
          target: executableTarget,
          release: release,
          devUrl: devUrl,
          packageDirectory: packageDirectory
        )

        // App exited normally, check if we should restart
        if noWatch {
          shouldExit = true
        } else {
          log("[watch] App exited. Waiting for file changes...")
          await fileWatcher?.waitForChange()
          log("[watch] Changes detected, rebuilding...")
        }
      } catch let error as ProcessManager.ProcessError {
        switch error {
        case .buildFailed(let output):
          log("[error] Build failed:\n\(output)")
          if noWatch {
            throw error
          }
          log("[watch] Waiting for file changes to retry...")
          await fileWatcher?.waitForChange()
          log("[watch] Changes detected, rebuilding...")
        case .terminated:
          // Process was killed (likely by us), continue loop
          break
        case .runtimeError(let output):
          log("[error] Runtime error:\n\(output)")
          if noWatch {
            throw error
          }
          log("[watch] Waiting for file changes to restart...")
          await fileWatcher?.waitForChange()
          log("[watch] Changes detected, rebuilding...")
        }
      }
    }

    // Cleanup
    await processManager.terminateAll()
    log("[done] Velox dev stopped")
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

  private func setupSignalHandlers(processManager: ProcessManager) {
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signal(SIGINT, SIG_IGN)
    signalSource.setEventHandler {
      log("\n[shutdown] Received SIGINT, cleaning up...")
      Task {
        await processManager.terminateAll()
        Darwin.exit(0)
      }
    }
    signalSource.resume()

    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    signal(SIGTERM, SIG_IGN)
    termSource.setEventHandler {
      log("\n[shutdown] Received SIGTERM, cleaning up...")
      Task {
        await processManager.terminateAll()
        Darwin.exit(0)
      }
    }
    termSource.resume()
  }
}
