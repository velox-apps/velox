# Velox TODO - Tauri Feature Parity

This document tracks features needed to achieve parity with Tauri v2.

## Priority 1: Core Runtime Features

### Event System
- [x] Global events (`emit` from backend to all windows)
- [x] Targeted events (`emit_to` specific window/webview)
- [x] Filtered events (`emit_filter` with predicate)
- [x] Frontend listening API (`listen`, `once`, `unlisten`)
- [x] Backend event listening from frontend

### State Management
- [x] `app.manage(State)` API for registering state
- [x] State injection into command handlers
- [x] Thread-safe state access (Mutex/RwLock patterns)
- [x] State access outside commands via manager

### Command System Improvements
- [x] Type-safe command registration (result builder DSL)
- [x] Automatic argument deserialization (JSON decoding)
- [x] Typed return values (Codable responses)
- [x] State injection into commands (via CommandContext)
- [x] @VeloxCommand macro for Tauri-like command definitions
- [x] Channel streaming for large data transfers
- [x] Binary/ArrayBuffer responses (bypass JSON)
- [x] WebviewWindow injection into commands
- [x] Deferred command responses (async invoke bridge)

## Priority 2: Desktop Features

### System Tray
- [x] Tray icon creation and management
- [x] Tray menus (context menus)
- [x] Tray click events (click, double-click, right-click)
- [x] Tray hover events (enter, move, leave) - macOS/Windows only
- [x] Dynamic tray icon updates
- [x] Tray tooltip

### Menu System
- [x] Application menus (menu bar)
- [x] Context menus
- [x] Menu item types (normal, submenu)
- [x] Menu accelerators/shortcuts
- [x] Dynamic menu updates
- [x] Checkbox menu items
- [x] Separator menu items

## Priority 3: Security

### Permissions System
- [x] Capability definitions (JSON in velox.json or programmatic)
- [x] Permission grants per command
- [x] Scopes for fine-grained access control (globs, URLs, values, custom validators)
- [x] Window/webview targeting for capabilities
- [ ] Platform-specific capability restrictions

### Security Configuration
- [x] `assetProtocol` scope settings
- [x] `pattern` (brownfield vs isolation mode)
- [x] `headers` for custom HTTP response headers
- [x] `dangerousDisableAssetCspModification` flag
- [x] `freezePrototype` implementation
- [x] CSP configuration (string or directives object)
- [x] CSP injection in app protocol responses
- [x] Asset path validation with glob patterns

## Priority 4: Developer Experience

### CLI Tooling
- [x] `velox dev` command with hot reloading
- [x] `velox build` command for production builds
- [x] `velox init` for project scaffolding
- [x] File watching with configurable ignore (`.veloxignore`)
- [x] `beforeDevCommand` hook execution
- [x] `beforeBuildCommand` hook execution
- [x] `beforeBundleCommand` hook execution

### Development Features
- [x] Automatic webview reload on frontend changes
- [x] Swift recompilation on backend changes
- [x] Dev server proxy support
- [x] Environment variable injection

## Priority 5: Plugin System

### Core Plugin Infrastructure
- [x] Plugin protocol/trait definition
- [x] Plugin lifecycle hooks:
  - [x] `setup` - initialization
  - [x] `onNavigation` - URL change validation
  - [x] `onWebviewReady` - per-window init scripts
  - [x] `onEvent` - core event handling
  - [x] `onDrop` - cleanup
- [x] Plugin state management
- [x] Plugin command registration
- [ ] Plugin permission definitions (deferred to Phase 2)

### Built-in Plugins (Future)
- [ ] HTTP client plugin
- [x] Notifications plugin
- [x] Dialog plugin (open/save file, message boxes)
- [x] Clipboard plugin
- [ ] File system plugin
- [x] Shell plugin (execute commands)
- [x] Process plugin
- [ ] Updater plugin
- [ ] Global shortcut plugin
- [ ] Deep link plugin
- [x] OS Info plugin
- [x] Opener plugin (open files/URLs in external apps)

## Priority 6: Bundling & Distribution

