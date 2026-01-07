import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Command Arguments

struct GreetArgs: Codable, Sendable {
    let name: String
}

struct MathArgs: Codable, Sendable {
    let a: Double
    let b: Double
}

// MARK: - Response Types

struct MathResponse: Codable, Sendable {
    let result: Double
    let operation: String
}

// MARK: - Commands

let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
        "Hello, \(args.name)!"
    }

    command("add", args: MathArgs.self, returning: MathResponse.self) { args, _ in
        MathResponse(result: args.a + args.b, operation: "addition")
    }

    command("multiply", args: MathArgs.self, returning: MathResponse.self) { args, _ in
        MathResponse(result: args.a * args.b, operation: "multiplication")
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
