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
      name: "VeloxRuntime",
      targets: ["VeloxRuntime"]
    ),
    .library(
      name: "VeloxRuntimeWry",
      targets: ["VeloxRuntimeWry"]
    ),
    .executable(
      name: "HelloWorld",
      targets: ["HelloWorld"]
    ),
    .executable(
      name: "State",
      targets: ["State"]
    ),
    .executable(
      name: "MultiWindow",
      targets: ["MultiWindow"]
    ),
    .executable(
      name: "Splashscreen",
      targets: ["Splashscreen"]
    ),
    .executable(
      name: "RunReturn",
      targets: ["RunReturn"]
    ),
    .executable(
      name: "Streaming",
      targets: ["Streaming"]
    ),
    .executable(
      name: "HelloWorld2",
      targets: ["HelloWorld2"]
    )
  ],
  targets: [
    .target(
      name: "VeloxRuntime",
      path: "Sources/VeloxRuntime"
    ),
    .target(
      name: "VeloxRuntimeWryFFI",
      path: "Sources/VeloxRuntimeWryFFI",
      publicHeadersPath: ".",
      plugins: ["VeloxRustBuildPlugin"]
    ),
    .target(
      name: "VeloxRuntimeWry",
      dependencies: ["VeloxRuntime", "VeloxRuntimeWryFFI"],
      path: "Sources/VeloxRuntimeWry",
      linkerSettings: [
        .unsafeFlags([
          "-L",
          ".build/plugins/outputs/velox/VeloxRuntimeWryFFI/destination/VeloxRustBuildPlugin/Artifacts/cargo-target/debug",
          "-L",
          "runtime-wry-ffi/target/debug",
        ], .when(configuration: .debug)),
        .unsafeFlags([
          "-L",
          ".build/plugins/outputs/velox/VeloxRuntimeWryFFI/destination/VeloxRustBuildPlugin/Artifacts/cargo-target/release",
          "-L",
          "runtime-wry-ffi/target/release",
        ], .when(configuration: .release)),
        .linkedLibrary("velox_runtime_wry_ffi")
      ]
    ),
    .testTarget(
      name: "VeloxRuntimeWryTests",
      dependencies: ["VeloxRuntimeWry"],
      path: "Tests/VeloxRuntimeWryTests"
    ),
    .executableTarget(
      name: "HelloWorld",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/HelloWorld"
    ),
    .executableTarget(
      name: "State",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/State"
    ),
    .executableTarget(
      name: "MultiWindow",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/MultiWindow"
    ),
    .executableTarget(
      name: "Splashscreen",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Splashscreen"
    ),
    .executableTarget(
      name: "RunReturn",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/RunReturn"
    ),
    .executableTarget(
      name: "Streaming",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Streaming"
    ),
    .executableTarget(
      name: "HelloWorld2",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/HelloWorld2"
    ),
    .plugin(
      name: "VeloxRustBuildPlugin",
      capability: .buildTool()
    )
  ]
)
