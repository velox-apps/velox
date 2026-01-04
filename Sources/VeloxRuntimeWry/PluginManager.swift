// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - Plugin Manager

/// Manages plugin registration and lifecycle.
///
/// The `PluginManager` coordinates:
/// - Plugin registration (before app build)
/// - Plugin setup (during app build)
/// - Navigation validation (during webview navigation)
/// - Webview ready notifications (after webview load)
/// - Event dispatch (during event loop)
/// - Plugin cleanup (on app shutdown)
public final class PluginManager: @unchecked Sendable {
  /// Registered plugins in order of registration
  private var plugins: [VeloxPlugin] = []

  /// Lock for thread safety
  private let lock = NSLock()

  /// Whether setup has been called
  private var isSetup = false

  public init() {}

  // MARK: - Registration

  /// Register a plugin. Must be called before setup.
  ///
  /// - Parameter plugin: The plugin to register.
  /// - Returns: Self for chaining.
  /// - Warning: Crashes if called after setup or if plugin name is duplicate.
  @discardableResult
  public func register(_ plugin: VeloxPlugin) -> Self {
    lock.lock()
    defer { lock.unlock() }

    guard !isSetup else {
      fatalError("Cannot register plugins after setup has been called")
    }

    // Check for duplicate names
    if plugins.contains(where: { $0.name == plugin.name }) {
      fatalError("Plugin with name '\(plugin.name)' is already registered")
    }

    plugins.append(plugin)
    return self
  }

  /// Get a registered plugin by name.
  ///
  /// - Parameter name: The plugin name.
  /// - Returns: The plugin if found and castable to T, nil otherwise.
  public func plugin<T: VeloxPlugin>(named name: String) -> T? {
    lock.lock()
    defer { lock.unlock() }
    return plugins.first { $0.name == name } as? T
  }

  /// Get a registered plugin by type.
  ///
  /// - Returns: The first plugin of type T, nil if not found.
  public func plugin<T: VeloxPlugin>() -> T? {
    lock.lock()
    defer { lock.unlock() }
    return plugins.first { $0 is T } as? T
  }

  /// Get all registered plugin names.
  public var pluginNames: [String] {
    lock.lock()
    defer { lock.unlock() }
    return plugins.map { $0.name }
  }

  /// Check if any plugins are registered.
  public var hasPlugins: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !plugins.isEmpty
  }

  // MARK: - Lifecycle

  /// Initialize all plugins. Called by VeloxAppBuilder during build.
  ///
  /// - Parameter context: The setup context providing access to app infrastructure.
  /// - Throws: If any plugin's setup method throws.
  internal func setup(context: PluginSetupContext) throws {
    lock.lock()
    isSetup = true
    let pluginsCopy = plugins
    lock.unlock()

    for plugin in pluginsCopy {
      try plugin.setup(context: context)
    }
  }

  /// Validate a navigation request across all plugins.
  /// Returns the final decision (first deny/redirect wins).
  ///
  /// - Parameter request: The navigation request to validate.
  /// - Returns: The navigation decision.
  internal func validateNavigation(_ request: NavigationRequest) -> NavigationDecision {
    lock.lock()
    let pluginsCopy = plugins
    lock.unlock()

    for plugin in pluginsCopy {
      let decision = plugin.onNavigation(request: request)
      switch decision {
      case .allow:
        continue
      case .deny, .redirect:
        return decision
      }
    }
    return .allow
  }

  /// Notify all plugins that a webview is ready.
  /// Returns combined JavaScript from all plugins.
  ///
  /// - Parameter context: The webview ready context.
  /// - Returns: Combined JavaScript initialization code.
  internal func webviewReady(context: WebviewReadyContext) -> String {
    lock.lock()
    let pluginsCopy = plugins
    lock.unlock()

    var scripts: [String] = []
    for plugin in pluginsCopy {
      if let script = plugin.onWebviewReady(context: context) {
        scripts.append("// Plugin: \(plugin.name)\n\(script)")
      }
    }

    guard !scripts.isEmpty else { return "" }

    return """
      (function() {
      \(scripts.joined(separator: "\n\n"))
      })();
      """
  }

  /// Dispatch an event to all plugins.
  ///
  /// - Parameter event: The event description as JSON.
  internal func dispatchEvent(_ event: String) {
    lock.lock()
    let pluginsCopy = plugins
    lock.unlock()

    for plugin in pluginsCopy {
      plugin.onEvent(event)
    }
  }

  /// Cleanup all plugins. Called on app shutdown.
  /// Plugins are cleaned up in reverse registration order.
  internal func shutdown() {
    lock.lock()
    let pluginsCopy = Array(plugins.reversed())
    plugins.removeAll()
    isSetup = false
    lock.unlock()

    for plugin in pluginsCopy {
      plugin.onDrop()
    }
  }

  deinit {
    shutdown()
  }
}
