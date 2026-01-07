# Creating Commands

Define type-safe communication between your Swift backend and JavaScript frontend.

## Overview

Commands are the primary way your frontend communicates with Swift. Velox offers three approaches, from simplest to most flexible:

1. **@VeloxCommand macro** — Minimal boilerplate (recommended)
2. **Command Registry DSL** — Type-safe with explicit control
3. **Manual handling** — Direct protocol handler routing

## The @VeloxCommand Macro

The `@VeloxCommand` macro generates all the boilerplate for you:

```swift
import VeloxMacros

enum Commands {
    @VeloxCommand
    static func greet(name: String) -> GreetResponse {
        GreetResponse(message: "Hello, \(name)!")
    }

    @VeloxCommand
    static func add(a: Int, b: Int) -> MathResponse {
        MathResponse(result: a + b)
    }
}
```

Register the generated commands:

```swift
let registry = commands {
    Commands.greetCommand      // Auto-generated
    Commands.addCommand        // Auto-generated
}
```

### Custom Command Names

By default, the command name matches the function name. Override it with a parameter:

```swift
@VeloxCommand("get_user_info")
static func getUserInfo(userId: String) -> UserInfo {
    // Command is invoked as "get_user_info"
}
```

### Accessing Context

Add a `CommandContext` parameter to access state, webview handles, and more:

```swift
@VeloxCommand
static func increment(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.increment())
}
```

### Error Handling

Mark functions as `throws` to return errors:

```swift
@VeloxCommand
static func divide(a: Double, b: Double) throws -> MathResponse {
    guard b != 0 else {
        throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: a / b)
}
```

## Command Registry DSL

For more explicit control, use the command registry directly:

```swift
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
}
```

### Argument Types

Define arguments as `Codable` structs:

```swift
struct GreetArgs: Codable, Sendable {
    let name: String
}

struct PersonArgs: Codable, Sendable {
    let name: String
    let age: Int
    let email: String?  // Optional fields are supported
}
```

### Response Types

Responses must also be `Codable`:

```swift
struct GreetResponse: Codable, Sendable {
    let message: String
}

struct UserResponse: Codable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
}
```

### Commands Without Arguments

Use `NoArgs` or omit the args parameter:

```swift
command("ping", returning: PingResponse.self) { _ in
    PingResponse(pong: true, timestamp: Date())
}
```

### Accessing State

Use the context to retrieve managed state:

```swift
command("get_count", returning: Int.self) { context in
    let state: CounterState = context.requireState()
    return state.count
}
```

## Manual Handling

For simple cases or migration, handle IPC requests directly:

```swift
let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    let command = URL(string: request.url)?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    switch command {
    case "greet":
        let args = try? JSONDecoder().decode(GreetArgs.self, from: request.body)
        let name = args?.name ?? "World"
        let response = ["result": "Hello, \(name)!"]
        let data = try! JSONEncoder().encode(response)
        return .init(status: 200, headers: ["Content-Type": "application/json"], body: data)

    default:
        return .init(status: 404, headers: [:], body: Data("Not found".utf8))
    }
}
```

> Note: Manual handling bypasses type safety. Prefer the macro or DSL for new code.

## Binary Responses

Return binary data (images, files) using `binaryCommand`:

```swift
binaryCommand("get_image", mimeType: "image/png") { context in
    let imageData = generatePNGImage()
    return imageData
}
```

In JavaScript:

```javascript
const response = await fetch('ipc://localhost/get_image');
const blob = await response.blob();
const url = URL.createObjectURL(blob);
document.getElementById('image').src = url;
```

## Calling Commands from JavaScript

Use the injected `window.Velox.invoke()` helper:

```javascript
// Simple call
const greeting = await window.Velox.invoke('greet', { name: 'World' });

// With error handling
try {
    const result = await window.Velox.invoke('divide', { a: 10, b: 0 });
} catch (error) {
    console.error('Command failed:', error.message);
}
```

### Alternative: Direct Fetch

You can also use `fetch` directly:

```javascript
const response = await fetch('ipc://localhost/greet', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: 'World' })
});
const data = await response.json();
console.log(data.result);
```

## Comparison

| Approach | Type Safety | Boilerplate | Best For |
|----------|-------------|-------------|----------|
| @VeloxCommand | Full | Minimal | New projects |
| Command DSL | Full | Moderate | Explicit control |
| Manual | None | High | Simple cases, migration |

## See Also

- <doc:DeferredResponses>
- <doc:ManagingState>
- ``CommandRegistry``
- ``CommandContext``
