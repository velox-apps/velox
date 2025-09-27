# VeloxRuntimeWry

Early Swift Package scaffolding for the Velox port of Tauri's `tauri-runtime-wry` crate.

## Layout

- `Package.swift`: Swift Package definition exposing the `VeloxRuntimeWry` library target.
- `Sources/VeloxRuntimeWry`: Swift surface area that mirrors the Tauri runtime concepts with
  Velox naming.
- `Sources/VeloxRuntimeWryFFI`: Lightweight C target that bridges into the Rust static library.
- `runtime-wry-ffi`: Rust crate producing a `velox_runtime_wry_ffi` static/dynamic library that
  re-exports selected pieces of `tao`, `wry`, and `tauri-runtime-wry`.

## Building

The Swift package declares a build-tool plugin that automatically compiles the Rust FFI crate
whenever `VeloxRuntimeWryFFI` is built. Simply run:

```bash
swift build
```

The plugin will invoke `cargo build` with the correct configuration (`debug` or `release`) and
emit libraries into `runtime-wry-ffi/target`. If you prefer to build the Rust crate manually you
can still run `cargo build` or `cargo build --release` inside `runtime-wry-ffi/`.

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

`VeloxRuntimeWry.Runtime` is in the middle of a Swift-native rewrite. The class currently advertises availability but returns `nil` on unsupported hosts while the new runtime layer evolves; the event-loop based APIs remain the primary entry point until the dedicated Swift runtime is feature-complete.
