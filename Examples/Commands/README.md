# Commands

**@VeloxCommand macro for cleanest command definitions**

This example demonstrates the recommended approach for defining IPC commands in Velox using the `@VeloxCommand` macro, similar to Tauri's `#[tauri::command]` attribute.

## Approach

The `@VeloxCommand` macro automatically generates the boilerplate needed to register commands with the command registry. Simply annotate your functions and the macro handles:

- Argument struct generation from function parameters
- JSON decoding/encoding
- Command registration property generation
- Error handling for throwing functions

## Usage

```swift
import VeloxMacros

enum Commands {
  @VeloxCommand
  static func greet(name: String) -> GreetResponse {
    GreetResponse(message: "Hello, \(name)!")
  }

  @VeloxCommand
  static func divide(numerator: Double, denominator: Double) throws -> MathResponse {
    guard denominator != 0 else {
      throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: numerator / denominator)
  }

  // Access state via CommandContext parameter
  @VeloxCommand
  static func increment(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.increment())
  }

  // Custom command name
  @VeloxCommand("get_counter")
  static func getCounter(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.counter)
  }
}

// Register macro-generated commands
let registry = commands {
  Commands.greetCommand
  Commands.divideCommand
  Commands.incrementCommand
  Commands.getCounterCommand
}
```

## Asset Approach

**Bundled assets** - HTML, CSS, and JavaScript are in the `assets/` directory and loaded at runtime via `AssetBundle`.

## Comparison

| Example | Approach | Boilerplate | Type Safety |
|---------|----------|-------------|-------------|
| **Commands** | `@VeloxCommand` macro | Minimal | Full |
| CommandsManual | Manual switch routing | High | Manual |
| CommandsManualRegistry | Command DSL | Medium | Full |

## Running

```bash
swift run Commands
```
