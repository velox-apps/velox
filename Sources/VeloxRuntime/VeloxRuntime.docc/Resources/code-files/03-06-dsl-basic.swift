import Foundation
import VeloxRuntime

// MARK: - The commands DSL

/// Build a command registry using the DSL
let registry = commands {
    // Simple command with no arguments
    command("ping", returning: String.self) { _ in
        "pong"
    }

    // Command with typed arguments and response
    command("greet", args: GreetArgs.self, returning: GreetResponse.self) { args, _ in
        GreetResponse(message: "Hello, \(args.name)!")
    }

    // Command that accesses state via context
    command("get_count", returning: Int.self) { ctx in
        let state: AppState = ctx.requireState()
        return state.count
    }

    // Async command
    command("fetch_data", args: FetchArgs.self, returning: DataResponse.self) { args, ctx in
        let data = try await fetchFromNetwork(url: args.url)
        return DataResponse(data: data, fetchedAt: Date())
    }

    // Command that can throw errors
    command("risky_operation", returning: String.self) { _ in
        guard someCondition else {
            throw CommandError(code: "Failed", message: "Operation failed")
        }
        return "Success"
    }
}
