import Foundation
import VeloxMacros
import VeloxRuntime

// MARK: - Accessing State with @VeloxCommand Macro

enum Commands {
    /// Get the current counter value
    /// Add CommandContext parameter to access state
    @VeloxCommand
    static func getCounter(context: CommandContext) -> Int {
        let state: AppState = context.requireState()
        return state.counter
    }

    /// Increment the counter
    @VeloxCommand
    static func increment(context: CommandContext) -> Int {
        let state: AppState = context.requireState()
        return state.incrementCounter()
    }

    /// Update username - combines args with state access
    @VeloxCommand
    static func setUsername(name: String, context: CommandContext) -> String {
        let state: AppState = context.requireState()
        state.setUsername(name)
        return "Username updated to: \(name)"
    }

    /// Get combined info from multiple states
    @VeloxCommand
    static func getUserInfo(context: CommandContext) -> UserInfo {
        let appState: AppState = context.requireState()
        let settings: UserSettings = context.requireState()

        return UserInfo(
            username: appState.username,
            theme: settings.theme,
            counter: appState.counter
        )
    }
}
