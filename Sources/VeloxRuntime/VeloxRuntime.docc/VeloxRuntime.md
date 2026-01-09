# ``VeloxRuntime``

Build beautiful desktop applications using Swift and HTML.

@Metadata {
    @DisplayName("Velox")
    @TitleHeading("Framework")
}

## Overview

Velox brings the power of [Tauri](https://tauri.app) to Swift developers. Create native macOS and iOS applications with HTML/CSS/JavaScript frontends and Swift backends—combining the flexibility of web technologies with the performance and safety of Swift.

```swift
import VeloxRuntimeWry

let app = try VeloxAppBuilder(directory: projectDir)
    .registerAppProtocol { _ in "<h1>Hello, Velox!</h1>" }
    .registerCommands(registry)
try app.run()
```

### Why Velox?

- **Swift-First**: Write your application logic in Swift, not Rust
- **Web UI Flexibility**: Use any frontend framework—React, Vue, Svelte, or vanilla HTML
- **Native Performance**: Powered by Wry's native WebView, not Electron
- **Small Binaries**: Ship lightweight apps without bundling a browser engine
- **Tauri Ecosystem**: Built on proven Tauri foundations (Tao, Wry)

### Architecture

Velox uses a layered architecture:

1. **Swift Application** — Your business logic and command handlers
2. **VeloxRuntimeWry** — Swift API for windows, webviews, and IPC
3. **Rust FFI** — Bridge to the native Tao/Wry libraries
4. **Tao/Wry** — Cross-platform window management and WebView rendering

Communication between your frontend (HTML/JavaScript) and backend (Swift) happens through a type-safe IPC system using custom URL protocols.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:VeloxArchitecture>
- <doc:Configuration>
- <doc:Bundling>

### Commands and IPC

- <doc:CreatingCommands>
- <doc:DeferredResponses>
- ``CommandRegistry``
- ``CommandContext``

### Plugins

- <doc:BuildingPlugins>
- <doc:BuiltinPlugins>
- ``VeloxPlugin``

### State Management

- <doc:ManagingState>
- ``StateContainer``

### Events and Streaming

- <doc:EventSystem>
- ``EventEmitter``
- ``EventListener``
- ``Channel``

### Tutorials

- <doc:Table-of-Contents>
