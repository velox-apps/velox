# Building Plugins

Extend Velox with reusable, modular functionality.

## Overview

Plugins are self-contained modules that add capabilities to your Velox application. They can register commands, manage state, respond to lifecycle events, and control navigation.

Plugins can be:
- **Inline**: Defined directly in your app for app-specific functionality
- **Packaged**: Distributed as separate Swift packages for reuse across projects

## The VeloxPlugin Protocol

Every plugin implements ``VeloxPlugin``:

```swift
public protocol VeloxPlugin: Sendable {
    /// Unique identifier for this plugin
    var identifier: String { get }

    /// Human-readable name
    var name: String { get }

    /// Called when the plugin is registered
    func initialize(context: PluginSetupContext) throws

    /// Called when a webview is created
    func onWebviewCreated(context: WebviewReadyContext)

    /// Called before navigation occurs
    func onNavigation(request: NavigationRequest) -> NavigationDecision
}
```

## Creating an Inline Plugin

For app-specific functionality, define plugins directly in your project:

```swift
import VeloxRuntime

struct LoggingPlugin: VeloxPlugin {
    let identifier = "com.example.logging"
    let name = "Logging Plugin"

    // Plugin-specific state
    final class LogState: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [LogEntry] = []

        func add(_ entry: LogEntry) {
            lock.lock()
            defer { lock.unlock() }
            entries.append(entry)
        }

        func getAll() -> [LogEntry] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }

    struct LogEntry: Codable, Sendable {
        let timestamp: Date
        let level: String
        let message: String
    }

    func initialize(context: PluginSetupContext) throws {
        // Register plugin state
        context.manage(LogState())

        // Register commands (auto-prefixed with plugin identifier)
        context.commands {
            command("log", args: LogArgs.self, returning: EmptyResponse.self) { args, ctx in
                let state: LogState = ctx.requireState()
                state.add(LogEntry(
                    timestamp: Date(),
                    level: args.level,
                    message: args.message
                ))
                return EmptyResponse()
            }

            command("get_logs", returning: [LogEntry].self) { ctx in
                let state: LogState = ctx.requireState()
                return state.getAll()
            }
        }
    }

    func onWebviewCreated(context: WebviewReadyContext) {
        print("[\(name)] Webview created: \(context.label)")
    }

    func onNavigation(request: NavigationRequest) -> NavigationDecision {
        print("[\(name)] Navigation to: \(request.url)")
        return .allow
    }
}

struct LogArgs: Codable, Sendable {
    let level: String
    let message: String
}
```

## Creating a Plugin Package

For plugins you want to share across projects or distribute to others, create a separate Swift package.

### Package Structure

```
velox-plugin-analytics/
├── Package.swift
├── README.md
├── Sources/
│   └── VeloxPluginAnalytics/
│       ├── AnalyticsPlugin.swift
│       ├── AnalyticsState.swift
│       ├── Commands/
│       │   ├── TrackCommand.swift
│       │   └── IdentifyCommand.swift
│       └── Types/
│           ├── AnalyticsEvent.swift
│           └── UserProperties.swift
└── Tests/
    └── VeloxPluginAnalyticsTests/
        └── AnalyticsPluginTests.swift
```

### Package.swift

Configure your plugin package to depend on `VeloxRuntime`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeloxPluginAnalytics",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "VeloxPluginAnalytics",
            targets: ["VeloxPluginAnalytics"]
        )
    ],
    dependencies: [
        // Depend on VeloxRuntime for the plugin protocol
        .package(url: "https://github.com/velox-apps/velox.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "VeloxPluginAnalytics",
            dependencies: [
                .product(name: "VeloxRuntime", package: "velox")
            ]
        ),
        .testTarget(
            name: "VeloxPluginAnalyticsTests",
            dependencies: ["VeloxPluginAnalytics"]
        )
    ]
)
```

### Plugin Implementation

**Sources/VeloxPluginAnalytics/AnalyticsPlugin.swift:**

```swift
import Foundation
import VeloxRuntime

/// Analytics plugin for tracking user events and identifying users.
public struct AnalyticsPlugin: VeloxPlugin {
    public let identifier = "com.example.analytics"
    public let name = "Analytics Plugin"

    private let apiKey: String
    private let endpoint: URL

    /// Create an analytics plugin with your API credentials.
    /// - Parameters:
    ///   - apiKey: Your analytics service API key
    ///   - endpoint: The analytics API endpoint URL
    public init(apiKey: String, endpoint: URL) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    public func initialize(context: PluginSetupContext) throws {
        // Initialize state with configuration
        let state = AnalyticsState(apiKey: apiKey, endpoint: endpoint)
        context.manage(state)

        // Register commands
        context.commands {
            command("track", args: TrackArgs.self, returning: EmptyResponse.self) { args, ctx in
                let state: AnalyticsState = ctx.requireState()
                try await state.track(event: args.event, properties: args.properties)
                return EmptyResponse()
            }

            command("identify", args: IdentifyArgs.self, returning: EmptyResponse.self) { args, ctx in
                let state: AnalyticsState = ctx.requireState()
                state.identify(userId: args.userId, traits: args.traits)
                return EmptyResponse()
            }

            command("flush", returning: FlushResponse.self) { ctx in
                let state: AnalyticsState = ctx.requireState()
                let count = try await state.flush()
                return FlushResponse(eventsFlushed: count)
            }
        }
    }

