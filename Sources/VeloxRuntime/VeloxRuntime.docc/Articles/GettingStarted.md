# Getting Started with Velox

Create your first Velox application in minutes.

## Overview

This guide walks you through creating a simple Velox application—a greeting app that demonstrates the core concepts of Swift-to-JavaScript communication using a proper project structure with separate frontend files.

## Prerequisites

Before you begin, ensure you have:

- **macOS 13** (Ventura) or later
- **Xcode 15** or later
- **Swift 5.9+** toolchain
- **Rust** toolchain (for building the FFI layer) — install via [rustup](https://rustup.rs)

## Create a New Project

### Option 1: Using create-velox-app (Recommended)

The quickest way to start is with the project generator:

```bash
npx create-velox-app my-velox-app
cd my-velox-app
swift build
swift run MyVeloxApp
```

`create-velox-app` includes many frontend templates to match your preferred stack:

| Template | Description |
|----------|-------------|
| `vanilla` | Plain HTML, CSS, and JavaScript |
| `vanilla-ts` | TypeScript with no framework |
| `react` | React with Vite |
| `react-ts` | React + TypeScript with Vite |
| `vue` | Vue 3 with Vite |
| `vue-ts` | Vue 3 + TypeScript with Vite |
| `svelte` | Svelte with Vite |
| `svelte-ts` | Svelte + TypeScript with Vite |
| `solid` | SolidJS with Vite |
| `preact` | Preact with Vite |
| `hummingbird` | Full-stack Swift with [Hummingbird](https://github.com/hummingbird-project/hummingbird) server |

To use a specific template:

```bash
npx create-velox-app my-velox-app --template react-ts
```

The **Hummingbird template** is particularly interesting for Swift developers who want to write both their desktop app backend and a companion web server entirely in Swift—sharing models, validation logic, and business rules between them.

### Option 2: Using the Velox CLI

If you have the Velox CLI installed:

```bash
velox init --name "MyApp" --identifier "com.example.myapp"
swift build
swift run MyApp
```

### Option 3: Manual Setup

Create your project directory and set up the structure manually.

## Project Structure

A Velox project separates Swift backend code from frontend assets:

```
my-velox-app/
├── Package.swift           # Swift Package manifest
├── velox.json              # Velox configuration
├── Sources/
│   └── MyApp/
│       └── main.swift      # Application entry point
└── assets/
    ├── index.html          # Frontend UI
    ├── styles.css          # Styles
    └── app.js              # JavaScript logic
```

## Step 1: Create the Configuration

Create `velox.json` in your project root. This file defines your app's identity, window settings, and asset location:

```json
{
    "productName": "MyApp",
    "version": "1.0.0",
    "identifier": "com.example.myapp",
    "app": {
        "windows": [{
            "label": "main",
            "title": "My Velox App",
            "width": 800,
            "height": 600,
            "url": "app://localhost/"
        }]
    },
    "build": {
        "frontendDist": "assets"
    }
}
```

Key settings:
- **productName**: Your app's display name
- **identifier**: Unique bundle identifier (reverse domain)
- **windows**: Array of window configurations
- **frontendDist**: Directory containing your HTML/CSS/JS files

## Step 2: Create the Frontend

### assets/index.html

Create the main HTML file that serves as your app's UI:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My Velox App</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Welcome to Velox!</h1>

        <form id="greet-form">
            <input
                type="text"
                id="name-input"
                placeholder="Enter your name"
                autocomplete="off"
            >
            <button type="submit">Greet</button>
        </form>

        <p id="greeting-output" class="output"></p>
    </div>

    <script src="app.js"></script>
</body>
</html>
```

### assets/styles.css

Add styles for your app:

```css
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 Helvetica, Arial, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
}

.container {
    background: white;
    padding: 2rem 3rem;
    border-radius: 12px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
    text-align: center;
    max-width: 400px;
    width: 90%;
}

h1 {
    color: #333;
    margin-bottom: 1.5rem;
    font-size: 1.75rem;
}

form {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
}

input {
    flex: 1;
    padding: 0.75rem 1rem;
    font-size: 1rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    outline: none;
    transition: border-color 0.2s;
}

input:focus {
    border-color: #667eea;
}

button {
    padding: 0.75rem 1.5rem;
    font-size: 1rem;
    font-weight: 600;
    color: white;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: transform 0.1s, box-shadow 0.2s;
}

button:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

button:active {
    transform: translateY(0);
}

.output {
    min-height: 1.5rem;
    padding: 1rem;
    background: #f8f9fa;
    border-radius: 8px;
    color: #333;
    font-size: 1.1rem;
}

.output:empty {
    display: none;
}
```

### assets/app.js

Add the JavaScript that communicates with Swift:

```javascript
// Wait for DOM to be ready
document.addEventListener('DOMContentLoaded', () => {
    const form = document.getElementById('greet-form');
    const nameInput = document.getElementById('name-input');
    const output = document.getElementById('greeting-output');

    form.addEventListener('submit', async (e) => {
        e.preventDefault();

        const name = nameInput.value.trim() || 'World';

        try {
            // Call the Swift backend
            const message = await window.Velox.invoke('greet', { name });
            output.textContent = message;
        } catch (error) {
            output.textContent = `Error: ${error.message}`;
            console.error('Greet command failed:', error);
        }
    });
});
```

## Step 3: Create the Swift Backend

### Package.swift

Set up your Swift package with Velox dependencies:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/velox-apps/velox.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "VeloxRuntimeWry", package: "velox"),
                .product(name: "VeloxRuntime", package: "velox")
            ],
            resources: [
                .copy("../../assets"),
                .copy("../../velox.json")
            ]
        )
    ]
)
```

### Sources/MyApp/main.swift

Create the Swift entry point that handles commands:

```swift
import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Command Arguments

struct GreetArgs: Codable, Sendable {
    let name: String
}

// MARK: - Commands

let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
        "Hello, \(args.name)! Greetings from Swift!"
    }
}

// MARK: - Main

func main() {
    guard Thread.isMainThread else {
        fatalError("Velox must run on the main thread")
    }

    // Get the directory containing this source file
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        // VeloxAppBuilder reads velox.json and serves assets automatically
        let app = try VeloxAppBuilder(directory: projectDir)
            .registerCommands(registry)

        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
```

## Step 4: Build and Run

```bash
# Build the project (first build compiles the Rust FFI layer)
swift build

# Run your app
swift run MyApp
```

A window should appear with your greeting app. Enter a name and click "Greet" to see the response from Swift!

## Understanding the Code

### Configuration-Driven Setup

`VeloxAppBuilder` reads `velox.json` to configure:
- Window size, title, and position
- Asset directory location
- Custom protocols (`app://` for assets, `ipc://` for commands)

```swift
let app = try VeloxAppBuilder(directory: projectDir)
    .registerCommands(registry)
```

### Command Registration

Commands are type-safe functions that the frontend can call:

```swift
struct GreetArgs: Codable, Sendable {
    let name: String
}

let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
        "Hello, \(args.name)!"
    }
}
```

### Frontend Communication

JavaScript calls Swift using the injected `window.Velox.invoke()`:

```javascript
const message = await window.Velox.invoke('greet', { name: 'World' });
```

The response is automatically JSON-encoded and returned as a Promise.

## Development Workflow

For rapid iteration, use the Velox CLI:

```bash
# Start development mode with hot reload
velox dev
```

This watches for changes to both Swift and frontend files:
- **Swift changes**: Triggers rebuild and restart
- **Frontend changes**: Triggers quick restart (no rebuild needed)

## Next Steps

Now that you have a working app, explore these topics:

- <doc:VeloxArchitecture> — Understand how Velox works under the hood
- <doc:CreatingCommands> — Learn all three ways to define commands
- <doc:BuildingPlugins> — Extend Velox with custom functionality
- <doc:ManagingState> — Share state across commands
- <doc:Configuration> — Full velox.json reference
