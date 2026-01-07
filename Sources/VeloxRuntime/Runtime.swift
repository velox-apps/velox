import Foundation

/// Errors that can occur during Velox runtime operations.
///
/// These errors indicate failures in core runtime functionality such as
/// window creation, event loop operations, or unsupported platform features.
public enum VeloxRuntimeError: Error, Sendable {
  /// The requested operation is not supported on this platform or runtime.
  case unsupported

  /// A runtime operation failed with a descriptive message.
  ///
  /// - Parameter description: A human-readable description of what went wrong.
  case failed(description: String)
}

/// Controls the behavior of the event loop after processing an event.
///
/// Return one of these values from your event handler to control how the
/// runtime proceeds after handling the current event.
///
/// Example:
/// ```swift
/// runtime.runIteration { event in
///   switch event {
///   case .exitRequested:
///     return .exit  // Stop the event loop
///   default:
///     return .wait  // Wait for next event
///   }
/// }
/// ```
public enum VeloxControlFlow: Int32, Sendable {
  /// Continue immediately to the next iteration without waiting for events.
  /// Use this when you have pending work that needs to be processed.
  case poll = 0

  /// Wait for the next event before continuing.
  /// This is the typical choice for most event handling.
  case wait = 1

  /// Exit the event loop and terminate the application.
  case exit = 2
}

/// A marker protocol for custom user-defined events.
///
/// Implement this protocol to create custom events that can be sent through
/// the event loop proxy and handled in your main event loop.
///
/// Example:
/// ```swift
/// enum MyEvent: VeloxUserEvent {
///   case dataLoaded([String])
///   case backgroundTaskComplete
/// }
/// ```
public protocol VeloxUserEvent: Sendable {}

/// Arguments for initializing a Velox runtime instance.
///
/// Platform-specific initialization parameters are encapsulated here.
/// On Linux, an application identifier is required for D-Bus integration.
///
/// Example:
/// ```swift
/// #if os(Linux)
/// let args = VeloxRuntimeInitArgs(applicationIdentifier: "com.example.myapp")
/// #else
/// let args = VeloxRuntimeInitArgs()
/// #endif
/// let runtime = try MyRuntime.make(args: args)
/// ```
public struct VeloxRuntimeInitArgs: Sendable {
  #if os(Linux)
  /// The D-Bus application identifier (Linux only).
  /// Should be in reverse domain notation (e.g., "com.example.myapp").
  public var applicationIdentifier: String?

  /// Creates runtime initialization arguments for Linux.
  ///
  /// - Parameter applicationIdentifier: The D-Bus application identifier.
  public init(applicationIdentifier: String? = nil) {
    self.applicationIdentifier = applicationIdentifier
  }
  #else
  /// Creates runtime initialization arguments.
  public init() {}
  #endif
}

/// A thread-safe proxy for sending events to the main event loop.
///
/// Use this proxy to send custom events from background threads or async
/// contexts to be processed in the main event loop.
///
/// Example:
/// ```swift
/// let proxy = try runtime.createProxy()
/// Task {
///   // Background work...
///   try proxy.send(event: .dataLoaded(results))
/// }
/// ```
public protocol VeloxEventLoopProxy: AnyObject {
  /// The type of user-defined events this proxy can send.
  associatedtype Event: VeloxUserEvent

  /// Sends an event to the main event loop.
  ///
  /// This method is thread-safe and can be called from any thread.
  ///
  /// - Parameter event: The event to send to the main loop.
  /// - Throws: ``VeloxRuntimeError`` if the event cannot be delivered.
  func send(event: Event) throws
}

/// A pending window configuration waiting to be created.
///
/// Use this struct to define a window before actually creating it with the runtime.
/// The window is created when passed to ``VeloxRuntime/createWindow(pending:)``.
///
/// - Note: The label must be unique across all windows in the application.
public struct VeloxPendingWindow<Event: VeloxUserEvent>: Sendable {
  /// The unique identifier for this window.
  public let label: String

  /// Creates a pending window configuration.
  ///
  /// - Parameter label: A unique identifier for the window.
  public init(label: String) {
    self.label = label
  }
}

/// A pending webview configuration waiting to be created.
///
/// Use this struct to define a webview before creating it within a window.
/// The webview is created when passed to ``VeloxRuntime/createWebview(window:pending:)``.
///
/// - Note: The label must be unique across all webviews in the application.
public struct VeloxPendingWebview<Event: VeloxUserEvent>: Sendable {
  /// The unique identifier for this webview.
  public let label: String

  /// Creates a pending webview configuration.
  ///
  /// - Parameter label: A unique identifier for the webview.
  public init(label: String) {
    self.label = label
  }
}

