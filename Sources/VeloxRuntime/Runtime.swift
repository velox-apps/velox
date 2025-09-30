import Foundation

public enum VeloxRuntimeError: Error, Sendable {
  case unsupported
  case failed(description: String)
}

public enum VeloxControlFlow: Int32, Sendable {
  case poll = 0
  case wait = 1
  case exit = 2
}

public protocol VeloxUserEvent: Sendable {}

public struct VeloxRuntimeInitArgs: Sendable {
  #if os(Linux)
  public var applicationIdentifier: String?
  public init(applicationIdentifier: String? = nil) {
    self.applicationIdentifier = applicationIdentifier
  }
  #else
  public init() {}
  #endif
}

public protocol VeloxEventLoopProxy: AnyObject {
  associatedtype Event: VeloxUserEvent
  func send(event: Event) throws
}

public struct VeloxPendingWindow<Event: VeloxUserEvent>: Sendable {
  public let label: String

  public init(label: String) {
    self.label = label
  }
}

public struct VeloxPendingWebview<Event: VeloxUserEvent>: Sendable {
  public let label: String

  public init(label: String) {
    self.label = label
  }
}

public protocol VeloxWindowDispatcher: AnyObject {
  associatedtype Event: VeloxUserEvent
  associatedtype Identifier: Hashable & Sendable
}

public protocol VeloxWebviewDispatcher: AnyObject {
  associatedtype Event: VeloxUserEvent
  associatedtype Identifier: Hashable & Sendable
}

public struct VeloxDetachedWindow<Event: VeloxUserEvent, WindowDispatcher: VeloxWindowDispatcher, WebviewDispatcher: VeloxWebviewDispatcher> where WindowDispatcher.Event == Event, WebviewDispatcher.Event == Event, WindowDispatcher.Identifier == WebviewDispatcher.Identifier {
  public let id: WindowDispatcher.Identifier
  public let label: String
  public let dispatcher: WindowDispatcher
  public let webview: WebviewDispatcher?

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

public protocol VeloxRuntimeHandle: AnyObject {
  associatedtype Event: VeloxUserEvent
  associatedtype WindowDispatcher: VeloxWindowDispatcher where WindowDispatcher.Event == Event
  associatedtype WebviewDispatcher: VeloxWebviewDispatcher where WebviewDispatcher.Event == Event, WebviewDispatcher.Identifier == WindowDispatcher.Identifier
  associatedtype EventLoopProxyType: VeloxEventLoopProxy where EventLoopProxyType.Event == Event

  func createProxy() throws -> EventLoopProxyType
  func requestExit(code: Int32) throws
  func createWindow(
    pending: VeloxPendingWindow<Event>
  ) throws -> VeloxDetachedWindow<Event, WindowDispatcher, WebviewDispatcher>
  func createWebview(
    window: WindowDispatcher.Identifier,
    pending: VeloxPendingWebview<Event>
  ) throws -> WebviewDispatcher
}

public enum VeloxRunEvent<Event: VeloxUserEvent>: Sendable {
  case ready
  case exit
  case exitRequested(code: Int32?)
  case windowEvent(label: String)
  case webviewEvent(label: String)
  case userEvent(Event)
  case raw(description: String)
}

public protocol VeloxRuntime: AnyObject {
  associatedtype Event: VeloxUserEvent
  associatedtype Handle: VeloxRuntimeHandle where Handle.Event == Event
  associatedtype EventLoopProxyType: VeloxEventLoopProxy where EventLoopProxyType.Event == Event

  static func make(args: VeloxRuntimeInitArgs) throws -> Self
  func handle() -> Handle
  func createProxy() throws -> EventLoopProxyType
  func createWindow(
    pending: VeloxPendingWindow<Event>
  ) throws -> VeloxDetachedWindow<Event, Handle.WindowDispatcher, Handle.WebviewDispatcher>
  func createWebview(
    window: Handle.WindowDispatcher.Identifier,
    pending: VeloxPendingWebview<Event>
  ) throws -> Handle.WebviewDispatcher
  func runIteration(handler: @escaping @Sendable (VeloxRunEvent<Event>) -> VeloxControlFlow)
}
