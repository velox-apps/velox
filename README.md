Bringing Tauri to Swift developers.

I love Rust as much as the next security paranoid person, but I do not love it to write apps,
it gets in my way, and I am too old to develop an appreciation for poetry or Rust.   So this 
is a port of Tauri to Swift so I can both build desktop apps using HTML with Swift backends
and fill me with joy.

Discord: [invite](https://discord.gg/nZKv7kkvb)

## Building

The Swift package declares a build-tool plugin that automatically compiles the Rust FFI crate
whenever `VeloxRuntimeWryFFI` is built. Simply run:

```bash
swift build
```

The plugin will invoke `cargo build` with the correct configuration (`debug` or `release`) and
emit libraries into `runtime-wry-ffi/target`. If you prefer to build the Rust crate manually you
can still run `cargo build` or `cargo build --release` inside `runtime-wry-ffi/`.

## Examples

The repository includes several example applications demonstrating Velox capabilities. Examples are located in the `Examples/` directory.

### Running Examples

Build and run any example using Swift Package Manager:

```bash
# Build all examples
swift build

# Run a specific example
swift run HelloWorld
swift run HelloWorld2
swift run MultiWindow
swift run State
swift run Splashscreen
swift run Streaming
swift run RunReturn
```


## Swift Surface Preview

```swift
let loop = VeloxRuntimeWry.EventLoop()
let proxy = loop?.makeProxy()
let window = loop?.makeWindow(configuration: .init(width: 800, height: 600, title: "Velox"))
let webview = window?.makeWebview(configuration: .init(url: "https://tauri.app"))

loop?.pump { event in
  switch event {
  case .loopDestroyed, .userExit:
    return .exit
  default:
    return .poll
  }
}

proxy?.requestExit()
```

This demonstrates the bridging between Swift and the underlying Tao/Wry event loop, window, and
webview primitives exposed by the Rust shim. Event callbacks now deliver structured metadata (via
JSON) which the Swift layer normalises into strongly-typed `VeloxRuntimeWry.Event` values.

### Event Metadata

`VeloxRuntimeWry.Event` exposes rich keyboard, pointer, focus, DPI, and file-drop information so
Swift applications can respond to Tao/Wry input without having to touch the underlying JSON payloads.

### Window & Webview Controls

The Swift API now includes helpers to:

- configure window titles, fullscreen state, sizing constraints, z-order, and visibility;
- request redraws or reposition windows without touching tao directly;
- drive Wry webviews via navigation, reload, JavaScript evaluation, zoom control, visibility toggles, and browsing-data clearing.
- toggle advanced window capabilities including decorations, always-on-bottom/workspace visibility, content protection, focus/focusable state, cursor controls, drag gestures, and attention requests.

### Runtime Lifecycle

Velox now ships a nascent `VeloxRuntime` module that defines the Swift-first protocols mirroring Tauri's runtime traits. `VeloxRuntimeWry.Runtime` remains a stub while the native implementation is completed; the event-loop based APIs remain the primary entry point until the dedicated Swift runtime is feature-complete.

## Examples

The repository includes several example applications demonstrating Velox capabilities. Examples are located in the `Examples/` directory.

### Running Examples

Build and run any example using Swift Package Manager:

```bash
# Build all examples
swift build

# Run a specific example
swift run HelloWorld
swift run HelloWorld2
swift run MultiWindow
swift run State
swift run Splashscreen
swift run Streaming
swift run RunReturn
swift run Commands
swift run Resources
swift run WindowControls
swift run MultiWebView
swift run DynamicHTML
```

### Asset Loading Approaches

Velox supports two approaches for loading web content, mirroring Tauri's flexibility:

#### 1. Self-Contained (Inline HTML)

The simplest approach embeds HTML directly in Swift code. This is ideal for simple UIs or when you want a single-binary deployment with no external dependencies.

**Example: HelloWorld**

```swift
let html = """
<!doctype html>
<html>
  <body>
    <h1>Hello from Velox!</h1>
  </body>
</html>
"""

let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
  VeloxRuntimeWry.CustomProtocol.Response(
    status: 200,
    headers: ["Content-Type": "text/html"],
    body: Data(html.utf8)
  )
}
```

**Pros:**
- Single binary, no external files needed
- Simple deployment
- Good for small UIs

**Cons:**
- HTML/CSS/JS changes require recompilation
- Less suitable for complex UIs
- No separation of concerns

#### 2. Bundled Assets (External Files)

For larger applications, keep HTML, CSS, and JavaScript as separate files loaded at runtime. This mirrors Tauri's asset bundling approach.

**Example: HelloWorld2**

```
Examples/HelloWorld2/
├── main.swift          # Swift entry point with AssetBundle
└── assets/
    ├── index.html      # HTML markup
    ├── styles.css      # Stylesheet
    └── app.js          # JavaScript
```

The `AssetBundle` struct discovers and serves files from the assets directory:

```swift
struct AssetBundle {
  let basePath: String

  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    // Load file and detect MIME type
  }
}

let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { request in
  guard let url = URL(string: request.url),
        let asset = assets.loadAsset(path: url.path) else {
    return notFoundResponse()
  }
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 200,
    headers: ["Content-Type": asset.mimeType],
    body: asset.data
  )
}
```

**Pros:**
- Separation of concerns (Swift logic vs web UI)
- Edit HTML/CSS/JS without recompiling Swift
- Better for complex UIs and larger teams
- Familiar web development workflow

**Cons:**
- Requires bundling assets with the binary
- Slightly more complex deployment

### Example Overview

| Example | Description | Asset Approach |
|---------|-------------|----------------|
| **HelloWorld** | Basic window with inline HTML and IPC | Self-contained |
| **HelloWorld2** | Same functionality with external assets | Bundled assets |
| **MultiWindow** | Multiple windows running simultaneously | Self-contained |
| **State** | Shared state across IPC calls | Self-contained |
| **Splashscreen** | Splash window before main window | Self-contained |
| **Streaming** | Server-sent events from Swift to webview | Self-contained |
| **RunReturn** | Manual event loop control | Self-contained |
| **Commands** | Various IPC command patterns (sync, async, fallible, stateful) | Self-contained |
| **Resources** | Resource bundling and path resolution | Bundled assets |
| **WindowControls** | Comprehensive window/webview API demonstration | Self-contained |
| **MultiWebView** | Multiple child webviews: local app + GitHub, tauri.app, Twitter | Mixed |
| **DynamicHTML** | Swift-rendered dynamic HTML with counter, todos, and themes | Self-contained |

### IPC Communication

Both approaches use custom protocols for IPC between Swift and the webview:

```javascript
// JavaScript: invoke a Swift command
async function invoke(command, args = {}) {
  const response = await fetch(`ipc://localhost/${command}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  return (await response.json()).result;
}

