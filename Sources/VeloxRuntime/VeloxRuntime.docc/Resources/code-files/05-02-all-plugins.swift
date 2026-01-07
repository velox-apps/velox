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
            // Register all built-in plugins at once
            .plugins {
                DialogPlugin()        // File dialogs, message boxes
                ClipboardPlugin()     // System clipboard
                NotificationPlugin()  // Native notifications
                ShellPlugin()         // Execute system commands
                OSInfoPlugin()        // OS information
                ProcessPlugin()       // Process management
                OpenerPlugin()        // Open files/URLs
            }
            .registerCommands(appCommands)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
