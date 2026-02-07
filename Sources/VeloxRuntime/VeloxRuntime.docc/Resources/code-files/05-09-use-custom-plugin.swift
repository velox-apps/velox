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
            // Register built-in plugins
            .plugin(DialogPlugin())
            .plugin(ClipboardPlugin())
            // Register your custom plugin
            .plugin(LoggingPlugin())
            .registerCommands(appCommands)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()

// In JavaScript, use the injected Logger helper:
//
// Logger.info('User logged in');
// Logger.warn('Session expiring soon');
// Logger.error('Failed to save document');
//
// const logs = await Logger.getLogs();
// console.log('Recent logs:', logs);
//
// Or use the full command name:
// await Velox.invoke('plugin:com.myapp.logging|log', {
//     level: 'info',
//     message: 'Hello from frontend!'
// });
