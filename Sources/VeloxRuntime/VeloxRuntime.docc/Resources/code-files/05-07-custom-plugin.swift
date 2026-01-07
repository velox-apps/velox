import Foundation
import VeloxRuntime

/// A custom logging plugin that tracks events in your app
struct LoggingPlugin: VeloxPlugin {
    /// Unique identifier for this plugin
    let identifier = "com.myapp.logging"

    /// Human-readable name
    let name = "Logging Plugin"

    /// Plugin configuration
    let logLevel: LogLevel
    let maxEntries: Int

    enum LogLevel: String {
        case debug, info, warn, error
    }

    init(level: LogLevel = .info, maxEntries: Int = 1000) {
        self.logLevel = level
        self.maxEntries = maxEntries
    }

    /// Called when the plugin is registered
    func initialize(context: PluginSetupContext) throws {
        print("[\(name)] Initializing with level: \(logLevel)")

        // Register plugin state
        context.manage(LogState(maxEntries: maxEntries))

        // Register commands - covered in the next step
    }

    /// Called when a webview is created
    func onWebviewCreated(context: WebviewReadyContext) {
        print("[\(name)] Webview created: \(context.label)")
    }

    /// Called before navigation occurs
    func onNavigation(request: NavigationRequest) -> NavigationDecision {
        print("[\(name)] Navigation to: \(request.url)")
        return .allow
    }
}