### Bundle Configuration
- [x] `bundle.active` flag
- [x] `bundle.targets` (app, dmg)
- [x] `bundle.icon` paths
- [ ] `bundle.resources` with glob patterns
- [ ] `bundle.externalBin` for embedded binaries
- [ ] `bundle.fileAssociations`
- [ ] `bundle.category`
- [ ] `bundle.shortDescription` / `bundle.longDescription`
- [ ] `bundle.copyright` / `bundle.license`
- [ ] `bundle.homepage` / `bundle.publisher`

### macOS Bundling
- [x] App bundle generation (.app)
- [x] DMG creation (basic)
- [x] Code signing (`signingIdentity`)
- [x] Notarization support
- [x] Entitlements file support
- [x] `minimumSystemVersion`
- [x] Custom Info.plist merging
- [x] Hardened runtime

### Linux Bundling (Future)
- [ ] AppImage generation
- [ ] .deb package generation
- [ ] .rpm package generation

### Windows Bundling (Future)
- [ ] NSIS installer
- [ ] MSI (WiX) installer
- [ ] Code signing
- [ ] WebView2 installation modes

## Priority 7: Mobile Support (Deferred)

### iOS Support
- [ ] iOS project generation
- [ ] Xcode integration
- [ ] `velox ios dev` command
- [ ] iOS-specific configuration
- [ ] Swift/Kotlin plugin bridges

### Android Support
- [ ] Android project generation
- [ ] Android Studio integration
- [ ] `velox android dev` command
- [ ] Android-specific configuration
- [ ] Gradle build integration

## Missing Window Configuration Properties

- [ ] `parent` - Parent window for modal/child windows
- [ ] `shadow` - Window shadow effect (default: true)
- [ ] `titleBarStyle` - macOS: Visible/Transparent/Overlay
- [ ] `hiddenTitle` - Hide title text on macOS
- [ ] `acceptFirstMouse` - macOS click-through on inactive window
- [ ] `dataDirectory` - Custom webview data storage path
- [ ] `incognito` - Private browsing mode
- [ ] `javascriptDisabled` - Disable JavaScript execution
- [ ] `scrollBarStyle` - Native scrollbar appearance
- [ ] `preventOverflow` - Keep window within workarea
- [ ] `proxyUrl` - Webview network proxy
- [ ] `backgroundThrottling` - Background task throttling policy

## Priority 8: 

- [ ] Radio menu items (not available in muda; can simulate with checkboxes)

## Configuration Enhancements

- [ ] JSON5 support (optional feature)
- [ ] TOML support (optional feature)
- [ ] `mainBinaryName` override
- [ ] `version` from external file (package.json path)
- [ ] Schema validation

## Documentation

- [ ] API reference documentation
- [ ] Configuration reference
- [ ] Plugin development guide
- [ ] Migration guide from Tauri
- [ ] Example applications for each feature

---

## Completed Features

- [x] Configuration file loading (velox.json)
- [x] Platform-specific config merging (RFC 7396)
- [x] Window configuration (30+ properties)
- [x] Custom protocols for IPC
- [x] Asset bundling and serving
- [x] macOS activation policy
- [x] VeloxAppBuilder for declarative app creation
- [x] Basic command handling via custom protocols
- [x] Type-safe command system (CommandRegistry, CommandBuilder DSL)
- [x] @VeloxCommand macro for Tauri-like command definitions
- [x] Multiple window support
- [x] Child webview support
- [x] Dynamic HTML rendering
- [x] Event system (emit, listen, unlisten)
- [x] State management (StateContainer)
- [x] System tray icons with menus
- [x] Application menu bar (macOS)
- [x] `velox dev` CLI command with file watching and beforeDevCommand hooks
- [x] `velox build` CLI command with app bundle creation (macOS)
- [x] `velox init` CLI command for project scaffolding
- [x] Plugin system (VeloxPlugin protocol, lifecycle hooks, command registration)
- [x] Permission system (capabilities, permissions, scopes, window targeting)
- [x] Security configuration (CSP, freezePrototype, assetProtocol, pattern, headers)
- [x] Channel streaming for large data transfers (Channel API, progress events)
- [x] Built-in plugins: Dialog, Clipboard, Notification, Shell, Process, OS Info, Opener
