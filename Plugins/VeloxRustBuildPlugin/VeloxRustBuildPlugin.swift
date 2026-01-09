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
    let stampFile = outputDirectory.appending("velox-runtime-wry-ffi.stamp")
    let cargoProfile = isReleaseConfiguration() ? "release" : "debug"

    var scriptLines = ["set -euo pipefail"]
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
      scriptLines.append("export PATH=\"$PATH:\(home)/.cargo/bin\"")
    }
    if shouldUseOfflineCargo() {
      scriptLines.append("export CARGO_NET_OFFLINE=true")
      scriptLines.append("echo '[VeloxRustBuildPlugin] cargo offline mode enabled'")
    }
    scriptLines.append("echo '[VeloxRustBuildPlugin] PATH='\"$PATH\"")
    scriptLines.append("cd \"\(context.package.directory.string)\"")
    scriptLines.append("mkdir -p \"runtime-wry-ffi/target/\(cargoProfile)\"")
    scriptLines.append("if ! command -v cargo >/dev/null; then")
    scriptLines.append("  echo '[VeloxRustBuildPlugin] error: cargo executable not found' 1>&2")
    scriptLines.append("  exit 1")
    scriptLines.append("fi")

    var buildCommand = "cargo build --manifest-path \"\(manifest.string)\" --target-dir \"\(cargoTargetDirectory.string)\" --locked"
    if shouldUseOfflineCargo() {
      buildCommand += " --offline"
    }
    if isReleaseConfiguration() {
      buildCommand += " --release"
    }
    // Enable local-dev feature when VELOX_LOCAL_DEV=1 (for testing with patched tao/wry)
    if ProcessInfo.processInfo.environment["VELOX_LOCAL_DEV"] == "1" {
      buildCommand += " --features local-dev"
    }
    scriptLines.append(buildCommand)
    scriptLines.append("touch \"\(stampFile.string)\"")

    let script = scriptLines.joined(separator: "\n") + "\n"

    return [
      .prebuildCommand(
        displayName: "Building velox-runtime-wry-ffi (Rust)",
        executable: Path("/bin/sh"),
        arguments: ["-c", script],
        environment: [:],
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
    let stampFile = outputDirectory.appending("velox-runtime-wry-ffi.stamp")
    let cargoProfile = isReleaseConfiguration() ? "release" : "debug"

    var scriptLines = ["set -euo pipefail"]
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
      scriptLines.append("export PATH=\"$PATH:\(home)/.cargo/bin\"")
    }
    if shouldUseOfflineCargo() {
      scriptLines.append("export CARGO_NET_OFFLINE=true")
      scriptLines.append("echo '[VeloxRustBuildPlugin] cargo offline mode enabled'")
    }
    scriptLines.append("echo '[VeloxRustBuildPlugin] PATH='\"$PATH\"")
    scriptLines.append("cd \"\(context.xcodeProject.directory.string)\"")
    scriptLines.append("mkdir -p \"runtime-wry-ffi/target/\(cargoProfile)\"")
    scriptLines.append("if ! command -v cargo >/dev/null; then")
    scriptLines.append("  echo '[VeloxRustBuildPlugin] error: cargo executable not found' 1>&2")
    scriptLines.append("  exit 1")
    scriptLines.append("fi")

    var buildCommand = "cargo build --manifest-path \"\(manifest.string)\" --target-dir \"\(cargoTargetDirectory.string)\" --locked"
    if shouldUseOfflineCargo() {
      buildCommand += " --offline"
    }
    if isReleaseConfiguration() {
      buildCommand += " --release"
    }
    // Enable local-dev feature when VELOX_LOCAL_DEV=1 (for testing with patched tao/wry)
    if ProcessInfo.processInfo.environment["VELOX_LOCAL_DEV"] == "1" {
      buildCommand += " --features local-dev"
    }
    scriptLines.append(buildCommand)
    scriptLines.append("touch \"\(stampFile.string)\"")

    let script = scriptLines.joined(separator: "\n") + "\n"

    return [
      .prebuildCommand(
        displayName: "Building velox-runtime-wry-ffi (Rust)",
        executable: Path("/bin/sh"),
        arguments: ["-c", script],
        environment: [:],
        outputFilesDirectory: outputDirectory
      ),
    ]
  }
}
#endif
