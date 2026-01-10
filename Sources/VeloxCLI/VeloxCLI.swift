import ArgumentParser

/// The Velox command-line interface for development and building desktop apps.
///
/// Velox CLI provides tools for:
/// - **Development**: `velox dev` - Run with hot reloading and file watching
/// - **Building**: `velox build` - Build for production, create app bundles
/// - **Bundling**: `velox bundle` - Create app bundles for distribution
/// - **Setup**: `velox init` - Initialize a new Velox project
///
/// Usage:
/// ```bash
/// # Start development server with hot reload
/// velox dev
///
/// # Build release and create .app bundle (macOS)
/// velox build --release --bundle
///
/// # Create a bundle (macOS)
/// velox bundle
///
/// # Initialize a new project
/// velox init --name MyApp
/// ```
@main
struct VeloxCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "velox",
    abstract: "Velox development tools",
    version: "0.1.0",
    subcommands: [DevCommand.self, BuildCommand.self, BundleCommand.self, InitCommand.self],
    defaultSubcommand: DevCommand.self
  )
}
