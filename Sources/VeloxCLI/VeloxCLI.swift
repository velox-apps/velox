import ArgumentParser

@main
struct VeloxCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "velox",
    abstract: "Velox development tools",
    version: "0.1.0",
    subcommands: [DevCommand.self],
    defaultSubcommand: DevCommand.self
  )
}
