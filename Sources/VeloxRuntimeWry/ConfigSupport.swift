// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - EventLoop Extensions for Config

public extension VeloxRuntimeWry.EventLoop {
  /// Create a window from a WindowConfig
  func makeWindow(from config: WindowConfig) -> VeloxRuntimeWry.Window? {
    let windowConfig = VeloxRuntimeWry.WindowConfiguration(
      width: UInt32(config.effectiveWidth),
      height: UInt32(config.effectiveHeight),
      title: config.effectiveTitle
    )

    guard let window = makeWindow(configuration: windowConfig) else {
      return nil
    }

    // Apply additional configuration
    applyWindowConfig(config, to: window)

    return window
  }

  /// Apply a full VeloxConfig, creating all windows marked with create: true
  /// Returns a dictionary mapping window labels to created windows
  @discardableResult
  func applyConfig(_ config: VeloxConfig) -> [String: VeloxRuntimeWry.Window] {
    var windows: [String: VeloxRuntimeWry.Window] = [:]

    // Apply macOS-specific settings
    #if os(macOS)
    if let macOS = config.app.macOS {
      if let policy = macOS.activationPolicy {
        switch policy {
        case .regular:
          setActivationPolicy(.regular)
        case .accessory:
          setActivationPolicy(.accessory)
        case .prohibited:
          setActivationPolicy(.prohibited)
        }
      }
    }
    #endif

    // Create windows marked with create: true
    for windowConfig in config.app.windows where windowConfig.shouldCreate {
      if let window = makeWindow(from: windowConfig) {
        windows[windowConfig.label] = window
      }
    }

    return windows
  }

  /// Apply window-specific configuration settings
  private func applyWindowConfig(_ config: WindowConfig, to window: VeloxRuntimeWry.Window) {
    // Position
    if let x = config.x, let y = config.y {
      window.setPosition(x: x, y: y)
    }

    // Size constraints
    if let minWidth = config.minWidth, let minHeight = config.minHeight {
      window.setMinimumSize(width: minWidth, height: minHeight)
    }
    if let maxWidth = config.maxWidth, let maxHeight = config.maxHeight {
      window.setMaximumSize(width: maxWidth, height: maxHeight)
    }

    // Window state
    if let resizable = config.resizable {
      window.setResizable(resizable)
    }
    if let decorations = config.decorations {
      window.setDecorations(decorations)
    }
    if let maximized = config.maximized, maximized {
      window.setMaximized(true)
    }
    if let minimized = config.minimized, minimized {
      window.setMinimized(true)
    }
    if let fullscreen = config.fullscreen, fullscreen {
      window.setFullscreen(true)
    }

    // Always on top/bottom
    if let alwaysOnTop = config.alwaysOnTop {
      window.setAlwaysOnTop(alwaysOnTop)
    }
    if let alwaysOnBottom = config.alwaysOnBottom {
      window.setAlwaysOnBottom(alwaysOnBottom)
    }

    // Focusable
    if let focusable = config.focusable {
      window.setFocusable(focusable)
    }

    // Buttons
    if let maximizable = config.maximizable {
      window.setMaximizable(maximizable)
    }
    if let minimizable = config.minimizable {
      window.setMinimizable(minimizable)
    }
    if let closable = config.closable {
      window.setClosable(closable)
    }

    // Visibility options
    if let skipTaskbar = config.skipTaskbar {
      window.setSkipTaskbar(skipTaskbar)
    }
    if let contentProtected = config.contentProtected {
      window.setContentProtected(contentProtected)
    }
    if let visibleOnAllWorkspaces = config.visibleOnAllWorkspaces {
      window.setVisibleOnAllWorkspaces(visibleOnAllWorkspaces)
    }

    // Theme
    if let theme = config.theme {
      switch theme {
      case .light:
        window.setTheme(.light)
      case .dark:
        window.setTheme(.dark)
      case .system:
        // System theme - don't set, let OS decide
        break
      }
    }

    // Background color
    if let colorHex = config.backgroundColor {
      if let color = parseColor(colorHex) {
        window.setBackgroundColor(color)
      }
    }

    // Visibility and focus (apply last)
    if let visible = config.visible, visible {
      window.setVisible(true)
    }
    if let focus = config.focus, focus {
      window.focus()
    }
  }

