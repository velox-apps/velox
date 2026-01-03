# CommandsManualRegistry

**Type-safe command DSL with automatic JSON decoding**

This example demonstrates the command registry DSL approach for defining IPC commands in Velox. It provides full type safety with explicit argument and response type declarations.

## Approach

Commands are registered using a result builder DSL. You define `Codable` structs for arguments and responses, and the registry handles JSON encoding/decoding automatically.

## Usage

```swift
import VeloxRuntime

// Define typed arguments
struct GreetArgs: Codable, Sendable {
  let name: String
}

struct DivideArgs: Codable, Sendable {
  let numerator: Double
  let denominator: Double
}

// Define typed responses
struct GreetResponse: Codable, Sendable {
  let message: String
}

struct MathResponse: Codable, Sendable {
  let result: Double
}

// Register commands using the DSL
let registry = commands {
  command("greet", args: GreetArgs.self, returning: GreetResponse.self) { args, _ in
    GreetResponse(message: "Hello, \(args.name)!")
  }

  command("divide", args: DivideArgs.self, returning: MathResponse.self) { args, _ in
    guard args.denominator != 0 else {
      throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: args.numerator / args.denominator)
  }

  // Commands without arguments
  command("ping", returning: PingResponse.self) { _ in
    PingResponse(pong: true, timestamp: Date().timeIntervalSince1970)
  }

  // Commands with state access
  command("increment", returning: CounterResponse.self) { context in
    let state: AppState = context.requireState()
    return CounterResponse(value: state.increment())
  }
}

// Create IPC handler from registry
let stateContainer = StateContainer().manage(AppState())
let ipcHandler = createCommandHandler(registry: registry, stateContainer: stateContainer)
```

## Asset Approach

**Bundled assets** - HTML, CSS, and JavaScript are in the `assets/` directory and loaded at runtime via `AssetBundle`.

## Pros and Cons

**Pros:**
- Full type safety for arguments and responses
- Automatic JSON encoding/decoding
- Compile-time verification of types
- Clean separation of argument/response definitions

**Cons:**
- More verbose than macro approach
- Requires explicit struct definitions for all arguments
- Command name specified as string (potential for typos)

## Comparison

| Example | Approach | Boilerplate | Type Safety |
|---------|----------|-------------|-------------|
| Commands | `@VeloxCommand` macro | Minimal | Full |
| CommandsManual | Manual switch routing | High | Manual |
| **CommandsManualRegistry** | Command DSL | Medium | Full |

## Running

```bash
swift run CommandsManualRegistry
```
