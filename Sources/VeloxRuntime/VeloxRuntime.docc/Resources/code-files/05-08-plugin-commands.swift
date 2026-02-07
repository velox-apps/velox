import Foundation
import VeloxRuntime

// MARK: - Plugin State

final class LogState: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let maxEntries: Int

    init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    func add(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }

    func getAll() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: String
    let message: String
}

// MARK: - Command Arguments

struct LogArgs: Codable, Sendable {
    let level: String
    let message: String
}

// MARK: - Plugin with Commands

struct LoggingPlugin: VeloxPlugin {
    let identifier = "com.myapp.logging"
    let name = "Logging Plugin"

    func initialize(context: PluginSetupContext) throws {
        // Register plugin state
        context.manage(LogState(maxEntries: 1000))

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

            command("clear_logs", returning: EmptyResponse.self) { ctx in
                let state: LogState = ctx.requireState()
                state.clear()
                return EmptyResponse()
            }
        }
    }

    func onWebviewCreated(context: WebviewReadyContext) {
        // Inject a Logger helper into JavaScript
        context.webview.evaluate(script: """
            window.Logger = {
                log: (level, message) => Velox.invoke('plugin:com.myapp.logging|log', { level, message }),
                info: (message) => Velox.invoke('plugin:com.myapp.logging|log', { level: 'info', message }),
                warn: (message) => Velox.invoke('plugin:com.myapp.logging|log', { level: 'warn', message }),
                error: (message) => Velox.invoke('plugin:com.myapp.logging|log', { level: 'error', message }),
                getLogs: () => Velox.invoke('plugin:com.myapp.logging|get_logs', {}),
                clear: () => Velox.invoke('plugin:com.myapp.logging|clear_logs', {})
            };
            """)
    }

    func onNavigation(request: NavigationRequest) -> NavigationDecision {
        return .allow
    }
}
