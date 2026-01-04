// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Navigation Types

/// Represents a navigation request that plugins can validate
public struct NavigationRequest: Sendable {
  /// The URL being navigated to
  public let url: URL

  /// The webview label requesting navigation
  public let webviewLabel: String

  /// Whether this is the initial page load
  public let isInitial: Bool

  public init(url: URL, webviewLabel: String, isInitial: Bool = false) {
    self.url = url
    self.webviewLabel = webviewLabel
    self.isInitial = isInitial
  }
}

/// The result of navigation validation
public enum NavigationDecision: Sendable {
  /// Allow the navigation to proceed
  case allow

  /// Block the navigation
  case deny

  /// Redirect to a different URL
  case redirect(URL)
}

// MARK: - Plugin Context Types

/// Context provided to plugins during setup
public struct PluginSetupContext: @unchecked Sendable {
  /// The state container for registering plugin state
  public let stateContainer: StateContainer

  /// The command registry for registering plugin commands
  public let commandRegistry: CommandRegistry

  /// The event emitter for sending events to webviews
  public let eventEmitter: EventEmitter

  /// The event listener for receiving events from webviews
  public let eventListener: EventListener

  /// App configuration
  public let config: VeloxConfig

  public init(
    stateContainer: StateContainer,
    commandRegistry: CommandRegistry,
    eventEmitter: EventEmitter,
    eventListener: EventListener,
    config: VeloxConfig
  ) {
    self.stateContainer = stateContainer
    self.commandRegistry = commandRegistry
    self.eventEmitter = eventEmitter
    self.eventListener = eventListener
    self.config = config
  }

  /// Register plugin-scoped state
  @discardableResult
  public func manage<T>(plugin pluginName: String, state: T) -> Self {
    stateContainer.manage(plugin: pluginName, state: state)
    return self
  }

  /// Get a command registry scoped to a plugin
  public func commands(for pluginName: String) -> PluginCommandRegistry {
    PluginCommandRegistry(pluginName: pluginName, globalRegistry: commandRegistry)
  }
}

/// Context for webview-ready callbacks
public struct WebviewReadyContext: @unchecked Sendable {
  /// The webview label
  public let label: String

  /// Handle to execute JavaScript and emit events
  public let webview: WebviewHandle

  /// The URL loaded in the webview
  public let url: URL?

  public init(label: String, webview: WebviewHandle, url: URL?) {
    self.label = label
    self.webview = webview
    self.url = url
  }
}

// MARK: - Plugin Protocol

/// Protocol defining a Velox plugin.
///
/// Plugins can extend Velox applications with:
/// - Custom commands
/// - State management
/// - Event listeners
/// - JavaScript injection
/// - Navigation validation
///
/// Example:
/// ```swift
/// final class MyPlugin: VeloxPlugin {
///     let name = "com.example.myplugin"
///
///     func setup(context: PluginSetupContext) throws {
///         context.commands(for: name).register("hello") { ctx in
///             return .ok(["message": "Hello from plugin!"])
///         }
///     }
/// }
/// ```
public protocol VeloxPlugin: AnyObject, Sendable {
  /// Unique identifier for this plugin.
  /// Use reverse domain notation (e.g., "com.example.myplugin").
  var name: String { get }

  /// Called once during app setup, before any windows are created.
  /// Use this to register state, commands, and event listeners.
  ///
  /// - Parameter context: The setup context providing access to app infrastructure.
  /// - Throws: If plugin initialization fails.
  func setup(context: PluginSetupContext) throws

  /// Called when a webview attempts to navigate to a new URL.
  ///
  /// Return `.allow` to permit navigation, `.deny` to block it,
  /// or `.redirect(url)` to redirect to a different URL.
  /// The first plugin to return `.deny` or `.redirect` wins.
  ///
  /// - Parameter request: The navigation request details.
  /// - Returns: The navigation decision.
  func onNavigation(request: NavigationRequest) -> NavigationDecision

  /// Called when a webview has finished loading and is ready.
  /// Use this to inject initialization scripts.
  ///
  /// - Parameter context: The webview ready context.
  /// - Returns: JavaScript code to execute, or nil for none.
  func onWebviewReady(context: WebviewReadyContext) -> String?