  /// Parse a hex color string like "#RRGGBB" or "#RRGGBBAA"
  private func parseColor(_ hex: String) -> VeloxRuntimeWry.Window.Color? {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hexString.hasPrefix("#") {
      hexString.removeFirst()
    }

    guard hexString.count == 6 || hexString.count == 8 else {
      return nil
    }

    var rgb: UInt64 = 0
    guard Scanner(string: hexString).scanHexInt64(&rgb) else {
      return nil
    }

    if hexString.count == 6 {
      return VeloxRuntimeWry.Window.Color(
        red: Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >> 8) & 0xFF) / 255.0,
        blue: Double(rgb & 0xFF) / 255.0,
        alpha: 1.0
      )
    } else {
      return VeloxRuntimeWry.Window.Color(
        red: Double((rgb >> 24) & 0xFF) / 255.0,
        green: Double((rgb >> 16) & 0xFF) / 255.0,
        blue: Double((rgb >> 8) & 0xFF) / 255.0,
        alpha: Double(rgb & 0xFF) / 255.0
      )
    }
  }
}

// MARK: - Window Extensions for Config

public extension VeloxRuntimeWry.Window {
  /// Create a webview from a WindowConfig
  func makeWebview(
    from config: WindowConfig,
    customProtocols: [VeloxRuntimeWry.CustomProtocol] = []
  ) -> VeloxRuntimeWry.Webview? {
    let devtoolsEnabled = config.devtools ?? VeloxRuntimeWry.defaultDevtoolsEnabled
    let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
      url: config.url ?? "",
      customProtocols: customProtocols,
      devtools: devtoolsEnabled,
      isChild: config.isChild ?? false,
      x: config.x ?? 0,
      y: config.y ?? 0,
      width: config.effectiveWidth,
      height: config.effectiveHeight
    )

    return makeWebview(configuration: webviewConfig)
  }
}

// MARK: - App Builder

/// A builder for creating Velox applications from configuration.
///
/// `VeloxAppBuilder` provides a fluent API for configuring and building
/// desktop applications. It handles:
/// - Loading configuration from `velox.json`
/// - Plugin registration and lifecycle
/// - Custom protocol handlers
/// - Window and webview creation
/// - Security headers and CSP
///
/// Example:
/// ```swift
/// try VeloxAppBuilder()
///   .plugin(ClipboardPlugin())
///   .commands { registry in
///     registry.register("greet") { _ in .ok("Hello!") }
///   }
///   .run()
/// ```
///
/// Or with a custom event loop:
/// ```swift
/// let builder = try VeloxAppBuilder()
/// let eventLoop = VeloxRuntimeWry.EventLoop()!
/// let windows = builder.build(eventLoop: eventLoop)
/// // Custom event handling...
/// eventLoop.run()
/// ```
public final class VeloxAppBuilder {
  /// The app configuration loaded from `velox.json`.
  public let config: VeloxConfig

  private var protocolHandlers: [String: VeloxRuntimeWry.CustomProtocol] = [:]
  private var windowSetupHandlers: [String: (VeloxRuntimeWry.Window, VeloxRuntimeWry.Webview?) -> Void] = [:]

  /// Event manager for frontend-backend communication.
  public let eventManager: VeloxEventManager

  /// State container for managed application state.
  ///
  /// Use ``manage(_:)`` to add state and ``state()`` to retrieve it.
  public let stateContainer: StateContainer

  /// Command registry for IPC commands.
  ///
  /// Use ``commands(scheme:_:)`` to register commands.
  public let commandRegistry: CommandRegistry

  /// Permission manager for access control.
  ///
  /// Configured automatically from the security section of `velox.json`.
  public let permissionManager: PermissionManager

  /// Initialize with a VeloxConfig
  public init(
    config: VeloxConfig,
    eventManager: VeloxEventManager = VeloxEventManager(),
    stateContainer: StateContainer = StateContainer(),
    commandRegistry: CommandRegistry = CommandRegistry(),
    permissionManager: PermissionManager = PermissionManager()
  ) {
    self.config = config
    self.eventManager = eventManager
    self.stateContainer = stateContainer
    self.commandRegistry = commandRegistry
    self.permissionManager = permissionManager

    // Configure permission manager from security config
    if let security = config.app.security {
      permissionManager.configure(
        capabilities: security.capabilities,
        permissions: security.permissions,
        defaultAppCommandPolicy: security.defaultAppCommandPolicy,
        defaultPluginCommandPolicy: security.defaultPluginCommandPolicy
      )
    }
  }