    public func onWebviewCreated(context: WebviewReadyContext) {
        // Inject analytics helper into the page
        context.webview.evaluate(script: """
            window.Analytics = {
                track: (event, props) => window.Velox.invoke('plugin:com.example.analytics|track', { event, properties: props }),
                identify: (userId, traits) => window.Velox.invoke('plugin:com.example.analytics|identify', { userId, traits })
            };
        """)
    }

    public func onNavigation(request: NavigationRequest) -> NavigationDecision {
        // Auto-track page views
        Task {
            // Track navigation as page view
        }
        return .allow
    }
}

// MARK: - Command Arguments

struct TrackArgs: Codable, Sendable {
    let event: String
    let properties: [String: String]?
}

struct IdentifyArgs: Codable, Sendable {
    let userId: String
    let traits: [String: String]?
}

struct FlushResponse: Codable, Sendable {
    let eventsFlushed: Int
}
```

**Sources/VeloxPluginAnalytics/AnalyticsState.swift:**

```swift
import Foundation

final class AnalyticsState: @unchecked Sendable {
    private let lock = NSLock()
    private let apiKey: String
    private let endpoint: URL
    private var userId: String?
    private var eventQueue: [AnalyticsEvent] = []

    init(apiKey: String, endpoint: URL) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    func identify(userId: String, traits: [String: String]?) {
        lock.lock()
        defer { lock.unlock() }
        self.userId = userId
    }

    func track(event: String, properties: [String: String]?) async throws {
        lock.lock()
        eventQueue.append(AnalyticsEvent(
            name: event,
            properties: properties ?? [:],
            userId: userId,
            timestamp: Date()
        ))
        lock.unlock()
    }

    func flush() async throws -> Int {
        lock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        lock.unlock()

        // Send events to analytics endpoint
        // ... HTTP request implementation ...

        return events.count
    }
}

struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let properties: [String: String]
    let userId: String?
    let timestamp: Date
}
```

### Publishing Your Plugin

**1. Push to GitHub:**

```bash
git init
git add .
git commit -m "Initial release of VeloxPluginAnalytics"
git remote add origin https://github.com/yourusername/velox-plugin-analytics.git
git push -u origin main
```

**2. Tag a release:**

```bash
git tag 1.0.0
git push origin 1.0.0
```

**3. Add a README with usage instructions:**

```markdown
# VeloxPluginAnalytics

Analytics plugin for Velox apps.

## Installation

Add to your `Package.swift`:

\```swift
dependencies: [
    .package(url: "https://github.com/yourusername/velox-plugin-analytics.git", from: "1.0.0")
]
\```

## Usage

\```swift
import VeloxPluginAnalytics

let app = try VeloxAppBuilder(directory: projectDir)
    .plugin(AnalyticsPlugin(
        apiKey: "your-api-key",
        endpoint: URL(string: "https://api.analytics.com/v1")!
    ))
\```
```

## Consuming Plugin Packages

To use a plugin from an external package in your Velox app:

### 1. Add the Dependency

Update your app's `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/velox-apps/velox.git", from: "1.0.0"),
        // Add plugin packages
        .package(url: "https://github.com/example/velox-plugin-analytics.git", from: "1.0.0"),
        .package(url: "https://github.com/example/velox-plugin-auth.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "VeloxRuntimeWry", package: "velox"),
                .product(name: "VeloxRuntime", package: "velox"),
                // Import plugin products
                .product(name: "VeloxPluginAnalytics", package: "velox-plugin-analytics"),
                .product(name: "VeloxPluginAuth", package: "velox-plugin-auth")
            ]
        )
    ]
)
```

### 2. Import and Register

In your `main.swift`:

```swift
import VeloxRuntime
import VeloxRuntimeWry
import VeloxPluginAnalytics
import VeloxPluginAuth

let app = try VeloxAppBuilder(directory: projectDir)
    // Register external plugins
    .plugin(AnalyticsPlugin(
        apiKey: ProcessInfo.processInfo.environment["ANALYTICS_KEY"] ?? "",
        endpoint: URL(string: "https://api.analytics.com/v1")!
    ))
    .plugin(AuthPlugin(
        clientId: "your-client-id",
        redirectUri: "myapp://auth/callback"
    ))
    // Register your commands
    .registerCommands(appCommands)

try app.run()
```

### 3. Use in JavaScript

```javascript
// Use the analytics plugin's injected helper
Analytics.track('button_clicked', { buttonId: 'submit' });
Analytics.identify('user-123', { plan: 'premium' });

