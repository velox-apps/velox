import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Command Arguments

struct GreetArgs: Codable, Sendable {
    let name: String
}

// MARK: - Commands

let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
        "Hello, \(args.name)!"
    }
}

// MARK: - Main

func main() {
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            .registerCommands(registry)
        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
