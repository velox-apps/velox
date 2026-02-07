# Velox TODO - Verified Gaps (as of 2026-02-07)

This document lists **only** items confirmed missing in the current codebase.

## Near-Term
- [ ] Tray icon image support is missing (no initial icon in `VeloxTrayConfig`, no `setIcon`/`setIconPath` API in FFI/Swift). `velox/runtime-wry-ffi/src/lib.rs:393`, `velox/Sources/VeloxRuntimeWry/VeloxRuntimeWry.swift:3734`.
- [ ] Radio menu items are not implemented (only normal/check/icon/predefined/separator/submenu exist). `velox/Sources/VeloxPluginMenu/MenuPlugin.swift:322`.
- [ ] Plugin-defined permissions are not modeled in the plugin protocol. `velox/Sources/VeloxRuntime/Plugin.swift:126`.
- [ ] Platform-specific capability restrictions are not modeled. `velox/Sources/VeloxRuntime/Permission.swift:114`.
- [ ] `bundle.resources` does not support glob patterns; only literal paths are copied. `velox/Sources/VeloxBundler/Bundler.swift:243`.
- [ ] Bundle metadata fields missing from config/bundler: `category`, `shortDescription`, `longDescription`, `homepage`, `license`, `copyright`. `velox/Sources/VeloxRuntime/Config.swift:658`.
- [ ] JSON5/TOML support is not implemented (JSON only via `JSONDecoder`). `velox/Sources/VeloxRuntime/Config.swift:884`.
- [ ] `mainBinaryName` override and `version` from external file are not supported. (Only root fields exist.) `velox/Sources/VeloxRuntime/Config.swift:9`.
- [ ] Schema validation is not implemented (schema URL stored but not validated). `velox/Sources/VeloxRuntime/Config.swift:12`, `velox/Sources/VeloxRuntime/Config.swift:823`.
- [ ] UI-enabled tests still need to be run on an AppKit-capable host (`VELOX_ENABLE_UI_TESTS=1`). `velox/Tests/VeloxRuntimeWryTests/EventLoopIntegrationTests.swift:48`.

## Longer-Term
- [ ] Missing plugins: HTTP client, file system, updater, global shortcut, deep link. (Only listed built-ins exist.) `velox/Sources/VeloxPlugins/VeloxPlugins.swift:10`.
- [ ] `bundle.externalBin` is not supported. `velox/Sources/VeloxRuntime/Config.swift:658`.
- [ ] `bundle.fileAssociations` is not supported. `velox/Sources/VeloxRuntime/Config.swift:658`.
- [ ] Linux bundling targets (AppImage, .deb, .rpm) are not implemented. (Only `app`/`dmg` targets exist.) `velox/Sources/VeloxRuntime/Config.swift:694`.
- [ ] Windows bundling targets (NSIS, MSI/WiX) and related signing/WebView2 modes are not implemented. (Only `app`/`dmg` targets exist.) `velox/Sources/VeloxRuntime/Config.swift:694`.
- [ ] iOS project generation / dev workflow is not implemented. (CLI has only dev/build/bundle/init.) `velox/Sources/VeloxCLI/VeloxCLI.swift:27`.
- [ ] Android project generation / dev workflow is not implemented. (CLI has only dev/build/bundle/init.) `velox/Sources/VeloxCLI/VeloxCLI.swift:27`.
