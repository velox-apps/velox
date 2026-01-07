import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// Create your state instance
let appState = AppState()

// Register state with the app builder using manage()
func main() {
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            .manage(appState)              // Register AppState
            .manage(UserSettings())        // Can register multiple states
            .manage(CacheManager())        // Each type can be registered once
            .registerCommands(registry)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}
