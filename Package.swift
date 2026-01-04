// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "VeloxRuntimeWry",
  platforms: [
    .macOS(.v13),
    .iOS(.v16)
  ],
  products: [
    .library(
      name: "VeloxRuntime",
      targets: ["VeloxRuntime"]
    ),
    .library(
      name: "VeloxMacros",
      targets: ["VeloxMacros"]
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
    ),
    .executable(
      name: "CommandsManual",
      targets: ["CommandsManual"]
    ),
    .executable(
      name: "Resources",
      targets: ["Resources"]
    ),
    .executable(
      name: "WindowControls",
      targets: ["WindowControls"]
    ),
    .executable(
      name: "MultiWebView",
      targets: ["MultiWebView"]
    ),
    .executable(
      name: "DynamicHTML",
      targets: ["DynamicHTML"]
    ),
    .executable(
      name: "Events",
      targets: ["Events"]
    ),
    .executable(
      name: "Tray",
      targets: ["Tray"]
    ),
    .executable(
      name: "CommandsManualRegistry",
      targets: ["CommandsManualRegistry"]
    ),
    .executable(
      name: "Commands",
      targets: ["Commands"]
    ),
    .executable(
      name: "Plugins",
      targets: ["Plugins"]
    ),
    .executable(
      name: "velox",
      targets: ["VeloxCLI"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
  ],
  targets: [
    // Macro implementation (compiler plugin)
    .macro(
      name: "VeloxMacrosImpl",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
      ],
      path: "Sources/VeloxMacrosImpl"
    ),
    // Macro declarations (client-facing)
    .target(
      name: "VeloxMacros",
      dependencies: ["VeloxMacrosImpl", "VeloxRuntime"],
      path: "Sources/VeloxMacros"
    ),
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
      path: "Examples/HelloWorld2",
      resources: [
        .copy("assets"),
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "CommandsManual",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/CommandsManual",
      exclude: ["README.md"],
      resources: [
        .copy("assets")
      ]
    ),
    .executableTarget(
      name: "Resources",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Resources",
      resources: [
        .copy("resources")
      ]
    ),
    .executableTarget(
      name: "WindowControls",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/WindowControls"
    ),
    .executableTarget(
      name: "MultiWebView",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/MultiWebView"
    ),
    .executableTarget(
      name: "DynamicHTML",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/DynamicHTML"
    ),
    .executableTarget(
      name: "Events",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Events"
    ),
    .executableTarget(
      name: "Tray",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Tray"
    ),
    .executableTarget(
      name: "CommandsManualRegistry",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/CommandsManualRegistry",
      exclude: ["README.md"],
      resources: [
        .copy("assets")
      ]
    ),
    .executableTarget(
      name: "Commands",
      dependencies: ["VeloxRuntimeWry", "VeloxMacros"],
      path: "Examples/Commands",
      exclude: ["README.md"],
      resources: [
        .copy("assets")
      ]
    ),
    .executableTarget(
      name: "Plugins",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Plugins"
    ),
    .executableTarget(
      name: "VeloxCLI",
      dependencies: [
        "VeloxRuntime",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log")
      ],
      path: "Sources/VeloxCLI"
    ),
    .plugin(
      name: "VeloxRustBuildPlugin",
      capability: .buildTool()
    )
  ]
)
