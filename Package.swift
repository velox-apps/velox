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
      name: "VeloxBundler",
      targets: ["VeloxBundler"]
    ),
    .library(
      name: "VeloxMacros",
      targets: ["VeloxMacros"]
    ),
    .library(
      name: "VeloxRuntimeWry",
      targets: ["VeloxRuntimeWry"]
    ),
    .library(
      name: "VeloxPlugins",
      targets: ["VeloxPlugins"]
    ),
    .library(
      name: "VeloxPluginDialog",
      targets: ["VeloxPluginDialog"]
    ),
    .library(
      name: "VeloxPluginClipboard",
      targets: ["VeloxPluginClipboard"]
    ),
    .library(
      name: "VeloxPluginNotification",
      targets: ["VeloxPluginNotification"]
    ),
    .library(
      name: "VeloxPluginShell",
      targets: ["VeloxPluginShell"]
    ),
    .library(
      name: "VeloxPluginOS",
      targets: ["VeloxPluginOS"]
    ),
    .library(
      name: "VeloxPluginProcess",
      targets: ["VeloxPluginProcess"]
    ),
    .library(
      name: "VeloxPluginOpener",
      targets: ["VeloxPluginOpener"]
    ),
    .library(
      name: "VeloxPluginResources",
      targets: ["VeloxPluginResources"]
    ),
    .library(
      name: "VeloxPluginMenu",
      targets: ["VeloxPluginMenu"]
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
      name: "ChannelStreaming",
      targets: ["ChannelStreaming"]
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
      name: "BuiltinPlugins",
      targets: ["BuiltinPlugins"]
    ),
    .executable(
      name: "Permissions",
      targets: ["Permissions"]
    ),
    .executable(
      name: "velox",
      targets: ["VeloxCLI"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
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
      name: "VeloxBundler",
      dependencies: [
        "VeloxRuntime",
        .product(name: "Logging", package: "swift-log")
      ],
      path: "Sources/VeloxBundler"
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
    .target(
      name: "VeloxPluginDialog",
      dependencies: ["VeloxRuntime", "VeloxRuntimeWry"],
      path: "Sources/VeloxPluginDialog",
      exclude: ["DIALOG_LIMITATIONS.md"]
    ),
    .target(
      name: "VeloxPluginClipboard",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginClipboard"
    ),
    .target(
      name: "VeloxPluginNotification",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginNotification"
    ),
    .target(
      name: "VeloxPluginShell",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginShell"
    ),
    .target(
      name: "VeloxPluginOS",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginOS"
    ),
    .target(
      name: "VeloxPluginProcess",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginProcess"
    ),
    .target(
      name: "VeloxPluginOpener",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginOpener"
    ),
    .target(
      name: "VeloxPluginResources",
      dependencies: ["VeloxRuntime"],
      path: "Sources/VeloxPluginResources"
    ),
    .target(
      name: "VeloxPluginMenu",
      dependencies: ["VeloxRuntime", "VeloxRuntimeWry"],
      path: "Sources/VeloxPluginMenu"
    ),
    .target(
      name: "VeloxPlugins",
      dependencies: [
        "VeloxPluginDialog",
        "VeloxPluginClipboard",
        "VeloxPluginNotification",
        "VeloxPluginShell",
        "VeloxPluginOS",
        "VeloxPluginProcess",
        "VeloxPluginOpener"
      ],
      path: "Sources/VeloxPlugins"
    ),
    .testTarget(
      name: "VeloxRuntimeWryTests",
      dependencies: ["VeloxRuntimeWry"],
      path: "Tests/VeloxRuntimeWryTests"
    ),
    .executableTarget(
      name: "HelloWorld",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/HelloWorld",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "State",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/State",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "MultiWindow",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/MultiWindow",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Splashscreen",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Splashscreen",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "RunReturn",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/RunReturn",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Streaming",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Streaming",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "ChannelStreaming",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/ChannelStreaming",
      resources: [
        .copy("velox.json")
      ]
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
        .copy("assets"),
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Resources",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Resources",
      resources: [
        .copy("resources"),
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "WindowControls",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/WindowControls",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "MultiWebView",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/MultiWebView",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "DynamicHTML",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/DynamicHTML",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Events",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Events",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Tray",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Tray",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "CommandsManualRegistry",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/CommandsManualRegistry",
      exclude: ["README.md"],
      resources: [
        .copy("assets"),
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Commands",
      dependencies: ["VeloxRuntimeWry", "VeloxMacros"],
      path: "Examples/Commands",
      exclude: ["README.md"],
      resources: [
        .copy("assets"),
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Plugins",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Plugins",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "BuiltinPlugins",
      dependencies: ["VeloxRuntimeWry", "VeloxPlugins"],
      path: "Examples/BuiltinPlugins",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "Permissions",
      dependencies: ["VeloxRuntimeWry"],
      path: "Examples/Permissions",
      resources: [
        .copy("velox.json")
      ]
    ),
    .executableTarget(
      name: "VeloxCLI",
      dependencies: [
        "VeloxBundler",
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
