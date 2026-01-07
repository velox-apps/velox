# Managing State

Share data safely across commands with Velox's state management system.

## Overview

Commands in Velox are stateless functions. To share data between command invocations—like a counter, user session, or cached data—use ``StateContainer``.

## Basic State Management

### Define State

Create a thread-safe class for your application state:

```swift
final class AppState: @unchecked Sendable {
    private let lock = NSLock()
    private var _counter: Int = 0

    var counter: Int {
        lock.lock()
        defer { lock.unlock() }
        return _counter
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _counter += 1
        return _counter
    }
}
```

### Register State

Add state to your app builder:

```swift
let app = try VeloxAppBuilder(directory: projectDir)
    .manage(AppState())
    .registerCommands(registry)
```

### Access in Commands

Use `context.requireState()` to retrieve state:

```swift
@VeloxCommand
static func increment(context: CommandContext) -> Int {
    let state: AppState = context.requireState()
    return state.increment()
}

@VeloxCommand
static func getCount(context: CommandContext) -> Int {
    let state: AppState = context.requireState()
    return state.counter
}
```

With the command DSL:

```swift
command("increment", returning: Int.self) { context in
    let state: AppState = context.requireState()
    return state.increment()
}
```

## Multiple State Types

You can manage multiple independent state objects:

```swift
final class UserState: @unchecked Sendable {
    private let lock = NSLock()
    var currentUser: User?
}

final class CacheState: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func set(_ key: String, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = data
    }
}

let app = try VeloxAppBuilder(directory: projectDir)
    .manage(UserState())
    .manage(CacheState())
```

Access each by type:

```swift
@VeloxCommand
static func getCurrentUser(context: CommandContext) -> User? {
    let state: UserState = context.requireState()
    return state.currentUser
}

@VeloxCommand
static func getCached(key: String, context: CommandContext) -> Data? {
    let state: CacheState = context.requireState()
    return state.get(key)
}
```

## Thread Safety

State must be thread-safe because commands can be invoked concurrently. Use one of these patterns:

### NSLock

```swift
final class SafeState: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func update(_ newValue: Int) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}
```

### DispatchQueue

```swift
final class QueueState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.app.state")
    private var _items: [String] = []

    var items: [String] {
        queue.sync { _items }
    }

    func add(_ item: String) {
        queue.sync { _items.append(item) }
    }
}
```

### Actor (Swift 5.5+)

```swift
actor ActorState {
    private var _counter: Int = 0

    var counter: Int { _counter }

    func increment() -> Int {
        _counter += 1
        return _counter
    }
}
```

> Note: When using actors, commands need to be async-aware.

## State in Plugins

Plugins can manage their own isolated state:

```swift
struct AnalyticsPlugin: VeloxPlugin {
    let identifier = "com.example.analytics"
    let name = "Analytics"

    final class AnalyticsState: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [AnalyticsEvent] = []

        func track(_ event: AnalyticsEvent) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }
    }

    func initialize(context: PluginSetupContext) throws {
        context.manage(AnalyticsState())

        context.commands {
            command("track", args: TrackArgs.self, returning: EmptyResponse.self) { args, ctx in
                let state: AnalyticsState = ctx.requireState()
                state.track(AnalyticsEvent(name: args.name, properties: args.properties))
                return EmptyResponse()
            }
        }
    }
}
```

## Best Practices

### Keep State Focused

Create separate state classes for different concerns:

```swift
// Good: Focused state classes
final class AuthState { ... }
final class CartState { ... }
final class PreferencesState { ... }

// Avoid: One giant state class
final class AppState {
    var user: User?
    var cart: [Item]
    var preferences: Preferences
    var cache: [String: Data]
    // ... dozens more properties
}
```

### Avoid Storing UI State

Keep UI state in your frontend. Backend state should be for:
- User sessions and authentication
- Cached data and API responses
- Application configuration
- Counters and metrics

### Handle Missing State

`requireState()` crashes if state isn't registered. For optional state access:

```swift
if let state: OptionalFeatureState = context.state() {
    // State exists
} else {
    // State not registered
}
```

## Example: Shopping Cart

```swift
final class CartState: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CartItem] = []

    func add(_ item: CartItem) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    func remove(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
            return true
        }
        return false
    }

    func getAll() -> [CartItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    var total: Decimal {
        lock.lock()
        defer { lock.unlock() }
        return items.reduce(0) { $0 + $1.price * Decimal($1.quantity) }
    }
}

struct CartItem: Codable, Sendable {
    let id: String
    let name: String
    let price: Decimal
    var quantity: Int
}

// Commands
let registry = commands {
    command("cart_add", args: CartItem.self, returning: EmptyResponse.self) { item, ctx in
        let cart: CartState = ctx.requireState()
        cart.add(item)
        return EmptyResponse()
    }

    command("cart_remove", args: StringArg.self, returning: Bool.self) { args, ctx in
        let cart: CartState = ctx.requireState()
        return cart.remove(id: args.value)
    }

    command("cart_list", returning: [CartItem].self) { ctx in
        let cart: CartState = ctx.requireState()
        return cart.getAll()
    }

    command("cart_total", returning: Decimal.self) { ctx in
        let cart: CartState = ctx.requireState()
        return cart.total
    }
}
```

## See Also

- <doc:CreatingCommands>
- <doc:BuildingPlugins>
- ``StateContainer``
- ``CommandContext``