  /// Load config from the default location (velox.json in current directory)
  public convenience init() throws {
    let config = try VeloxConfig.load()
    self.init(config: config)
  }

  /// Load config from a specific directory
  public convenience init(directory: URL) throws {
    let config = try VeloxConfig.load(from: directory)
    self.init(config: config)
  }

  /// Register managed state
  @discardableResult
  public func manage<T>(_ state: T) -> Self {
    stateContainer.manage(state)
    return self
  }

  /// Get managed state of type T
  public func state<T>() -> T? {
    stateContainer.get()
  }

  /// Get managed state of type T, or crash if not registered
  public func requireState<T>() -> T {
    stateContainer.require()
  }

  /// Register a custom protocol handler
  @discardableResult
  public func registerProtocol(
    _ scheme: String,
    handler: @escaping @Sendable (VeloxRuntimeWry.CustomProtocol.Request) -> VeloxRuntimeWry.CustomProtocol.Response?
  ) -> Self {
    protocolHandlers[scheme] = VeloxRuntimeWry.CustomProtocol(scheme: scheme, handler: handler)
    return self
  }

  /// Register a setup handler for a specific window
  @discardableResult
  public func onWindowCreated(
    _ label: String,
    handler: @escaping (VeloxRuntimeWry.Window, VeloxRuntimeWry.Webview?) -> Void
  ) -> Self {
    windowSetupHandlers[label] = handler
    return self
  }

  /// Build the app, creating all configured windows and webviews
  ///
  /// This method:
  /// 1. Initializes all registered plugins
  /// 2. Creates windows and webviews as configured
  /// 3. Notifies plugins when webviews are ready
  ///
  /// - Parameter eventLoop: The event loop to create windows in.
  /// - Returns: A dictionary mapping window labels to window/webview tuples.
  public func build(
    eventLoop: VeloxRuntimeWry.EventLoop
  ) -> [String: (window: VeloxRuntimeWry.Window, webview: VeloxRuntimeWry.Webview?)] {
    var result: [String: (window: VeloxRuntimeWry.Window, webview: VeloxRuntimeWry.Webview?)] = [:]

    // Setup plugins if any are registered
    if pluginManager.hasPlugins {
      let setupContext = PluginSetupContext(
        stateContainer: stateContainer,
        commandRegistry: commandRegistry,
        eventEmitter: eventManager,
        eventListener: eventManager,
        config: config
      )

      do {
        try pluginManager.setup(context: setupContext)
      } catch {
        print("[VeloxAppBuilder] Plugin setup failed: \(error)")
      }
    }

    // Apply macOS settings
    #if os(macOS)
    if let macOS = config.app.macOS {
      if let policy = macOS.activationPolicy {
        switch policy {
        case .regular: eventLoop.setActivationPolicy(.regular)
        case .accessory: eventLoop.setActivationPolicy(.accessory)
        case .prohibited: eventLoop.setActivationPolicy(.prohibited)
        }
      }
    }
    #endif

    // Create windows
    for windowConfig in config.app.windows where windowConfig.shouldCreate {
      guard let window = eventLoop.makeWindow(from: windowConfig) else {
        print("[VeloxAppBuilder] Failed to create window: \(windowConfig.label)")
        continue
      }

      eventManager.register(window: window, label: windowConfig.label)

      // Create webview if URL is specified
      var webview: VeloxRuntimeWry.Webview?
      if windowConfig.url != nil {
        // Collect protocols for this window
        var protocols: [VeloxRuntimeWry.CustomProtocol] = []
        if let schemeNames = windowConfig.customProtocols {
          for name in schemeNames {
            if let proto = protocolHandlers[name] {
              protocols.append(proto)
            }
          }
        }
        // Also add any protocol matching common schemes
        for (scheme, proto) in protocolHandlers {
          if windowConfig.url?.hasPrefix("\(scheme)://") == true && !protocols.contains(where: { $0.scheme == scheme }) {
            protocols.append(proto)
          }
        }

        webview = window.makeWebview(from: windowConfig, customProtocols: protocols)
        webview?.show()

        // Register webview with event manager
        if let wv = webview {
          eventManager.register(webview: wv, label: windowConfig.label)

          // Inject security initialization scripts (must run first)
          let securityScript = SecurityScriptGenerator.generateInitScript(config: config.app.security)
          if !securityScript.isEmpty {
            wv.evaluate(script: securityScript)
          }

          // Notify plugins that webview is ready
          if pluginManager.hasPlugins {
            let webviewHandle = eventManager.getWebviewHandle(windowConfig.label)
            if let handle = webviewHandle {
              let readyContext = WebviewReadyContext(
                label: windowConfig.label,
                webview: handle,
                url: URL(string: windowConfig.url ?? "")
              )

              let initScript = pluginManager.webviewReady(context: readyContext)
              if !initScript.isEmpty {
                wv.evaluate(script: initScript)
              }
            }
          }
        }
      }

      // Notify plugins that a window was created
      if pluginManager.hasPlugins {
        pluginManager.dispatchEvent("{\"type\":\"windowCreated\",\"label\":\"\(windowConfig.label)\"}")
      }

      // Apply visibility
      if windowConfig.visible ?? true {
        window.setVisible(true)
      }
      if windowConfig.focus ?? false {
        window.focus()
      }

      // Call setup handler
      if let handler = windowSetupHandlers[windowConfig.label] {
        handler(window, webview)
      }

      result[windowConfig.label] = (window, webview)
    }

    return result
  }

