# Velox Architecture

Understand how Velox brings together Swift, Rust, and web technologies.

## Overview

Velox is a Swift port of [Tauri](https://tauri.app), designed to let you build desktop applications with web frontends and Swift backends. It uses the same underlying technologies as Tauri—Tao for window management and Wry for WebView rendering—but exposes them through a Swift-native API.

## Layer Architecture

Velox uses a layered architecture that bridges Swift and Rust:

```
┌─────────────────────────────────────────────────────┐
│  Your Swift Application                             │
│  • Business logic, command handlers, plugins        │
├─────────────────────────────────────────────────────┤
│  VeloxRuntimeWry                                    │
│  • Swift API: EventLoop, Window, Webview            │
│  • VeloxAppBuilder for easy setup                   │
├─────────────────────────────────────────────────────┤
│  VeloxRuntime                                       │
│  • Core protocols and types                         │
│  • Commands, Events, State, Plugins                 │
├─────────────────────────────────────────────────────┤
│  VeloxRuntimeWryFFI (C Bridge)                      │
│  • C function declarations                          │
│  • Type bridging between Swift and Rust             │
├─────────────────────────────────────────────────────┤
│  runtime-wry-ffi (Rust)                             │
│  • Rust library exposing C FFI                      │
│  • Wraps Tao and Wry                                │
├─────────────────────────────────────────────────────┤
│  Tao + Wry                                          │
│  • Tao: Cross-platform window management            │
│  • Wry: Native WebView (WKWebView on macOS)         │
└─────────────────────────────────────────────────────┘
```

## Key Components

### VeloxRuntime

The core module defining platform-independent protocols and types:

- **``VeloxPlugin``** — Protocol for extending Velox with plugins
- **``CommandRegistry``** — Type-safe command registration
- **``StateContainer``** — Thread-safe application state
- **``EventEmitter``** / **``EventListener``** — Event system
- **``Channel``** — Streaming data to the frontend

### VeloxRuntimeWry

The Wry-based implementation providing:

- **`EventLoop`** — The main application run loop
- **`Window`** — Native window management
- **`Webview`** — WebView control and JavaScript execution
- **`CustomProtocol`** — URL scheme handlers for IPC
- **`VeloxAppBuilder`** — High-level app configuration

### Rust FFI Layer

The `runtime-wry-ffi` crate provides:

- C-compatible function exports
- Memory-safe bridging between Swift and Rust
- Access to Tao (windowing) and Wry (WebView) functionality

## Communication Model

### Custom URL Protocols

Velox uses custom URL protocols for frontend-backend communication:

| Protocol | Purpose |
|----------|---------|
| `app://` | Serve HTML, CSS, JS, and other assets |
| `ipc://` | Handle command invocations from JavaScript |

### IPC Flow

1. **JavaScript calls** `window.Velox.invoke('command', args)`
2. **Request sent** via `fetch('ipc://localhost/command', { body: JSON.stringify(args) })`
3. **Swift handler** receives the request, decodes arguments, executes logic
4. **Response returned** as JSON back to JavaScript
5. **Promise resolves** with the result

```
┌──────────────┐                    ┌──────────────┐
│  JavaScript  │  ──── invoke ────▶ │    Swift     │
│   Frontend   │                    │   Backend    │
│              │ ◀── JSON result ── │              │
└──────────────┘                    └──────────────┘
         │                                  │
         │        Custom Protocol           │
         │      (ipc://localhost/)          │
         └──────────────────────────────────┘
```

### Deferred Responses

For operations that can't complete immediately (like modal dialogs), Velox supports deferred responses:

```swift
command("show_dialog") { context in
    let deferred = try context.deferResponse()

    DispatchQueue.main.async {
        let result = showModalDialog()
        deferred.responder.resolve(result)
    }

    return deferred.pending
}
```

## Event Loop

The event loop is the heart of a Velox application:

```swift
let eventLoop = VeloxRuntimeWry.EventLoop()

eventLoop.pump { event in
    switch event {
    case .windowCloseRequested:
        return .exit
    case .keyboardInput(let key):
        handleKeyPress(key)
        return .wait
    default:
        return .wait
    }
}
```

Events include:
- Window lifecycle (created, closed, resized, moved)
- User input (keyboard, mouse, touch)
- System events (DPI changes, file drops)

## Process Model

Unlike Electron (which runs Chromium), Velox uses the system's native WebView:

| Platform | WebView Engine |
|----------|---------------|
| macOS | WKWebView (WebKit) |
| iOS | WKWebView (WebKit) |
| Windows | WebView2 (Chromium) |
| Linux | WebKitGTK |

This means:
- **Smaller binaries** — No bundled browser engine
- **Lower memory** — Shared system WebView
- **Native look** — Platform-consistent rendering

## Comparison with Tauri

| Aspect | Tauri | Velox |
|--------|-------|-------|
| Backend Language | Rust | Swift |
| Frontend | Any web framework | Any web framework |
| Window Management | Tao | Tao (via FFI) |
| WebView | Wry | Wry (via FFI) |
| Platforms | Windows, macOS, Linux, iOS, Android | macOS, iOS |
| Binary Size | ~2-5 MB | ~2-5 MB |

Velox is ideal for Swift developers who want Tauri's architecture without learning Rust.

## See Also

- <doc:GettingStarted>
- <doc:CreatingCommands>
- <doc:EventSystem>