// Call Swift's greet function
const message = await invoke('greet', { name: 'World' });
```

```swift
// Swift: handle IPC requests
let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
  let command = URL(string: request.url)?.path.trimmingCharacters(in: .init(charactersIn: "/"))

  switch command {
  case "greet":
    let name = parseArgs(request.body)["name"] as? String ?? "World"
    return jsonResponse(["result": "Hello \(name)!"])
  default:
    return errorResponse("Unknown command")
  }
}
```

## The Small Print set in H2

### Layout

- `Package.swift`: Swift Package definition exposing the `VeloxRuntimeWry` library target.
- `Sources/VeloxRuntimeWry`: Swift surface area that mirrors the Tauri runtime concepts with
  Velox naming.
- `Sources/VeloxRuntimeWryFFI`: Lightweight C target that bridges into the Rust static library.
- `runtime-wry-ffi`: Rust crate producing a `velox_runtime_wry_ffi` static/dynamic library that
  re-exports selected pieces of `tao`, `wry`, and `tauri-runtime-wry`.

### Build Modes

Velox supports two build modes for the Rust FFI crate:

#### Standard Build (crates.io)

Uses published versions of `tao` and `wry` from crates.io. This is the default for clean checkouts and CI:

```bash
# Remove local patches if present
rm -f .cargo/config.toml
swift build
```

#### Local Development Build

Uses locally patched `tao` and `wry` with additional testing features. Requires sibling checkouts of these repositories with the `velox-testing` feature added to tao's default features.

```bash
# Ensure .cargo/config.toml exists with patches (at package root, not runtime-wry-ffi)
# Then build with local-dev feature:
VELOX_LOCAL_DEV=1 swift build
```

The `.cargo/config.toml` (in the package root) patches crates.io dependencies with local paths:
```toml
[patch.crates-io]
tao = { path = "../tao" }
wry = { path = "../wry" }
```

**Requirements for Local Dev:**
- Local `tao` version must match crates.io (currently 0.34.5)
- Local `tao` must have `velox-testing` in its default features in `Cargo.toml`
- Local `wry` version must match crates.io (currently 0.53.5)

