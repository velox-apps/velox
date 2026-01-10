import ArgumentParser
import Foundation
import Logging
import VeloxBundler
import VeloxRuntime

/// Creates app bundles for distribution.
struct BundleCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Create app bundles for distribution"
  )

  @Flag(name: .long, help: "Build in debug mode instead of release")
  var debug: Bool = false

  @Flag(name: .long, help: "Skip building; use existing build artifacts")
  var noBuild: Bool = false

  @Flag(name: .long, help: "Create a DMG bundle")
  var dmg: Bool = false

  @Flag(name: .shortAndLong, help: "Enable verbose logging")
  var verbose: Bool = false

  @Option(name: .long, help: "Override signing identity (Developer ID Application: ...)")
  var signingIdentity: String?

  @Option(name: .long, help: "Override entitlements plist path")
  var entitlements: String?

  @Flag(name: .long, help: "Enable hardened runtime for code signing")
  var hardenedRuntime: Bool = false

  @Option(name: .long, help: "Keychain profile name for notarytool")
  var notaryKeychainProfile: String?

  @Option(name: .long, help: "Apple ID for notarytool")
  var notaryAppleId: String?

  @Option(name: .long, help: "Team ID for notarytool")
  var notaryTeamId: String?

  @Option(name: .long, help: "App-specific password for notarytool")
  var notaryPassword: String?

  @Option(name: .long, help: "Custom DMG name (without extension)")
  var dmgName: String?

  @Option(name: .long, help: "DMG volume name")
  var dmgVolumeName: String?

  @Argument(help: "Executable target to bundle (auto-detected if omitted)")
  var target: String?

  func run() async throws {
    configureLogger(verbose: verbose)
    logger.info("Velox Bundle")
    logger.info("============")

    let config: VeloxConfig
    do {
      config = try VeloxConfig.load()
      logger.info("[config] Loaded velox.json")
    } catch {
      throw ValidationError("No velox.json found. Run from project root.\n\(error)")
    }

    let (executableTarget, packageDirectory) = try resolveTarget()
    logger.info("[target] Using executable: \(executableTarget)")

    let configuration = debug ? "debug" : "release"
    let effectiveConfig = applyBundleOverrides(to: config)

    if !noBuild {
      let mode = debug ? "development" : "production"
      let envVars = EnvLoader.load(config: effectiveConfig, mode: mode)
      if !envVars.isEmpty {
        logger.info("[env] Loaded \(envVars.count) environment variable(s)")
      }

      if let beforeBuildCommand = effectiveConfig.build?.beforeBuildCommand {
        logger.info("[hook] Running beforeBuildCommand: \(beforeBuildCommand)")
        let exitCode = try await runShellCommand(beforeBuildCommand)
        if exitCode != 0 {
          throw ValidationError("beforeBuildCommand failed with exit code \(exitCode)")
        }
        logger.info("[hook] beforeBuildCommand completed")
      }

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
    } else {
      let buildDir = packageDirectory
        .appendingPathComponent(".build")
        .appendingPathComponent(configuration)
      let executablePath = buildDir.appendingPathComponent(executableTarget)
      if !FileManager.default.fileExists(atPath: executablePath.path) {
        throw ValidationError("Missing build artifact at \(executablePath.path). Run velox build first.")
      }
    }

    #if os(macOS)
    if let beforeBundleCommand = effectiveConfig.build?.beforeBundleCommand {
      logger.info("[hook] Running beforeBundleCommand: \(beforeBundleCommand)")
      let exitCode = try await runShellCommand(beforeBundleCommand)
      if exitCode != 0 {
        throw ValidationError("beforeBundleCommand failed with exit code \(exitCode)")
      }
      logger.info("[hook] beforeBundleCommand completed")
    }

    let bundler = VeloxBundler(logger: logger)
    let bundleTargets = bundler.resolveBundleTargets(bundleFlag: true, bundleConfig: effectiveConfig.bundle)
    do {
      let output = try bundler.createBundle(
        target: executableTarget,
        config: effectiveConfig,
        bundleConfig: effectiveConfig.bundle,
        configuration: configuration,
        packageDirectory: packageDirectory,
        bundleTargets: bundleTargets
      )
      logger.info("[done] Bundle: \(output.bundleURL.path)")
      if let dmgURL = output.dmgURL {
        logger.info("[done] DMG: \(dmgURL.path)")
      }
    } catch {
      throw ValidationError(error.localizedDescription)
    }
    #else
    logger.info("[bundle] App bundles are only supported on macOS")
    #endif
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
      "Multiple executable targets found. Please specify one:\n\(targetList)\n\nUsage: velox bundle <target>"
    )
  }

  private func applyBundleOverrides(to config: VeloxConfig) -> VeloxConfig {
    let overrides = BundleOverrides(
      signingIdentity: resolvedString(signingIdentity, envKey: "SIGNING_IDENTITY"),
      entitlements: resolvedString(entitlements, envKey: "ENTITLEMENTS"),
      hardenedRuntime: resolvedHardenedRuntime(),
      notaryKeychainProfile: resolvedString(notaryKeychainProfile, envKey: "NOTARY_KEYCHAIN_PROFILE"),
      notaryAppleId: resolvedString(notaryAppleId, envKey: "NOTARY_APPLE_ID"),
      notaryTeamId: resolvedString(notaryTeamId, envKey: "NOTARY_TEAM_ID"),
      notaryPassword: resolvedString(notaryPassword, envKey: "NOTARY_PASSWORD"),
      dmgEnabled: resolvedDmgEnabled(),
      dmgName: resolvedString(dmgName, envKey: "DMG_NAME"),
      dmgVolumeName: resolvedString(dmgVolumeName, envKey: "DMG_VOLUME_NAME")
    )

    if overrides.isEmpty {
      return config
    }

    var config = config
    var bundle = config.bundle ?? BundleConfig()
    var macos = bundle.macos ?? MacOSBundleConfig()

    if let signingIdentity = overrides.signingIdentity {
      macos.signingIdentity = signingIdentity
    }
    if let entitlements = overrides.entitlements {
      macos.entitlements = entitlements
    }
    if let hardenedRuntime = overrides.hardenedRuntime {
      macos.hardenedRuntime = hardenedRuntime
    } else if overrides.signingIdentity != nil && macos.hardenedRuntime == nil {
      macos.hardenedRuntime = true
    }

    if overrides.hasNotarization {
      var notarization = macos.notarization ?? NotarizationConfig()
      if let value = overrides.notaryKeychainProfile {
        notarization.keychainProfile = value
      }
      if let value = overrides.notaryAppleId {
        notarization.appleId = value
      }
      if let value = overrides.notaryTeamId {
        notarization.teamId = value
      }
      if let value = overrides.notaryPassword {
        notarization.password = value
      }
      macos.notarization = notarization
    }

    if overrides.hasDmgOverrides {
      var dmgConfig = macos.dmg ?? DmgConfig()
      if let enabled = overrides.dmgEnabled {
        dmgConfig.enabled = enabled
      } else if dmgConfig.enabled == nil {
        dmgConfig.enabled = true
      }
      if let name = overrides.dmgName {
        dmgConfig.name = name
      }
      if let volumeName = overrides.dmgVolumeName {
        dmgConfig.volumeName = volumeName
      }
      macos.dmg = dmgConfig
    }

    bundle.macos = macos
    config.bundle = bundle
    return config
  }

  private func resolvedString(_ value: String?, envKey: String) -> String? {
    if let value, !value.isEmpty {
      return value
    }
    if let envValue = ProcessInfo.processInfo.environment[envKey], !envValue.isEmpty {
      return envValue
    }
    return nil
  }

  private func resolvedDmgEnabled() -> Bool? {
    if dmg {
      return true
    }
    return envBool("DMG_ENABLED")
  }

  private func resolvedHardenedRuntime() -> Bool? {
    if hardenedRuntime {
      return true
    }
    return envBool("HARDENED_RUNTIME")
  }

  private func envBool(_ key: String) -> Bool? {
    guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty
    else {
      return nil
    }
    switch raw.lowercased() {
    case "1", "true", "yes", "y", "on":
      return true
    case "0", "false", "no", "n", "off":
      return false
    default:
      return nil
    }
  }

  private func runShellCommand(_ command: String) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

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

    var env = ProcessInfo.processInfo.environment
    env["SWIFT_BUILD_CONFIGURATION"] = configuration
    env["CONFIGURATION"] = configuration
    for (key, value) in additionalEnv {
      env[key] = value
    }
    process.environment = env

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
}

private struct BundleOverrides {
  let signingIdentity: String?
  let entitlements: String?
  let hardenedRuntime: Bool?
  let notaryKeychainProfile: String?
  let notaryAppleId: String?
  let notaryTeamId: String?
  let notaryPassword: String?
  let dmgEnabled: Bool?
  let dmgName: String?
  let dmgVolumeName: String?

  var hasNotarization: Bool {
    notaryKeychainProfile != nil
      || notaryAppleId != nil
      || notaryTeamId != nil
      || notaryPassword != nil
  }

  var hasDmgOverrides: Bool {
    dmgEnabled != nil || dmgName != nil || dmgVolumeName != nil
  }

  var isEmpty: Bool {
    signingIdentity == nil
      && entitlements == nil
      && hardenedRuntime == nil
      && !hasNotarization
      && !hasDmgOverrides
  }
}
