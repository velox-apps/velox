// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/velox-apps/velox.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "VeloxRuntimeWry", package: "velox"),
                .product(name: "VeloxRuntime", package: "velox")
            ]
        )
    ]
)
