# CommandsManual

**Manual IPC routing with switch statement**

This example demonstrates the most basic approach for handling IPC commands in Velox using a manual switch statement. This mirrors how you might handle routing in a simple server.

## Approach

Commands are routed manually using a switch statement on the command name. Arguments are extracted from `[String: Any]` dictionaries without type safety.

## Usage

```swift
func handleInvoke(request: Request, state: AppState) -> Response? {
  let command = extractCommand(from: request.url)
  var args: [String: Any] = parseJSON(request.body)

  switch command {
  case "greet":
    let name = args["name"] as? String ?? "World"
    return jsonResponse(["result": "Hello, \(name)!"])

  case "add":
    let a = args["a"] as? Int ?? 0
    let b = args["b"] as? Int ?? 0
    return jsonResponse(["result": a + b])

  case "divide":
    let num = args["numerator"] as? Double ?? 0
    let den = args["denominator"] as? Double ?? 0
    if den == 0 {
      return errorResponse("DivisionByZero", "Cannot divide by zero")
    }
    return jsonResponse(["result": num / den])

  default:
    return errorResponse("UnknownCommand", "Unknown command: \(command)")
  }
}
```

## Asset Approach

**Bundled assets** - HTML, CSS, and JavaScript are in the `assets/` directory and loaded at runtime via `AssetBundle`.

## Pros and Cons

**Pros:**
- Simple and explicit
- No dependencies on macros or DSL
- Easy to understand for newcomers

**Cons:**
- No type safety for arguments
- Manual JSON parsing with `as?` casts
- Verbose error handling
- Easy to make typos in argument names

## Comparison

| Example | Approach | Boilerplate | Type Safety |
|---------|----------|-------------|-------------|
| Commands | `@VeloxCommand` macro | Minimal | Full |
| **CommandsManual** | Manual switch routing | High | Manual |
| CommandsManualRegistry | Command DSL | Medium | Full |

## Running

```bash
swift run CommandsManual
```
