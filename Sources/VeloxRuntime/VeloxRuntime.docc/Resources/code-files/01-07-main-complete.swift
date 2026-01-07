import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// Define command arguments
struct GreetArgs: Codable, Sendable {
    let name: String
}

let html = """
<!DOCTYPE html>
<html>
<head>
    <title>My Velox App</title>
    <style>
        body {
            font-family: system-ui;
            max-width: 400px;
            margin: 50px auto;
            text-align: center;
        }
        input, button {
            padding: 10px;
            font-size: 16px;
            margin: 5px;
        }
        #result {
            margin-top: 20px;
            padding: 15px;
            background: #f0f0f0;
            border-radius: 8px;
        }
    </style>
</head>
<body>
    <h1>Hello Velox!</h1>
    <input id="name" placeholder="Enter your name">
    <button onclick="greet()">Greet</button>
    <div id="result"></div>

    <script>
        async function greet() {
            const name = document.getElementById('name').value || 'World';
            const message = await window.Velox.invoke('greet', { name });
            document.getElementById('result').textContent = message;
        }
    </script>
</body>
</html>
"""

// Register commands
let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
        "Hello, \(args.name)! Welcome to Velox!"
    }
}

func main() {
    guard Thread.isMainThread else {
        fatalError("Must run on main thread")
    }

    let projectDir = URL(fileURLWithPath: #file).deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            .registerAppProtocol { _ in html }
            .registerCommands(registry)
        try app.run()
    } catch {
        fatalError("Failed to start: \(error)")
    }
}

main()