  /// Create an event loop, build the configured windows, and run until exit.
  public func run(
    handler: (@Sendable (VeloxRuntimeWry.Event) -> VeloxRuntimeWry.ControlFlow)? = nil
  ) throws {
    guard Thread.isMainThread else {
      throw VeloxRuntimeError.failed(description: "VeloxAppBuilder.run must be called on the main thread")
    }
    guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
      throw VeloxRuntimeError.unsupported
    }

    let windows = build(eventLoop: eventLoop)
    let pm = pluginManager
    // Keep window/webview handles alive for the duration of the run loop.
    withExtendedLifetime(windows) {
      #if os(macOS)
      eventLoop.showApplication()
      #endif

      // Wrap the user handler to also dispatch events to plugins.
      let wrappedHandler: @Sendable (VeloxRuntimeWry.Event) -> VeloxRuntimeWry.ControlFlow = { event in
        if pm.hasPlugins {
          if let json = Self.eventToJSON(event) {
            pm.dispatchEvent(json)
          }
        }
        return handler?(event) ?? Self.defaultControlFlow(event)
      }
      eventLoop.run(wrappedHandler)
    }
  }

  // MARK: - Event Helpers

  /// Default control flow for events when no user handler is provided.
  private static func defaultControlFlow(_ event: VeloxRuntimeWry.Event) -> VeloxRuntimeWry.ControlFlow {
    switch event {
    case .windowCloseRequested, .userExit, .exitRequested:
      return .exit
    default:
      return .wait
    }
  }

  /// Converts a VeloxRuntimeWry.Event to a JSON string for plugin dispatch.
  /// Returns nil for events that don't need plugin notification.
  private static func eventToJSON(_ event: VeloxRuntimeWry.Event) -> String? {
    switch event {
    case .windowResized(let windowId, let size):
      return "{\"type\":\"windowResized\",\"windowId\":\"\(windowId)\",\"width\":\(size.width),\"height\":\(size.height)}"
    case .windowMoved(let windowId, let position):
      return "{\"type\":\"windowMoved\",\"windowId\":\"\(windowId)\",\"x\":\(position.x),\"y\":\(position.y)}"
    case .windowCloseRequested(let windowId):
      return "{\"type\":\"windowCloseRequested\",\"windowId\":\"\(windowId)\"}"
    case .windowDestroyed(let windowId):
      return "{\"type\":\"windowDestroyed\",\"windowId\":\"\(windowId)\"}"
    case .windowFocused(let windowId, let isFocused):
      return "{\"type\":\"windowFocused\",\"windowId\":\"\(windowId)\",\"isFocused\":\(isFocused)}"
    case .reopen(let hasVisibleWindows):
      return "{\"type\":\"reopen\",\"hasVisibleWindows\":\(hasVisibleWindows)}"
    case .userExit:
      return "{\"type\":\"userExit\"}"
    default:
      return nil
    }
  }

  /// Create an app protocol handler that serves static content with security headers
  ///
  /// This method creates a protocol handler for serving static HTML content with
  /// proper security headers (CSP, custom headers from config).
  ///
  /// - Parameters:
  ///   - scheme: The protocol scheme (default: "app")
  ///   - contentProvider: A closure that provides the HTML content for a given path
  /// - Returns: Self for chaining
  @discardableResult
  public func registerAppProtocol(
    scheme: String = "app",
    contentProvider: @escaping @Sendable (String) -> String?
  ) -> Self {
    let security = config.app.security

    return registerProtocol(scheme) { request in
      guard let url = URL(string: request.url) else {
        return nil
      }

      let path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path

      guard let content = contentProvider(path) else {
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 404,
          headers: ["Content-Type": "text/plain"],
          mimeType: "text/plain",
          body: Data("Not Found".utf8)
        )
      }

      // Build headers
      var headers: [String: String] = [
        "Content-Type": "text/html; charset=utf-8"
      ]

      // Add CSP header if configured
      if let cspConfig = security?.csp {
        let cspValue = cspConfig.buildHeaderValue()
        headers["Content-Security-Policy"] = cspValue
      }

      // Add custom headers from security config
      if let customHeaders = security?.headers {
        for (key, value) in customHeaders {
          headers[key] = value
        }
      }

      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 200,
        headers: headers,
        mimeType: "text/html",
        body: Data(content.utf8)
      )
    }
  }

  /// Create an asset protocol handler that serves files with security validation
  ///
  /// This method creates a protocol handler for serving local files with
  /// path validation against the configured asset scope.
  ///
  /// - Parameter scheme: The protocol scheme (default: "asset")
  /// - Returns: Self for chaining
  @discardableResult
  public func registerAssetProtocol(scheme: String = "asset") -> Self {
    let security = config.app.security
    let assetConfig = security?.assetProtocol

    // Check if asset protocol is enabled
    guard assetConfig?.isEnabled == true else {
      // Return a handler that always returns forbidden
      return registerProtocol(scheme) { _ in
        VeloxRuntimeWry.CustomProtocol.Response(
          status: 403,
          headers: ["Content-Type": "text/plain"],
          mimeType: "text/plain",
          body: Data("Asset protocol is not enabled".utf8)
        )
      }
    }

    let validator = AssetPathValidator(scope: assetConfig?.scope ?? [])

    return registerProtocol(scheme) { request in
      guard let url = URL(string: request.url) else {
        return nil
      }

      // Get the file path from the URL
      var filePath = url.path
      if filePath.hasPrefix("/") {
        filePath = String(filePath.dropFirst())
      }

      // URL decode the path
      filePath = filePath.removingPercentEncoding ?? filePath

      // Validate against scope
      guard validator.isAllowed(filePath) else {
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 403,
          headers: ["Content-Type": "text/plain"],
          mimeType: "text/plain",
          body: Data("Access denied: path not in scope".utf8)
        )
      }

      // Read the file
      guard let data = FileManager.default.contents(atPath: filePath) else {
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 404,
          headers: ["Content-Type": "text/plain"],
          mimeType: "text/plain",
          body: Data("File not found".utf8)
        )
      }

      // Determine MIME type
      let mimeType = Self.mimeType(for: filePath)

      // Build headers
      var headers: [String: String] = [
        "Content-Type": mimeType
      ]

      // Add custom headers from security config
      if let customHeaders = security?.headers {
        for (key, value) in customHeaders {
          headers[key] = value
        }
      }

      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 200,
        headers: headers,
        mimeType: mimeType,
        body: data
      )
    }
  }

  /// Determine MIME type from file extension
  private static func mimeType(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js", "mjs": return "application/javascript"
    case "json": return "application/json"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "webp": return "image/webp"
    case "ico": return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "otf": return "font/otf"
    case "mp3": return "audio/mpeg"
    case "mp4": return "video/mp4"
    case "webm": return "video/webm"
    case "wav": return "audio/wav"
    case "ogg": return "audio/ogg"
    case "pdf": return "application/pdf"
    case "xml": return "application/xml"
    case "txt": return "text/plain"
    case "wasm": return "application/wasm"
    default: return "application/octet-stream"
    }
  }
}
