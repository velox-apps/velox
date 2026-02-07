import Foundation
import Logging
import VeloxRuntime

public struct VeloxBundler {
  public struct Output {
    public let bundleURL: URL
    public let dmgURL: URL?

    public init(bundleURL: URL, dmgURL: URL?) {
      self.bundleURL = bundleURL
      self.dmgURL = dmgURL
    }
  }

  public let logger: Logger

  public init(logger: Logger) {
    self.logger = logger
  }

  public func resolveBundleTargets(
    bundleFlag: Bool,
    bundleConfig: BundleConfig?
  ) -> Set<BundleTarget> {
    var targets = Set(bundleConfig?.targets ?? [])
    if bundleFlag || (bundleConfig?.active ?? false) {
      targets.insert(.app)
    }
    if bundleConfig?.macos?.dmg?.enabled == true {
      targets.insert(.dmg)
    }
    if targets.contains(.dmg) {
      targets.insert(.app)
    }
    return targets
  }

  public func createBundle(
    target: String,
    config: VeloxConfig,
    bundleConfig: BundleConfig?,
    configuration: String,
    packageDirectory: URL,
    bundleTargets: Set<BundleTarget>
  ) throws -> Output {
    #if os(macOS)
    logger.info("[bundle] Creating app bundle...")
    let bundleURL = try createAppBundle(
      target: target,
      config: config,
      bundleConfig: bundleConfig,
      configuration: configuration,
      packageDirectory: packageDirectory
    )
    logger.info("[bundle] App bundle created")

    if let signingIdentity = bundleConfig?.macos?.signingIdentity {
      logger.info("[bundle] Code signing with identity: \(signingIdentity)")
      let entitlementsPath = bundleConfig?.macos?.entitlements
      let entitlementsURL = entitlementsPath.map { resolvePath($0, base: packageDirectory) }
      let hardenedRuntime = bundleConfig?.macos?.hardenedRuntime ?? false
      try signAppBundle(
        bundleURL: bundleURL,
        identity: signingIdentity,
        entitlements: entitlementsURL,
        hardenedRuntime: hardenedRuntime
      )
      logger.info("[bundle] Code signing complete")
    }

    var dmgURL: URL?
    if bundleTargets.contains(.dmg) {
      let dmgConfig = bundleConfig?.macos?.dmg
      let dmgName = dmgConfig?.name ?? bundleURL.deletingPathExtension().lastPathComponent
      let volumeName = dmgConfig?.volumeName
        ?? config.productName
        ?? bundleURL.deletingPathExtension().lastPathComponent
      dmgURL = try createDmg(
        bundleURL: bundleURL,
        dmgName: dmgName,
        volumeName: volumeName,
        buildDirectory: packageDirectory
          .appendingPathComponent(".build")
          .appendingPathComponent(configuration)
      )
      logger.info("[bundle] DMG created: \(dmgURL?.path ?? "")")
    }

    if let notarization = bundleConfig?.macos?.notarization {
      logger.info("[bundle] Notarizing bundle...")
      try notarizeBundle(
        bundleURL: bundleURL,
        dmgURL: dmgURL,
        config: notarization,
        buildDirectory: packageDirectory
          .appendingPathComponent(".build")
          .appendingPathComponent(configuration)
      )
      logger.info("[bundle] Notarization complete")
    }

    return Output(bundleURL: bundleURL, dmgURL: dmgURL)
    #else
    throw VeloxBundlerError("App bundles are only supported on macOS")
    #endif
  }

  #if os(macOS)
  private func createAppBundle(
    target: String,
    config: VeloxConfig,
    bundleConfig: BundleConfig?,
    configuration: String,
    packageDirectory: URL
  ) throws -> URL {
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
    let veloxJsonSource = packageDirectory.appendingPathComponent("velox.json")
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
      let assetsSource = packageDirectory.appendingPathComponent(frontendDist)
      let assetsDest = resourcesPath.appendingPathComponent(frontendDist)

      if FileManager.default.fileExists(atPath: assetsSource.path) {
        if FileManager.default.fileExists(atPath: assetsDest.path) {
          try FileManager.default.removeItem(at: assetsDest)
        }
        // Ensure parent directory exists for nested frontendDist paths like "frontend/dist"
        let assetsDestParent = assetsDest.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: assetsDestParent.path) {
          try FileManager.default.createDirectory(at: assetsDestParent, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: assetsSource, to: assetsDest)
        logger.info("[bundle] Copied assets from \(frontendDist)")
      }
    }

