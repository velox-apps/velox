import ArgumentParser
import Darwin
import Foundation
import Logging
import VeloxRuntime

/// Builds the Velox app for production distribution.
///
/// The build command:
/// 1. Loads `velox.json` configuration
/// 2. Runs `beforeBuildCommand` if configured
/// 3. Builds the Swift app with `swift build`
/// 4. Optionally creates a macOS `.app` bundle
///
/// Usage:
/// ```bash
/// # Build release
/// velox build
///
/// # Build debug
/// velox build --debug
///
/// # Build and create .app bundle (macOS)
/// velox build --bundle
///
/// # Specify target
/// velox build MyAppTarget --bundle
/// ```
struct BuildCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
    abstract: "Build the app for production"
  )

  @Flag(name: .long, help: "Build in debug mode instead of release")
  var debug: Bool = false

  @Flag(name: .long, help: "Create an app bundle (.app on macOS)")
  var bundle: Bool = false

  @Flag(name: .shortAndLong, help: "Enable verbose logging")
  var verbose: Bool = false

  @Argument(help: "Executable target to build (auto-detected if omitted)")
  var target: String?

  func run() async throws {
    configureLogger(verbose: verbose)
    logger.info("Velox Build")
    logger.info("===========")

    // 1. Load configuration
    let config: VeloxConfig
    do {
      config = try VeloxConfig.load()
      logger.info("[config] Loaded velox.json")
    } catch {
      throw ValidationError("No velox.json found. Run from project root.\n\(error)")
    }

    // 1.5. Load environment variables
    let mode = debug ? "development" : "production"
    let envVars = EnvLoader.load(config: config, mode: mode)
    if !envVars.isEmpty {
      logger.info("[env] Loaded \(envVars.count) environment variable(s)")
    }

    // 2. Detect or validate target
    let (executableTarget, packageDirectory) = try resolveTarget()
    logger.info("[target] Using executable: \(executableTarget)")

    // 3. Run beforeBuildCommand if configured
    if let beforeBuildCommand = config.build?.beforeBuildCommand {
      logger.info("[hook] Running beforeBuildCommand: \(beforeBuildCommand)")
      let exitCode = try await runShellCommand(beforeBuildCommand)
      if exitCode != 0 {
        throw ValidationError("beforeBuildCommand failed with exit code \(exitCode)")
      }
      logger.info("[hook] beforeBuildCommand completed")
    }

    // 4. Build the Swift app
    let configuration = debug ? "debug" : "release"
    logger.info("[build] Building \(executableTarget) in \(configuration) mode...")

    let buildExitCode = try await runSwiftBuild(
      target: executableTarget,
      configuration: configuration,
      packageDirectory: packageDirectory,
      additionalEnv: envVars
    )

    if buildExitCode != 0 {
      throw ValidationError("Build failed with exit code \(buildExitCode)")
    }

    logger.info("[build] Build completed successfully")

    // 5. Create app bundle if requested
    if bundle {
      #if os(macOS)
      // Run beforeBundleCommand if configured
      if let beforeBundleCommand = config.build?.beforeBundleCommand {
        logger.info("[hook] Running beforeBundleCommand: \(beforeBundleCommand)")
        let exitCode = try await runShellCommand(beforeBundleCommand)
        if exitCode != 0 {
          throw ValidationError("beforeBundleCommand failed with exit code \(exitCode)")
        }
        logger.info("[hook] beforeBundleCommand completed")
      }

      logger.info("[bundle] Creating app bundle...")
      try createAppBundle(
        target: executableTarget,
        config: config,
        configuration: configuration,
        packageDirectory: packageDirectory
      )
      logger.info("[bundle] App bundle created")
      #else
      logger.info("[bundle] App bundles are only supported on macOS")
      #endif
    }

    // Print output location
    let outputPath = packageDirectory
      .appendingPathComponent(".build")
      .appendingPathComponent(configuration)
      .appendingPathComponent(executableTarget)
    logger.info("[done] Output: \(outputPath.path)")
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

    let targetList = result.executables.map { "  - \($0)" }.joined(separator: "\n")
    throw ValidationError(
      "Multiple executable targets found. Please specify one:\n\(targetList)\n\nUsage: velox build <target>"
    )
  }

  private func runShellCommand(_ command: String) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Forward output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        FileHandle.standardOutput.write(data)
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        FileHandle.standardError.write(data)
      }
    }

    try process.run()
    process.waitUntilExit()

    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil

    return process.terminationStatus
  }

  private func runSwiftBuild(
    target: String,
    configuration: String,
    packageDirectory: URL,
    additionalEnv: [String: String] = [:]
  ) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = ["build", "-c", configuration, "--product", target, "--disable-sandbox"]
    process.currentDirectoryURL = packageDirectory

    // Set environment variables
    var env = ProcessInfo.processInfo.environment
    for (key, value) in additionalEnv {
      env[key] = value
    }
    process.environment = env

    // Forward output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        FileHandle.standardOutput.write(data)
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        FileHandle.standardError.write(data)
      }
    }

    try process.run()
    process.waitUntilExit()

    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil

    return process.terminationStatus
  }

  #if os(macOS)
  private func createAppBundle(
    target: String,
    config: VeloxConfig,
    configuration: String,
    packageDirectory: URL
  ) throws {
    let buildDir = packageDirectory
      .appendingPathComponent(".build")
      .appendingPathComponent(configuration)

    let executablePath = buildDir.appendingPathComponent(target)
    let appName = config.productName ?? target
    let bundlePath = buildDir.appendingPathComponent("\(appName).app")
    let contentsPath = bundlePath.appendingPathComponent("Contents")
    let macOSPath = contentsPath.appendingPathComponent("MacOS")
    let resourcesPath = contentsPath.appendingPathComponent("Resources")

    // Create directory structure
    try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resourcesPath, withIntermediateDirectories: true)

    // Copy executable
    let destExecutable = macOSPath.appendingPathComponent(target)
    if FileManager.default.fileExists(atPath: destExecutable.path) {
      try FileManager.default.removeItem(at: destExecutable)
    }
    try FileManager.default.copyItem(at: executablePath, to: destExecutable)

    // Copy velox.json to Resources
    let veloxJsonSource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("velox.json")
    let veloxJsonDest = resourcesPath.appendingPathComponent("velox.json")
    if FileManager.default.fileExists(atPath: veloxJsonSource.path) {
      if FileManager.default.fileExists(atPath: veloxJsonDest.path) {
        try FileManager.default.removeItem(at: veloxJsonDest)
      }
      try FileManager.default.copyItem(at: veloxJsonSource, to: veloxJsonDest)
      logger.info("[bundle] Copied velox.json")
    }

    // Copy assets if frontendDist is configured
    if let frontendDist = config.build?.frontendDist {
      let assetsSource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(frontendDist)
      let assetsDest = resourcesPath.appendingPathComponent(frontendDist)

      if FileManager.default.fileExists(atPath: assetsSource.path) {
        if FileManager.default.fileExists(atPath: assetsDest.path) {
          try FileManager.default.removeItem(at: assetsDest)
        }
        try FileManager.default.copyItem(at: assetsSource, to: assetsDest)
        logger.info("[bundle] Copied assets from \(frontendDist)")
      }
    }

    // Create Info.plist
    let infoPlist = createInfoPlist(config: config, executableName: target)
    let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
    try infoPlist.write(to: infoPlistPath, atomically: true, encoding: .utf8)

    logger.info("[bundle] Created: \(bundlePath.path)")
  }

  private func createInfoPlist(config: VeloxConfig, executableName: String) -> String {
    let bundleId = config.identifier
    let bundleName = config.productName ?? executableName
    let version = config.version ?? "1.0.0"

    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>\(executableName)</string>
        <key>CFBundleIdentifier</key>
        <string>\(bundleId)</string>
        <key>CFBundleName</key>
        <string>\(bundleName)</string>
        <key>CFBundleDisplayName</key>
        <string>\(bundleName)</string>
        <key>CFBundleVersion</key>
        <string>\(version)</string>
        <key>CFBundleShortVersionString</key>
        <string>\(version)</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>LSMinimumSystemVersion</key>
        <string>13.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSSupportsAutomaticGraphicsSwitching</key>
        <true/>
      </dict>
      </plist>
      """
  }
  #endif
}