/// A dispatcher for window-related operations.
///
/// Conforming types provide a way to interact with native windows,
/// including event handling and identifier management.
public protocol VeloxWindowDispatcher: AnyObject {
  /// The type of user-defined events this dispatcher handles.
  associatedtype Event: VeloxUserEvent

  /// The type used to uniquely identify windows.
  associatedtype Identifier: Hashable & Sendable
}

/// A dispatcher for webview-related operations.
///
/// Conforming types provide a way to interact with webviews,
/// including JavaScript evaluation and navigation handling.
public protocol VeloxWebviewDispatcher: AnyObject {
  /// The type of user-defined events this dispatcher handles.
  associatedtype Event: VeloxUserEvent

  /// The type used to uniquely identify webviews.
  associatedtype Identifier: Hashable & Sendable
}

/// A window that has been created but not yet attached to the event loop.
///
/// Detached windows are returned from window creation methods and contain
/// all the necessary dispatchers for interacting with the window and its webview.
///
/// - Note: The window becomes fully functional once the runtime's event loop starts.
public struct VeloxDetachedWindow<Event: VeloxUserEvent, WindowDispatcher: VeloxWindowDispatcher, WebviewDispatcher: VeloxWebviewDispatcher> where WindowDispatcher.Event == Event, WebviewDispatcher.Event == Event, WindowDispatcher.Identifier == WebviewDispatcher.Identifier {
  /// The unique identifier assigned by the underlying window system.
  public let id: WindowDispatcher.Identifier

  /// The user-defined label for this window.
  public let label: String

  /// The dispatcher for window operations.
  public let dispatcher: WindowDispatcher

  /// The dispatcher for webview operations, if the window contains a webview.
  public let webview: WebviewDispatcher?

  /// Creates a detached window with the specified components.
  ///
  /// - Parameters:
  ///   - id: The system-assigned window identifier.
  ///   - label: The user-defined window label.
  ///   - dispatcher: The window operations dispatcher.
  ///   - webview: The webview dispatcher, if present.
  public init(
    id: WindowDispatcher.Identifier,
    label: String,
    dispatcher: WindowDispatcher,
    webview: WebviewDispatcher? = nil
  ) {
    self.id = id
    self.label = label
    self.dispatcher = dispatcher
    self.webview = webview
  }
}

extension VeloxDetachedWindow: @unchecked Sendable {}

/// A handle to the runtime that can be used from background threads.
///
/// The runtime handle provides thread-safe access to runtime operations
/// such as creating windows, webviews, and event loop proxies.
///
/// - Important: Use this handle for operations from background threads.
///   The main ``VeloxRuntime`` should only be used on the main thread.
public protocol VeloxRuntimeHandle: AnyObject {
  /// The type of user-defined events this runtime handles.
  associatedtype Event: VeloxUserEvent

  /// The window dispatcher type for this runtime.
  associatedtype WindowDispatcher: VeloxWindowDispatcher where WindowDispatcher.Event == Event

  /// The webview dispatcher type for this runtime.
  associatedtype WebviewDispatcher: VeloxWebviewDispatcher where WebviewDispatcher.Event == Event, WebviewDispatcher.Identifier == WindowDispatcher.Identifier

  /// The event loop proxy type for this runtime.
  associatedtype EventLoopProxyType: VeloxEventLoopProxy where EventLoopProxyType.Event == Event

  /// Creates a new event loop proxy for sending events from background threads.
  ///
  /// - Returns: A thread-safe proxy for sending events to the main loop.
  /// - Throws: ``VeloxRuntimeError`` if proxy creation fails.
  func createProxy() throws -> EventLoopProxyType

  /// Requests the application to exit with the specified exit code.
  ///
  /// - Parameter code: The exit code to return to the operating system.
  /// - Throws: ``VeloxRuntimeError`` if the exit request cannot be processed.
  func requestExit(code: Int32) throws

  /// Creates a new window from a pending configuration.
  ///
  /// - Parameter pending: The pending window configuration.
  /// - Returns: A detached window ready to be used.
  /// - Throws: ``VeloxRuntimeError`` if window creation fails.
  func createWindow(
    pending: VeloxPendingWindow<Event>
  ) throws -> VeloxDetachedWindow<Event, WindowDispatcher, WebviewDispatcher>

  /// Creates a new webview within an existing window.
  ///
  /// - Parameters:
  ///   - window: The identifier of the window to host the webview.
  ///   - pending: The pending webview configuration.
  /// - Returns: A dispatcher for the created webview.
  /// - Throws: ``VeloxRuntimeError`` if webview creation fails.
  func createWebview(
    window: WindowDispatcher.Identifier,
    pending: VeloxPendingWebview<Event>
  ) throws -> WebviewDispatcher
}