// Or use the standard invoke pattern
await window.Velox.invoke('plugin:com.example.analytics|track', {
    event: 'purchase',
    properties: { amount: 99.99 }
});
```

## Registering Plugins

Add plugins when building your app:

```swift
let app = try VeloxAppBuilder(directory: projectDir)
    .plugin(LoggingPlugin())
    .plugin(AnalyticsPlugin())
    .registerCommands(appCommands)

try app.run()
```

## Plugin Commands

Commands registered by plugins are automatically prefixed with the plugin identifier:

```javascript
// Plugin identifier: "com.example.logging"
// Command registered as: "log"
// Full command name: "plugin:com.example.logging|log"

await window.Velox.invoke('plugin:com.example.logging|log', {
    level: 'info',
    message: 'User clicked button'
});
```

## Lifecycle Hooks

### initialize

Called once when the plugin is registered. Use this to:
- Register commands
- Set up plugin state
- Configure resources

```swift
func initialize(context: PluginSetupContext) throws {
    context.manage(MyPluginState())
    context.commands {
        // Register plugin commands
    }
}
```

### onWebviewCreated

Called each time a webview is created. Use this for:
- Injecting JavaScript helpers
- Setting up webview-specific state

```swift
func onWebviewCreated(context: WebviewReadyContext) {
    context.webview.evaluate(script: """
        window.MyPlugin = {
            version: '1.0.0',
            isReady: true
        };
    """)
}
```

### onNavigation

Called before each navigation. Control whether to allow it:

```swift
func onNavigation(request: NavigationRequest) -> NavigationDecision {
    // Block external URLs
    if !request.url.hasPrefix("app://") && !request.url.hasPrefix("https://trusted.com") {
        return .deny
    }
    return .allow
}
```

## Plugin State

Plugins can manage their own state, isolated from the main app:

```swift
final class PluginState: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Any] = [:]

    func set(_ key: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }
        data[key] = value
    }

    func get(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return data[key]
    }
}

func initialize(context: PluginSetupContext) throws {
    context.manage(PluginState())
}
```

Access state in commands:

```swift
command("get_value", args: KeyArgs.self, returning: String?.self) { args, ctx in
    let state: PluginState = ctx.requireState()
    return state.get(args.key) as? String
}
```

## Plugin Best Practices

### Naming Conventions

- **Package name**: `VeloxPlugin{Name}` (e.g., `VeloxPluginAnalytics`)
- **Plugin identifier**: Reverse domain notation (e.g., `com.example.analytics`)
- **Module name**: Match the package name

### Configuration

Accept configuration through the initializer:

```swift
public struct MyPlugin: VeloxPlugin {
    private let config: Config

    public struct Config {
        public let apiKey: String
        public let debug: Bool

        public init(apiKey: String, debug: Bool = false) {
            self.apiKey = apiKey
            self.debug = debug
        }
    }

    public init(config: Config) {
        self.config = config
    }

    // Or provide a convenience initializer
    public init(apiKey: String, debug: Bool = false) {
        self.config = Config(apiKey: apiKey, debug: debug)
    }
}
```

### Error Handling

Throw descriptive errors from `initialize`:

```swift
func initialize(context: PluginSetupContext) throws {
    guard !apiKey.isEmpty else {
        throw PluginError.missingConfiguration("API key is required")
    }

    guard endpoint.scheme == "https" else {
        throw PluginError.invalidConfiguration("Endpoint must use HTTPS")
    }
}
```

### Documentation

Add DocC comments to your public API:

```swift
/// Analytics plugin for tracking user events.
///
/// Use this plugin to track user behavior and identify users
/// in your analytics platform.
///
/// ## Usage
///
/// ```swift
/// let plugin = AnalyticsPlugin(apiKey: "your-key")
/// ```
public struct AnalyticsPlugin: VeloxPlugin {
    // ...
}
```

## Built-in Plugins

Velox includes several ready-to-use plugins:

| Plugin | Module | Commands |
|--------|--------|----------|
| Dialog | `VeloxPluginDialog` | `open`, `save`, `message`, `ask`, `confirm` |
| Clipboard | `VeloxPluginClipboard` | `read`, `write` |
| Notification | `VeloxPluginNotification` | `send`, `requestPermission` |
| Shell | `VeloxPluginShell` | `execute`, `spawn`, `kill` |
| OS | `VeloxPluginOS` | `version`, `arch`, `hostname`, `locale` |
| Process | `VeloxPluginProcess` | `exit`, `relaunch`, `environment` |
| Opener | `VeloxPluginOpener` | `open` |

Use them via `VeloxPlugins`:

```swift
import VeloxPlugins

let app = try VeloxAppBuilder(directory: projectDir)
    .plugin(DialogPlugin())
    .plugin(ClipboardPlugin())
    .plugin(NotificationPlugin())
```

Or import all at once:

```swift
import VeloxPlugins

let app = try VeloxAppBuilder(directory: projectDir)
    .plugins(VeloxPlugins.all)
```

## See Also

- <doc:BuiltinPlugins>
- <doc:ManagingState>
- ``VeloxPlugin``
- ``PluginSetupContext``
