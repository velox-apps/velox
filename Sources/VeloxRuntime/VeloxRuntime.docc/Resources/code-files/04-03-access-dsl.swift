import Foundation
import VeloxRuntime

// MARK: - Accessing State with the Command DSL

let registry = commands {
    // Access state through the context parameter
    command("get_counter", returning: Int.self) { ctx in
        // requireState() retrieves state by type
        let state: AppState = ctx.requireState()
        return state.counter
    }

    // Modify state and return new value
    command("increment", returning: Int.self) { ctx in
        let state: AppState = ctx.requireState()
        return state.incrementCounter()
    }

    // Access multiple state types
    command("get_user_info", returning: UserInfo.self) { ctx in
        let appState: AppState = ctx.requireState()
        let settings: UserSettings = ctx.requireState()

        return UserInfo(
            username: appState.username,
            theme: settings.theme,
            counter: appState.counter
        )
    }

    // Optional state access - returns nil if not registered
    command("get_cache_stats", returning: CacheStats?.self) { ctx in
        // state() returns optional, requireState() throws if missing
        guard let cache: CacheManager = ctx.state() else {
            return nil
        }
        return cache.stats
    }
}
