import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Counter Response

struct CounterResponse: Codable, Sendable {
    let value: Int
}

// MARK: - Counter Commands

let counterCommands = commands {
    command("counter:get", returning: CounterResponse.self) { ctx in
        let state: CounterState = ctx.requireState()
        return CounterResponse(value: state.value)
    }

    command("counter:increment", returning: CounterResponse.self) { ctx in
        let state: CounterState = ctx.requireState()
        return CounterResponse(value: state.increment())
    }

    command("counter:decrement", returning: CounterResponse.self) { ctx in
        let state: CounterState = ctx.requireState()
        return CounterResponse(value: state.decrement())
    }

    command("counter:reset", returning: CounterResponse.self) { ctx in
        let state: CounterState = ctx.requireState()
        return CounterResponse(value: state.reset())
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
            .manage(CounterState())          // Register counter state
            .registerCommands(counterCommands)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