/// Events delivered by the runtime's event loop.
///
/// These events represent lifecycle events, window/webview events, and
/// custom user-defined events that your application can handle.
///
/// Example:
/// ```swift
/// runtime.runIteration { event in
///   switch event {
///   case .ready:
///     print("App is ready")
///   case .userEvent(let myEvent):
///     handleMyEvent(myEvent)
///   case .exitRequested(let code):
///     return .exit
///   default:
///     break
///   }
///   return .wait
/// }
/// ```
public enum VeloxRunEvent<Event: VeloxUserEvent>: Sendable {
  /// The application has finished initialization and is ready.
  case ready

  /// The application is about to exit.
  case exit

  /// An exit was requested, optionally with an exit code.
  case exitRequested(code: Int32?)

  /// An event occurred on a window.
  ///
  /// - Parameter label: The label of the window that generated the event.
  case windowEvent(label: String)

  /// An event occurred on a webview.
  ///
  /// - Parameter label: The label of the webview that generated the event.
  case webviewEvent(label: String)

  /// A custom user-defined event was received.
  ///
  /// - Parameter event: The user event sent via the event loop proxy.
  case userEvent(Event)

  /// A raw event description for debugging or unhandled events.
  ///
  /// - Parameter description: A string describing the event.
  case raw(description: String)
}

/// The main runtime protocol for Velox applications.
///
/// A Velox runtime manages the application's event loop, windows, and webviews.
/// It provides the foundation for building cross-platform desktop applications.
///
/// Example:
/// ```swift
/// let runtime = try WryRuntime.make(args: VeloxRuntimeInitArgs())
/// let window = try runtime.createWindow(pending: VeloxPendingWindow(label: "main"))
///
/// while true {
///   var shouldExit = false
///   runtime.runIteration { event in
///     if case .exitRequested = event {
///       shouldExit = true
///       return .exit
///     }
///     return .wait
///   }
///   if shouldExit { break }
/// }
/// ```
///
/// - Important: Most runtime methods must be called on the main thread.
///   Use the handle or event loop proxy for background thread access.
public protocol VeloxRuntime: AnyObject {
  /// The type of user-defined events this runtime handles.
  associatedtype Event: VeloxUserEvent

  /// The runtime handle type for thread-safe access.
  associatedtype Handle: VeloxRuntimeHandle where Handle.Event == Event

  /// The event loop proxy type for this runtime.
  associatedtype EventLoopProxyType: VeloxEventLoopProxy where EventLoopProxyType.Event == Event

  /// Creates a new runtime instance with the specified initialization arguments.
  ///
  /// - Parameter args: Platform-specific initialization arguments.
  /// - Returns: A configured runtime ready to use.
  /// - Throws: ``VeloxRuntimeError`` if runtime creation fails.
  static func make(args: VeloxRuntimeInitArgs) throws -> Self

  /// Gets a thread-safe handle to this runtime.
  ///
  /// Use the handle to perform runtime operations from background threads.
  ///
  /// - Returns: A handle that can be safely used across threads.
  func handle() -> Handle

  /// Creates a new event loop proxy for sending events from background threads.
  ///
  /// - Returns: A thread-safe proxy for sending events to the main loop.
  /// - Throws: ``VeloxRuntimeError`` if proxy creation fails.
  func createProxy() throws -> EventLoopProxyType

  /// Creates a new window from a pending configuration.
  ///
  /// - Parameter pending: The pending window configuration.
  /// - Returns: A detached window ready to be used.
  /// - Throws: ``VeloxRuntimeError`` if window creation fails.
  func createWindow(
    pending: VeloxPendingWindow<Event>
  ) throws -> VeloxDetachedWindow<Event, Handle.WindowDispatcher, Handle.WebviewDispatcher>

  /// Creates a new webview within an existing window.
  ///
  /// - Parameters:
  ///   - window: The identifier of the window to host the webview.
  ///   - pending: The pending webview configuration.
  /// - Returns: A dispatcher for the created webview.
  /// - Throws: ``VeloxRuntimeError`` if webview creation fails.
  func createWebview(
    window: Handle.WindowDispatcher.Identifier,
    pending: VeloxPendingWebview<Event>
  ) throws -> Handle.WebviewDispatcher

  /// Runs a single iteration of the event loop.
  ///
  /// Call this in a loop to process events. The handler is called for each
  /// event and should return a ``VeloxControlFlow`` value to control the loop.
  ///
  /// - Parameter handler: A closure that handles each event and returns a control flow value.
  func runIteration(handler: @escaping @Sendable (VeloxRunEvent<Event>) -> VeloxControlFlow)
}