  /// Called for core runtime events (window, webview lifecycle events).
  /// This is called before the event is delivered to user handlers.
  ///
  /// - Parameter event: The event description as JSON.
  func onEvent(_ event: String)

  /// Called when the plugin is being unloaded or app is shutting down.
  /// Use this for cleanup.
  func onDrop()
}

// MARK: - Default Implementations

public extension VeloxPlugin {
  func onNavigation(request: NavigationRequest) -> NavigationDecision {
    .allow
  }

  func onWebviewReady(context: WebviewReadyContext) -> String? {
    nil
  }

  func onEvent(_ event: String) {
    // No-op by default
  }

  func onDrop() {
    // No-op by default
  }
}

// MARK: - Plugin Command Registry

/// A command registry scoped to a specific plugin.
/// Commands are automatically prefixed with `plugin:<pluginName>:`.
public final class PluginCommandRegistry: @unchecked Sendable {
  private let pluginName: String
  private let globalRegistry: CommandRegistry

  internal init(pluginName: String, globalRegistry: CommandRegistry) {
    self.pluginName = pluginName
    self.globalRegistry = globalRegistry
  }

  /// The prefix used for this plugin's commands
  public var prefix: String {
    "plugin:\(pluginName):"
  }

  /// Register a command with automatic plugin prefix.
  /// Command will be registered as "plugin:<pluginName>:<commandName>".
  @discardableResult
  public func register(_ name: String, handler: @escaping AnyCommandHandler) -> Self {
    let fullName = "\(prefix)\(name)"
    globalRegistry.register(fullName, handler: handler)
    return self
  }

  /// Register a typed command handler with automatic argument decoding.
  @discardableResult
  public func register<Args: Decodable & Sendable>(
    _ name: String,
    args: Args.Type,
    handler: @escaping @Sendable (Args, CommandContext) -> CommandResult
  ) -> Self {
    let fullName = "\(prefix)\(name)"
    globalRegistry.register(fullName, args: args, handler: handler)
    return self
  }

  /// Register a command with typed args and return value.
  @discardableResult
  public func register<Args: Decodable & Sendable, Result: Encodable & Sendable>(
    _ name: String,
    args: Args.Type,
    returning: Result.Type,
    handler: @escaping @Sendable (Args, CommandContext) throws -> Result
  ) -> Self {
    let fullName = "\(prefix)\(name)"
    globalRegistry.register(fullName, args: args, returning: returning, handler: handler)
    return self
  }

  /// Register a simple command that just needs context.
  @discardableResult
  public func register<Result: Encodable & Sendable>(
    _ name: String,
    returning: Result.Type,
    handler: @escaping @Sendable (CommandContext) throws -> Result
  ) -> Self {
    let fullName = "\(prefix)\(name)"
    globalRegistry.register(fullName, returning: returning, handler: handler)
    return self
  }
}

// MARK: - Plugin State Key

/// Internal key for plugin-scoped state
private struct PluginStateKey: Hashable, Sendable {
  let pluginName: String
  let typeId: ObjectIdentifier

  init<T>(pluginName: String, type: T.Type) {
    self.pluginName = pluginName
    self.typeId = ObjectIdentifier(type)
  }
}

// MARK: - StateContainer Plugin Extensions

public extension StateContainer {
  /// Register plugin-scoped state.
  /// Each plugin can have its own state of any type without conflicting
  /// with other plugins or the main app.
  @discardableResult
  func manage<T>(plugin pluginName: String, state: T) -> Self {
    let key = PluginStateKey(pluginName: pluginName, type: T.self)
    return manageKeyed(key: key, value: state)
  }

  /// Get plugin-scoped state.
  func get<T>(plugin pluginName: String) -> T? {
    let key = PluginStateKey(pluginName: pluginName, type: T.self)
    return getKeyed(key: key)
  }

  /// Get plugin-scoped state, or crash if not registered.
  func require<T>(plugin pluginName: String) -> T {
    guard let state: T = get(plugin: pluginName) else {
      fatalError("Plugin '\(pluginName)' state of type \(T.self) not registered")
    }
    return state
  }
}