    // Copy additional resources
    if let resources = bundleConfig?.resources, !resources.isEmpty {
      try copyBundleResources(resources, from: packageDirectory, to: resourcesPath)
    }

    // Copy icon
    let iconName = try copyBundleIcon(bundleConfig?.icon, from: packageDirectory, to: resourcesPath)

    // Create Info.plist
    let infoPlist = try createInfoPlist(
      config: config,
      bundleConfig: bundleConfig,
      executableName: target,
      iconName: iconName,
      baseDirectory: packageDirectory
    )
    let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
    try infoPlist.write(to: infoPlistPath)

    logger.info("[bundle] Created: \(bundlePath.path)")
    return bundlePath
  }

  private func createInfoPlist(
    config: VeloxConfig,
    bundleConfig: BundleConfig?,
    executableName: String,
    iconName: String?,
    baseDirectory: URL
  ) throws -> Data {
    let bundleId = config.identifier
    let bundleName = config.productName ?? executableName
    let version = config.version ?? "1.0.0"

    let minimumSystemVersion = bundleConfig?.macos?.minimumSystemVersion ?? "13.0"

    var plist: [String: Any] = [
      "CFBundleExecutable": executableName,
      "CFBundleIdentifier": bundleId,
      "CFBundleName": bundleName,
      "CFBundleDisplayName": bundleName,
      "CFBundleVersion": version,
      "CFBundleShortVersionString": version,
      "CFBundlePackageType": "APPL",
      "CFBundleInfoDictionaryVersion": "6.0",
      "LSMinimumSystemVersion": minimumSystemVersion,
      "NSHighResolutionCapable": true,
      "NSSupportsAutomaticGraphicsSwitching": true
    ]

    if let iconName {
      plist["CFBundleIconFile"] = iconName
    }

    if let infoPlistPath = bundleConfig?.macos?.infoPlist {
      let infoPlistURL = resolvePath(infoPlistPath, base: baseDirectory)
      let data = try Data(contentsOf: infoPlistURL)
      let custom = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
      guard let customDict = custom as? [String: Any] else {
        throw VeloxBundlerError("Custom Info.plist must be a dictionary: \(infoPlistURL.path)")
      }
      mergePlist(&plist, override: customDict)
    }

    return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  }

  private func mergePlist(_ base: inout [String: Any], override: [String: Any]) {
    for (key, value) in override {
      if let baseDict = base[key] as? [String: Any], let valueDict = value as? [String: Any] {
        var merged = baseDict
        mergePlist(&merged, override: valueDict)
        base[key] = merged
      } else {
        base[key] = value
      }
    }
  }

  private func copyBundleResources(_ resources: [String], from base: URL, to resourcesPath: URL) throws {
    for resource in resources {
      let sourceURL = resolvePath(resource, base: base)
      guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        logger.warning("[bundle] Resource not found: \(sourceURL.path)")
        continue
      }
      let destURL = resourcesPath.appendingPathComponent(sourceURL.lastPathComponent)
      if FileManager.default.fileExists(atPath: destURL.path) {
        try FileManager.default.removeItem(at: destURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destURL)
      logger.info("[bundle] Copied resource: \(sourceURL.lastPathComponent)")
    }
  }

  private func copyBundleIcon(
    _ icon: BundleIcon?,
    from base: URL,
    to resourcesPath: URL
  ) throws -> String? {
    guard let iconPath = icon?.paths.first else {
      return nil
    }

    let sourceURL = resolvePath(iconPath, base: base)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      logger.warning("[bundle] Icon not found: \(sourceURL.path)")
      return nil
    }

    let destURL = resourcesPath.appendingPathComponent(sourceURL.lastPathComponent)
    if FileManager.default.fileExists(atPath: destURL.path) {
      try FileManager.default.removeItem(at: destURL)
    }
    try FileManager.default.copyItem(at: sourceURL, to: destURL)
    logger.info("[bundle] Copied icon: \(sourceURL.lastPathComponent)")

    return destURL.deletingPathExtension().lastPathComponent
  }

  private func signAppBundle(
    bundleURL: URL,
    identity: String,
    entitlements: URL?,
    hardenedRuntime: Bool
  ) throws {
    var args = [
      "--force",
      "--sign", identity
    ]

    if hardenedRuntime {
      args.append("--options")
      args.append("runtime")
    }

    if let entitlements {
      guard FileManager.default.fileExists(atPath: entitlements.path) else {
        throw VeloxBundlerError("Entitlements file not found: \(entitlements.path)")
      }
      args.append("--entitlements")
      args.append(entitlements.path)
    }

    args.append("--timestamp")
    args.append(bundleURL.path)

    let exitCode = try runProcess(
      executable: "/usr/bin/codesign",
      arguments: args
    )
    if exitCode != 0 {
      throw VeloxBundlerError("codesign failed with exit code \(exitCode)")
    }
  }

  private func createDmg(
    bundleURL: URL,
    dmgName: String,
    volumeName: String,
    buildDirectory: URL
  ) throws -> URL {
    let dmgURL = buildDirectory.appendingPathComponent("\(dmgName).dmg")
    if FileManager.default.fileExists(atPath: dmgURL.path) {
      try FileManager.default.removeItem(at: dmgURL)
    }

    let args = [
      "create",
      "-volname", volumeName,
      "-srcfolder", bundleURL.path,
      "-ov",
      "-format", "UDZO",
      dmgURL.path
    ]

    let exitCode = try runProcess(
      executable: "/usr/bin/hdiutil",
      arguments: args
    )
    if exitCode != 0 {
      throw VeloxBundlerError("hdiutil failed with exit code \(exitCode)")
    }

    return dmgURL
  }

  private func notarizeBundle(
    bundleURL: URL,
    dmgURL: URL?,
    config: NotarizationConfig,
    buildDirectory: URL
  ) throws {
    let artifactURL: URL
    if let dmgURL {
      artifactURL = dmgURL
    } else {
      let zipURL = buildDirectory.appendingPathComponent(
        "\(bundleURL.deletingPathExtension().lastPathComponent).zip"
      )
      if FileManager.default.fileExists(atPath: zipURL.path) {
        try FileManager.default.removeItem(at: zipURL)
      }
      let exitCode = try runProcess(
        executable: "/usr/bin/ditto",
        arguments: ["-c", "-k", "--keepParent", bundleURL.path, zipURL.path]
      )
      if exitCode != 0 {
        throw VeloxBundlerError("ditto failed with exit code \(exitCode)")
      }
      artifactURL = zipURL
    }

    var args = ["notarytool", "submit", artifactURL.path]
    if let keychainProfile = config.keychainProfile {
      args.append(contentsOf: ["--keychain-profile", keychainProfile])
    } else if let appleId = config.appleId,
              let teamId = config.teamId,
              let password = config.password
    {
      args.append(contentsOf: ["--apple-id", appleId, "--team-id", teamId, "--password", password])
    } else {
      throw VeloxBundlerError("Notarization requires keychainProfile or appleId/teamId/password")
    }

    if config.wait ?? true {
      args.append("--wait")
    }

    let submitExit = try runProcess(
      executable: "/usr/bin/xcrun",
      arguments: args
    )
    if submitExit != 0 {
      throw VeloxBundlerError("notarytool failed with exit code \(submitExit)")
    }

    if config.staple ?? true {
      let stapleExit = try runProcess(
        executable: "/usr/bin/xcrun",
        arguments: ["stapler", "staple", bundleURL.path]
      )
      if stapleExit != 0 {
        throw VeloxBundlerError("stapler failed with exit code \(stapleExit)")
      }
    }
  }

  private func resolvePath(_ path: String, base: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
      return URL(fileURLWithPath: expanded)
    }
    return base.appendingPathComponent(path)
  }

  private func runProcess(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
  ) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

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
  #endif
}

public struct VeloxBundlerError: LocalizedError {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? {
    message
  }
}
