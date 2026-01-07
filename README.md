Bringing Tauri to Swift developers.

I love Rust as much as the next security paranoid person, but I do not love it to write apps,
it gets in my way, and I am too old to develop an appreciation for poetry or Rust.   So this 
is a port of Tauri to Swift so I can both build desktop apps using HTML with Swift backends
and fill me with joy.

Discord: [invite](https://discord.gg/nZKv7kkvb)

## Documentation

[Documentation, tutorials and guides](https://velox-apps.github.io/velox/).

## Building

The Swift package declares a build-tool plugin that automatically compiles the Rust FFI crate
whenever `VeloxRuntimeWryFFI` is built. Simply run:

```bash
swift build
```

The plugin will invoke `cargo build` with the correct configuration (`debug` or `release`) and
emit libraries into `runtime-wry-ffi/target`. If you prefer to build the Rust crate manually you
can still run `cargo build` or `cargo build --release` inside `runtime-wry-ffi/`.

By default the plugin runs Cargo in offline mode to avoid sandboxed network access and ensures
`velox/.cargo/config.toml` patch overrides are picked up. If you need Cargo to fetch from the
network, set `VELOX_CARGO_ONLINE=1` when building.

## Create New Projects

Use the [create-velox-app](https://github.com/velox-apps/create-velox-app) command to create a new
blank project, starting from one of the built-in templates.

## Velox CLI

Velox includes a CLI tool for development workflow, similar to Tauri's CLI.

### Building the CLI

```bash
swift build --product velox
```

The CLI binary will be available at `.build/debug/velox`.

### Commands

#### `velox init` - Initialize a New Project

Initialize Velox in a new or existing directory:

```bash
# Initialize with defaults (derives name from directory)
velox init

# Specify product name and identifier
velox init --name "MyApp" --identifier "com.example.myapp"

# Overwrite existing files
velox init --force
```

This creates:
```
your-project/
├── Package.swift       # Swift package manifest
├── Sources/
│   └── YourApp/
│       └── main.swift  # App entry point with IPC handlers
├── assets/
│   └── index.html      # Frontend UI template
└── velox.json          # Velox configuration
```

#### `velox dev` - Development Mode

Run the app in development mode with hot reloading:

```bash
# Run with auto-detected target
velox dev

# Specify a target explicitly
velox dev MyApp

# Run in release mode
velox dev --release

# Disable file watching
velox dev --no-watch

# Override dev server port
velox dev --port 3000
```

Features:
- Executes `beforeDevCommand` from velox.json (e.g., `npm run dev`)
- Waits for dev server at `devUrl` if configured
- Builds and runs the Swift app with `VELOX_DEV_URL` set
- **Dev server proxy**: When `devUrl` is set, the `app://` protocol proxies requests to your dev server, enabling HMR from tools like Vite
- Watches for Swift file changes and rebuilds automatically
- **Smart reload**: Frontend-only changes trigger a quick restart without rebuild
- Graceful shutdown with Ctrl+C

#### `velox build` - Production Build

Build the app for production:

```bash
# Release build (default)
velox build

# Debug build
velox build --debug

# Create macOS app bundle (.app)
velox build --bundle

# Specify target
velox build MyApp

# Debug build with app bundle
velox build --debug --bundle
```

The `--bundle` flag creates a complete macOS app bundle:
```
.build/release/MyApp.app/
├── Contents/
│   ├── Info.plist      # Generated from velox.json
│   ├── MacOS/
│   │   └── MyApp       # Executable
│   └── Resources/
│       └── assets/     # Frontend files (from frontendDist)
```

### Configuration for CLI

The CLI uses settings from `velox.json`:

```json
{
  "productName": "MyApp",
  "version": "1.0.0",
  "identifier": "com.example.myapp",
  "build": {
    "devUrl": "http://localhost:5173",
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build",
    "beforeBundleCommand": "npm run prepare-bundle",
    "frontendDist": "dist",
    "env": {
      "API_URL": "https://api.example.com",
      "DEBUG": "true"
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `devUrl` | Dev server URL; enables proxy mode (see below) |
| `beforeDevCommand` | Command to run before `velox dev` (e.g., start Vite) |
| `beforeBuildCommand` | Command to run before `velox build` (e.g., build frontend) |
| `beforeBundleCommand` | Command to run before creating app bundle |
| `frontendDist` | Directory containing frontend assets for bundling |
| `env` | Environment variables to inject into build and dev processes |

### Environment Variables

Velox supports environment variable injection from multiple sources:

1. **`.env`** - Base environment file
2. **`.env.development`** or **`.env.production`** - Mode-specific overrides
3. **`.env.local`** - Local overrides (gitignored)
4. **`velox.json` build.env** - Configuration-defined variables

Priority (highest to lowest): system env > velox.json > .env.local > .env.[mode] > .env

Example `.env` file:
```
API_URL=https://api.example.com
DEBUG=true
# Comments are supported
MULTILINE="line1\nline2"
```

### Frontend Development Modes

Velox offers two approaches for serving frontend assets during development. Choose based on your project's complexity and tooling preferences.

#### Option 1: Local Asset Serving (Simple Projects)

**When to use:** Static HTML/CSS/JS without a build step, simple projects, or when you want the fastest possible reload cycle.

```json
{
  "build": {
    "frontendDist": "assets"
  }
}
```

**How it works:**
- `velox dev` serves files directly from the `frontendDist` directory (e.g., `assets/`)
- File watcher monitors both Swift sources AND frontend files
- When you edit `index.html`, `styles.css`, or `app.js`, the app restarts instantly (no rebuild)
- Swift file changes trigger a full rebuild

**Pros:**
- Zero configuration - just put HTML files in `assets/`
- No Node.js or npm required
- Fastest restart for simple frontend changes
- Great for prototyping and learning

**Cons:**
- No transpilation (TypeScript, JSX, etc.)
- No module bundling
- No Hot Module Replacement (page fully reloads)
- Manual browser refresh via app restart

#### Option 2: Dev Server Proxy (Modern Web Tooling)

**When to use:** Projects using Vite, webpack, or other modern frontend toolchains that provide HMR.

```json
{
  "build": {
    "devUrl": "http://localhost:5173",
    "beforeDevCommand": "npm run dev",
    "frontendDist": "dist"
  }
}
```

**How it works:**
1. `beforeDevCommand` starts your frontend dev server (e.g., Vite)
2. Velox waits for `devUrl` to respond before launching the app
3. The `VELOX_DEV_URL` environment variable is passed to your Swift app
4. The `app://` protocol proxies all requests to the dev server
5. File watcher only monitors Swift sources (frontend HMR is handled by Vite)

**Pros:**
- **Hot Module Replacement (HMR)** - instant updates without page reload
- Full modern toolchain support (TypeScript, React, Vue, Tailwind, etc.)
- Source maps for debugging
- Consistent `app://` protocol between dev and production
- CORS-free development

**Cons:**
- Requires Node.js and npm
- More configuration
- Slightly slower initial startup (waiting for dev server)

#### Comparison Table

| Feature | Local Assets | Dev Server Proxy |
|---------|-------------|------------------|
| Setup complexity | Minimal | Requires npm project |
| Frontend tooling | None (vanilla JS) | Full (Vite, webpack, etc.) |
| TypeScript/JSX | Not supported | Fully supported |
| Hot Module Replacement | No (app restart) | Yes (instant) |
| Page reload on change | Full restart | Partial/none (HMR) |
| Swift change handling | Rebuild + restart | Rebuild + restart |
| Production build | Copy files | Run build command |

#### Switching Between Modes

To switch from proxy mode to local asset serving, simply remove or comment out `devUrl`:

```json
{
  "build": {
    // "devUrl": "http://localhost:5173",  // Commented out = local mode
    // "beforeDevCommand": "npm run dev",   // Not needed without devUrl
    "frontendDist": "assets"
  }
}
```

The same `frontendDist` directory is used for both development (local mode) and production builds.

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
swift run CommandsManual
swift run CommandsManualRegistry
swift run Resources
swift run WindowControls
swift run MultiWebView
swift run DynamicHTML
swift run Events
swift run Tray
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
| **Commands** | @VeloxCommand macro for cleanest command definitions | Bundled assets |
| **CommandsManual** | Manual IPC routing with switch statement | Bundled assets |
| **CommandsManualRegistry** | Type-safe command DSL with automatic JSON decoding | Bundled assets |
| **Resources** | Resource bundling and path resolution | Bundled assets |
| **WindowControls** | Comprehensive window/webview API demonstration | Self-contained |
| **MultiWebView** | Multiple child webviews: local app + GitHub, tauri.app, Twitter | Mixed |
| **DynamicHTML** | Swift-rendered dynamic HTML with counter, todos, and themes | Self-contained |
| **Events** | Event system: backend-to-frontend and frontend-to-backend events | Self-contained |
| **Tray** | System tray icon with context menu (macOS) | Self-contained |

### Configuration (velox.json)

Velox supports a configuration file (`velox.json`) similar to Tauri's `tauri.conf.json`. This allows declarative app configuration:

```json
{
  "$schema": "https://velox.dev/schema/velox.schema.json",
  "productName": "MyApp",
  "version": "1.0.0",
  "identifier": "com.example.myapp",
  "app": {
    "windows": [
      {
        "label": "main",
        "title": "My Application",
        "width": 800,
        "height": 600,
        "url": "app://localhost/",
        "create": true,
        "visible": true,
        "resizable": true,
        "customProtocols": ["app", "ipc"]
      }
    ],
    "macOS": {
      "activationPolicy": "regular"
    }
  },
  "build": {
    "frontendDist": "assets"
  }
}
```

Use `VeloxAppBuilder` to create your app from configuration:

```swift
import VeloxRuntime
import VeloxRuntimeWry

let config = try VeloxConfig.load(from: URL(fileURLWithPath: "path/to/app"))
let eventLoop = VeloxRuntimeWry.EventLoop()!

let app = VeloxAppBuilder(config: config)
  .registerProtocol("app") { request in
    // Serve assets
  }
  .registerProtocol("ipc") { request in
    // Handle IPC commands
  }
  .build(eventLoop: eventLoop)
```

**Platform-Specific Overrides**: Create `velox.macos.json`, `velox.ios.json`, etc. to override settings per platform using RFC 7396 JSON Merge Patch.

### IPC Communication

Both approaches use custom protocols for IPC between Swift and the webview. Velox injects a
`window.Velox.invoke` helper that supports both immediate and deferred command responses:

```javascript
// JavaScript: invoke a Swift command (preferred)
const message = await window.Velox.invoke('greet', { name: 'World' });
```

If you need a custom helper, you can still use `fetch` for immediate responses:

```javascript
async function invoke(command, args = {}) {
  const response = await fetch(`ipc://localhost/${command}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  return (await response.json()).result;
}
```

#### Deferred Responses

To return after the IPC handler completes (for modal dialogs or long tasks), defer the response
and resolve it later. `window.Velox.invoke` will await the final result automatically:

```swift
struct DelayedEchoArgs: Codable, Sendable { let message: String; let delayMs: Int? }

commands.register("delayed_echo", args: DelayedEchoArgs.self, returning: DeferredCommandResponse.self) { args, ctx in
  let deferred = try ctx.deferResponse()
  let delay = max(0, args.delayMs ?? 500)
  DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
    deferred.responder.resolve(args.message)
  }
  return deferred.pending
}
```

```javascript
const reply = await window.Velox.invoke('delayed_echo', { message: 'Hello later', delayMs: 800 });
```

#### @VeloxCommand Macro (Recommended)

Velox provides the `@VeloxCommand` macro for the cleanest command definitions, similar to Tauri's `#[tauri::command]`:

```swift
import VeloxMacros
import VeloxRuntimeWry

// Define response types
struct GreetResponse: Codable, Sendable {
  let message: String
}

// Commands must be in a container (enum/struct) for macro expansion
enum Commands {
  @VeloxCommand
  static func greet(name: String) -> GreetResponse {
    GreetResponse(message: "Hello, \(name)!")
  }

  @VeloxCommand
  static func divide(numerator: Double, denominator: Double) throws -> MathResponse {
    guard denominator != 0 else {
      throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: numerator / denominator)
  }

  // Access state via CommandContext parameter
  @VeloxCommand
  static func increment(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.increment())
  }

  // Custom command name
  @VeloxCommand("get_counter")
  static func getCounter(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.counter)
  }
}

// Register macro-generated commands
let registry = commands {
  Commands.greetCommand      // Generated by @VeloxCommand
  Commands.divideCommand
  Commands.incrementCommand
  Commands.getCounterCommand
}
```

See **Examples/Commands** for a complete demonstration of the `@VeloxCommand` macro.

#### Type-Safe Command DSL

For cases where you prefer explicit control, use the command DSL directly:

```swift
import VeloxRuntime
import VeloxRuntimeWry

// Define typed arguments and responses
struct GreetArgs: Codable, Sendable {
  let name: String
}

struct GreetResponse: Codable, Sendable {
  let message: String
}

// Register commands using the DSL
let registry = commands {
  command("greet", args: GreetArgs.self, returning: GreetResponse.self) { args, _ in
    GreetResponse(message: "Hello, \(args.name)!")
  }

  command("divide", args: DivideArgs.self, returning: MathResponse.self) { args, _ in
    guard args.denominator != 0 else {
      throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: args.numerator / args.denominator)
  }

  command("increment", returning: CounterResponse.self) { context in
    let state: AppState = context.requireState()
    return CounterResponse(value: state.increment())
  }
}

// Create IPC handler and register protocol
let stateContainer = StateContainer().manage(AppState())
let ipcHandler = createCommandHandler(registry: registry, stateContainer: stateContainer)
let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc", handler: ipcHandler)
```

See **Examples/CommandsManualRegistry** for a complete demonstration of the type-safe command DSL.

#### Manual IPC Handling

For simpler cases, you can handle IPC requests manually:

```swift
// Swift: handle IPC requests manually
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
