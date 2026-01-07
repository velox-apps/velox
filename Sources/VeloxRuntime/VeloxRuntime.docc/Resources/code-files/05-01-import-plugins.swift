import Foundation
import VeloxRuntime
import VeloxRuntimeWry
import VeloxPlugins

func main() {
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            // Register individual plugins as needed
            .plugin(DialogPlugin())        // File dialogs, message boxes
            .plugin(ClipboardPlugin())     // System clipboard
            .plugin(NotificationPlugin())  // Native notifications
            .registerCommands(appCommands)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
