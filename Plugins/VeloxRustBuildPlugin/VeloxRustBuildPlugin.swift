import Foundation
import PackagePlugin

private func isReleaseConfiguration() -> Bool {
  let environment = ProcessInfo.processInfo.environment
  let candidates = ["CONFIGURATION", "BUILD_CONFIGURATION", "SWIFT_BUILD_CONFIGURATION"]
  for key in candidates {
    if let value = environment[key], value.lowercased().contains("release") {
      return true
    }
  }
  return false
}

private func shouldUseOfflineCargo() -> Bool {
  let environment = ProcessInfo.processInfo.environment
  if environment["VELOX_CARGO_ONLINE"] == "1" {
    return false
  }
  if environment["VELOX_CARGO_OFFLINE"] == "1" {
    return true
  }
  let cargoOffline = environment["CARGO_NET_OFFLINE"]?.lowercased()
  if cargoOffline == "1" || cargoOffline == "true" {
    return true
  }
  return true
}

private func resolveCargoExecutable(environment: [String: String]) -> String? {
  let fileManager = FileManager.default

  func executableExtensions() -> [String] {
#if os(Windows)
    let pathExtensions = environment["PATHEXT"]?
      .split(separator: ";")
      .map { String($0).lowercased() } ?? [".exe", ".cmd", ".bat"]
    return [""] + pathExtensions
#else
    return [""]
#endif
  }

  func isExecutable(_ path: String) -> Bool {
    fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
  }

  func resolveInDirectory(_ directory: String, executable name: String) -> String? {
    for ext in executableExtensions() {
      let candidate = URL(fileURLWithPath: directory)
        .appendingPathComponent(name + ext)
        .path
      if isExecutable(candidate) {
        return candidate
      }
    }
    return nil
  }

  if let path = environment["PATH"] {
#if os(Windows)
    let separator: Character = ";"
#else
    let separator: Character = ":"
#endif
    for entry in path.split(separator: separator).map(String.init) where !entry.isEmpty {
      if let cargo = resolveInDirectory(entry, executable: "cargo") {
        return cargo
      }
    }
  }

  let homeDirectory: String? = environment["HOME"] ?? environment["USERPROFILE"]
  if let homeDirectory {
    let cargoBin = URL(fileURLWithPath: homeDirectory)
      .appendingPathComponent(".cargo")
      .appendingPathComponent("bin")
      .path
    if let cargo = resolveInDirectory(cargoBin, executable: "cargo") {
      return cargo
    }
  }

  return nil
}

private func cargoArguments(
  manifest: Path,
  cargoTargetDirectory: Path
) -> [String] {
  var arguments = [
    "build",
    "--manifest-path", manifest.string,
    "--target-dir", cargoTargetDirectory.string,
  ]
  if shouldUseOfflineCargo() {
    arguments.append("--offline")
  } else {
    arguments.append("--locked")
  }
  if isReleaseConfiguration() {
    arguments.append("--release")
  }
  if ProcessInfo.processInfo.environment["VELOX_LOCAL_DEV"] == "1" {
    arguments.append(contentsOf: ["--features", "local-dev"])
  }
  return arguments
}

private func cargoEnvironment() -> [String: String] {
  var environment = ProcessInfo.processInfo.environment
  if shouldUseOfflineCargo() {
    environment["CARGO_NET_OFFLINE"] = "true"
  }
  return environment
}

@main
struct VeloxRustBuildPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    if ProcessInfo.processInfo.environment["VELOX_SKIP_PLUGIN"] == "1" {
      Diagnostics.warning("Skipping VeloxRustBuildPlugin due to VELOX_SKIP_PLUGIN")
      return []
    }

    guard target.name == "VeloxRuntimeWryFFI" else {
      return []
    }

    let manifest = context.package.directory.appending("runtime-wry-ffi/Cargo.toml")
    let outputDirectory = context.pluginWorkDirectory.appending("Artifacts")
    let cargoTargetDirectory = outputDirectory.appending("cargo-target")
    let environment = ProcessInfo.processInfo.environment
    guard let cargoExecutable = resolveCargoExecutable(environment: environment) else {
      Diagnostics.error("VeloxRustBuildPlugin could not find a cargo executable in PATH or the standard Cargo install directory.")
      return []
    }

    return [
      .prebuildCommand(
        displayName: "Building velox-runtime-wry-ffi (Rust)",
        executable: Path(cargoExecutable),
        arguments: cargoArguments(
          manifest: manifest,
          cargoTargetDirectory: cargoTargetDirectory
        ),
        environment: cargoEnvironment(),
        outputFilesDirectory: outputDirectory
      ),
    ]
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension VeloxRustBuildPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(
    context: XcodePluginContext,
    target: XcodeTarget,
    inputFiles: [Path]
  ) throws -> [Command] {
    if ProcessInfo.processInfo.environment["VELOX_SKIP_PLUGIN"] == "1" {
      Diagnostics.warning("Skipping VeloxRustBuildPlugin due to VELOX_SKIP_PLUGIN")
      return []
    }

    guard target.displayName == "VeloxRuntimeWryFFI" else {
      return []
    }

    let manifest = context.xcodeProject.directory.appending("runtime-wry-ffi/Cargo.toml")
    let outputDirectory = context.pluginWorkDirectory.appending("Artifacts")
    let cargoTargetDirectory = outputDirectory.appending("cargo-target")
    let environment = ProcessInfo.processInfo.environment
    guard let cargoExecutable = resolveCargoExecutable(environment: environment) else {
      Diagnostics.error("VeloxRustBuildPlugin could not find a cargo executable in PATH or the standard Cargo install directory.")
      return []
    }

    return [
      .prebuildCommand(
        displayName: "Building velox-runtime-wry-ffi (Rust)",
        executable: Path(cargoExecutable),
        arguments: cargoArguments(
          manifest: manifest,
          cargoTargetDirectory: cargoTargetDirectory
        ),
        environment: cargoEnvironment(),
        outputFilesDirectory: outputDirectory
      ),
    ]
  }
}
#endif
