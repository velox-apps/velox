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
