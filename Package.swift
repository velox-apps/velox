// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VeloxRuntimeWry",
  platforms: [
    .macOS(.v12),
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "VeloxRuntimeWry",
      targets: ["VeloxRuntimeWry"]
    )
  ],
  targets: [
    .target(
      name: "VeloxRuntimeWryFFI",
      path: "Sources/VeloxRuntimeWryFFI",
      publicHeadersPath: ".",
      plugins: ["VeloxRustBuildPlugin"]
    ),
    .target(
      name: "VeloxRuntimeWry",
      dependencies: ["VeloxRuntimeWryFFI"],
      path: "Sources/VeloxRuntimeWry",
      linkerSettings: [
        .unsafeFlags(["-L", "runtime-wry-ffi/target/debug"], .when(configuration: .debug)),
        .unsafeFlags(["-L", "runtime-wry-ffi/target/release"], .when(configuration: .release)),
        .unsafeFlags([
          "-L",
          ".build/plugins/outputs/velox/VeloxRuntimeWryFFI/destination/VeloxRustBuildPlugin/Artifacts/cargo-target/debug",
        ], .when(configuration: .debug)),
        .unsafeFlags([
          "-L",
          ".build/plugins/outputs/velox/VeloxRuntimeWryFFI/destination/VeloxRustBuildPlugin/Artifacts/cargo-target/release",
        ], .when(configuration: .release)),
        .linkedLibrary("velox_runtime_wry_ffi")
      ]
    ),
    .testTarget(
      name: "VeloxRuntimeWryTests",
      dependencies: ["VeloxRuntimeWry"],
      path: "Tests/VeloxRuntimeWryTests"
    ),
    .plugin(
      name: "VeloxRustBuildPlugin",
      capability: .buildTool()
    )
  ]
)
