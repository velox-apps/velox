import Foundation
import VeloxRuntime
import VeloxRuntimeWryFFI

final class VeloxEventStreamMultiplexer<Value> {
  private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
  private let lock = NSLock()

  func add(_ continuation: AsyncStream<Value>.Continuation) -> UUID {
    let token = UUID()
    lock.lock()
    continuations[token] = continuation
    lock.unlock()
    return token
  }

  func remove(_ token: UUID) {
    lock.lock()
    continuations.removeValue(forKey: token)
    lock.unlock()
  }

  func yield(_ value: Value) {
    lock.lock()
    let snapshots = Array(continuations.values)
    lock.unlock()
    for continuation in snapshots {
      continuation.yield(value)
    }
  }

  func finishAll() {
    lock.lock()
    let snapshots = Array(continuations.values)
    continuations.removeAll()
    lock.unlock()
    for continuation in snapshots {
      continuation.finish()
    }
  }

  var isEmpty: Bool {
    lock.lock()
    let empty = continuations.isEmpty
    lock.unlock()
    return empty
  }
}

/// Convenience wrapper around the Rust FFI exported by `velox-runtime-wry-ffi`.
/// This provides a Swift-first surface that mirrors the original Tauri `wry`
/// runtime API naming while renaming public symbols to the Velox domain.
public enum VeloxRuntimeWry {
  public enum RuntimeError: Swift.Error {
    case unsupported
  }

  /// Describes the versions of the Velox runtime and the underlying WebView
  /// implementation.
  public struct Version: Sendable, Hashable {
    public let runtime: String
    public let webview: String

    public init(runtime: String, webview: String) {
      self.runtime = runtime
      self.webview = webview
    }
  }

  /// The canonical module name used when interacting with the Rust side.
  public static var moduleName: String {
    string(from: velox_runtime_wry_library_name())
  }

  /// Version information for the Swift-facing runtime.
  public static var version: Version {
    Version(
      runtime: string(from: velox_runtime_wry_crate_version()),
      webview: string(from: velox_runtime_wry_webview_version())
    )
  }

  /// Control flow hints returned by event loop callbacks.
  public enum ControlFlow: Int32, Sendable {
    case poll = 0
    case wait = 1
    case exit = 2
  }

  /// Window configuration subset mirrored from `tao::window::WindowBuilder`.
  public struct WindowConfiguration: Sendable {
    public var width: UInt32
    public var height: UInt32
    public var title: String

    public init(width: UInt32 = 0, height: UInt32 = 0, title: String = "") {
      self.width = width
      self.height = height
      self.title = title
    }
  }

  /// Webview configuration subset mirrored from `wry::WebViewBuilder`.
  public struct WebviewConfiguration: Sendable {
    public var url: String

    public init(url: String = "") {
      self.url = url
    }
  }
}

public extension VeloxRuntimeWry {
  /// Swift-native runtime adapter that drives the tao event loop without relying on tauri-runtime.
  final class Runtime: VeloxRuntime {
    public typealias Event = VeloxRuntimeWry.Event
    public typealias Handle = Runtime
    public typealias EventLoopProxyType = EventLoopProxyAdapter

    private struct WindowState {
      let label: String
      let taoIdentifier: String
      let window: Window
      var webview: Webview?
    }

    private let eventLoop: EventLoop
    private let eventLoopProxy: EventLoopProxy?
    private let stateLock = NSLock()
    private var windows: [ObjectIdentifier: WindowState] = [:]
    private var windowsByLabel: [String: ObjectIdentifier] = [:]
    private var windowsByTaoIdentifier: [String: ObjectIdentifier] = [:]
    private var windowEventStreams: [ObjectIdentifier: VeloxEventStreamMultiplexer<WindowEvent>] = [:]
    private var webviewEventStreams: [ObjectIdentifier: VeloxEventStreamMultiplexer<WebviewEvent>] = [:]
    private let menuEventStream = VeloxEventStreamMultiplexer<MenuEvent>()
    private let trayEventStream = VeloxEventStreamMultiplexer<TrayEventNotification>()

    public static func make(args _: VeloxRuntimeInitArgs) throws -> Runtime {
      guard Thread.isMainThread else {
        throw VeloxRuntimeError.failed(description: "VeloxRuntimeWry.Runtime must be created on the main thread")
      }
      guard let eventLoop = EventLoop() else {
        throw VeloxRuntimeError.unsupported
      }
      return Runtime(eventLoop: eventLoop)
    }

    public convenience init?() {
      guard Thread.isMainThread else {
        return nil
      }
      guard let eventLoop = EventLoop() else {
        return nil
      }
      self.init(eventLoop: eventLoop)
    }

    private init(eventLoop: EventLoop) {
      self.eventLoop = eventLoop
      self.eventLoopProxy = eventLoop.makeProxy()
    }

    public func handle() -> Runtime { self }

    public func createProxy() throws -> EventLoopProxyAdapter {
      guard let proxy = eventLoopProxy else {
        throw VeloxRuntimeError.unsupported
      }
      return EventLoopProxyAdapter(proxy: proxy)
    }

    public func createWindow(
      pending: VeloxPendingWindow<Event>
    ) throws -> VeloxDetachedWindow<Event, Window, Webview> {
      guard let window = eventLoop.makeWindow(configuration: .init(title: pending.label)) else {
        throw VeloxRuntimeError.unsupported
      }
      return registerWindow(window, label: pending.label)
    }

    public func createWebview(
      window identifier: ObjectIdentifier,
      pending _: VeloxPendingWebview<Event>
    ) throws -> Webview {
      let state: WindowState? = {
        stateLock.lock()
        defer { stateLock.unlock() }
        return windows[identifier]
      }()

      guard let state else {
        throw VeloxRuntimeError.failed(description: "window not found")
      }

      guard let webview = state.window.makeWebview() else {
        throw VeloxRuntimeError.unsupported
      }

      stateLock.lock()
      var updated = state
      updated.webview = webview
      windows[identifier] = updated
      stateLock.unlock()

      webview.register(owner: self, windowIdentifier: identifier)

      return webview
    }

    public func runIteration(
      handler: @Sendable @escaping (VeloxRunEvent<Event>) -> VeloxControlFlow
    ) {
      eventLoop.pump { event in
        self.route(event)
        let flow = handler(self.toRunEvent(from: event))
        switch flow {
        case .poll: return ControlFlow.poll
        case .wait: return ControlFlow.wait
        case .exit: return ControlFlow.exit
        }
      }
    }

    public func requestExit(code: Int32) throws {
      guard let proxy = eventLoopProxy else {
        throw VeloxRuntimeError.unsupported
      }
      guard proxy.requestExit() else {
        throw VeloxRuntimeError.failed(description: "failed to signal event loop exit")
      }
    }

    @discardableResult
    public func requestExitIfPossible(code: Int32 = 0) -> Bool {
      (try? requestExit(code: code)) != nil
    }

    @discardableResult
    public func createWindow(
      configuration: WindowConfiguration? = nil,
      label: String? = nil
    ) throws -> VeloxDetachedWindow<Event, Window, Webview> {
      guard let window = eventLoop.makeWindow(configuration: configuration) else {
        throw VeloxRuntimeError.unsupported
      }
      let resolvedLabel = label ?? configuration?.title ?? makeDefaultLabel(for: window)
      return registerWindow(window, label: resolvedLabel)
    }

    public func windowIdentifier(forLabel label: String) -> ObjectIdentifier? {
      stateLock.lock()
      defer { stateLock.unlock() }
      return windowsByLabel[label]
    }

    public func window(for label: String) -> Window? {
      stateLock.lock()
      defer { stateLock.unlock() }
      guard let identifier = windowsByLabel[label], let state = windows[identifier] else {
        return nil
      }
      return state.window
    }

    private func registerWindow(
      _ window: Window,
      label: String,
      webview: Webview? = nil
    ) -> VeloxDetachedWindow<Event, Window, Webview> {
      let identifier = ObjectIdentifier(window)
      let taoIdentifier = window.taoIdentifier
      let state = WindowState(label: label, taoIdentifier: taoIdentifier, window: window, webview: webview)
      stateLock.lock()
      windows[identifier] = state
      windowsByLabel[label] = identifier
      windowsByTaoIdentifier[taoIdentifier] = identifier
      stateLock.unlock()
      window.register(owner: self)
      return VeloxDetachedWindow(id: identifier, label: label, dispatcher: window, webview: webview)
    }

    public func menuEvents(
      bufferingPolicy: AsyncStream<MenuEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<MenuEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = self.menuEventStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.menuEventStream.remove(token)
        }
      }
    }

    public func trayEvents(
      bufferingPolicy: AsyncStream<TrayEventNotification>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<TrayEventNotification> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = self.trayEventStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.trayEventStream.remove(token)
        }
      }
    }

    private func makeDefaultLabel(for window: Window) -> String {
      "window-\(window.taoIdentifier)"
    }

    private func label(forWindowIdentifier identifier: String) -> String {
      stateLock.lock()
      defer { stateLock.unlock() }
      if let objectIdentifier = windowsByTaoIdentifier[identifier], let state = windows[objectIdentifier] {
        return state.label
      }
      return identifier
    }

    private func removeWindow(forWindowIdentifier identifier: String) -> String? {
      var label: String?
      var windowStream: VeloxEventStreamMultiplexer<WindowEvent>?
      var webviewStream: VeloxEventStreamMultiplexer<WebviewEvent>?

      stateLock.lock()
      if let objectIdentifier = windowsByTaoIdentifier.removeValue(forKey: identifier),
        let state = windows.removeValue(forKey: objectIdentifier)
      {
        windowsByLabel.removeValue(forKey: state.label)
        label = state.label
        windowStream = windowEventStreams.removeValue(forKey: objectIdentifier)
        webviewStream = webviewEventStreams.removeValue(forKey: objectIdentifier)
      }
      stateLock.unlock()

      windowStream?.finishAll()
      webviewStream?.finishAll()

      return label
    }

    fileprivate func windowEventStream(
      for identifier: ObjectIdentifier,
      bufferingPolicy: AsyncStream<WindowEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<WindowEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token: UUID = {
          stateLock.lock()
          defer { stateLock.unlock() }
          let sink = windowEventStreams[identifier] ?? VeloxEventStreamMultiplexer<WindowEvent>()
          let token = sink.add(continuation)
          windowEventStreams[identifier] = sink
          return token
        }()

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.stateLock.lock()
          if let sink = self.windowEventStreams[identifier] {
            sink.remove(token)
            if sink.isEmpty {
              self.windowEventStreams.removeValue(forKey: identifier)
            }
          }
          self.stateLock.unlock()
        }
      }
    }

    fileprivate func webviewEventStream(
      for identifier: ObjectIdentifier,
      bufferingPolicy: AsyncStream<WebviewEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<WebviewEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token: UUID = {
          stateLock.lock()
          defer { stateLock.unlock() }
          let sink = webviewEventStreams[identifier] ?? VeloxEventStreamMultiplexer<WebviewEvent>()
          let token = sink.add(continuation)
          webviewEventStreams[identifier] = sink
          return token
        }()

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.stateLock.lock()
          if let sink = self.webviewEventStreams[identifier] {
            sink.remove(token)
            if sink.isEmpty {
              self.webviewEventStreams.removeValue(forKey: identifier)
            }
          }
          self.stateLock.unlock()
        }
      }
    }

    private func route(_ event: Event) {
      switch event {
      case .windowCloseRequested(let windowId),
        .windowDestroyed(let windowId),
        .windowResized(let windowId, _),
        .windowMoved(let windowId, _),
        .windowFocused(let windowId, _),
        .windowScaleFactorChanged(let windowId, _, _),
        .windowKeyboardInput(let windowId, _),
        .windowImeText(let windowId, _),
        .windowModifiersChanged(let windowId, _),
        .windowCursorMoved(let windowId, _),
        .windowCursorEntered(let windowId, _),
        .windowCursorLeft(let windowId, _),
        .windowMouseInput(let windowId, _),
        .windowMouseWheel(let windowId, _, _),
        .windowDroppedFile(let windowId, _),
        .windowHoveredFile(let windowId, _),
        .windowHoveredFileCancelled(let windowId),
        .windowThemeChanged(let windowId, _),
        .windowEvent(let windowId, _),
        .windowRedrawRequested(let windowId):
        deliverWindowEvent(windowIdentifier: windowId, event: event)
      case .webviewEvent(let label, _):
        deliverWebviewEvent(label: label, event: event)
      case .loopDestroyed, .exit, .userExit:
        finishAllStreams()
      case .menuEvent(let identifier):
        menuEventStream.yield(.activated(identifier: identifier))
      case .trayEvent(let trayEvent):
        trayEventStream.yield(.init(identifier: trayEvent.identifier, event: trayEvent))
      default:
        break
      }
    }

    private func deliverWindowEvent(windowIdentifier: String, event: Event) {
      var sink: VeloxEventStreamMultiplexer<WindowEvent>?
      var label: String?
      stateLock.lock()
      if let objectIdentifier = windowsByTaoIdentifier[windowIdentifier],
        let state = windows[objectIdentifier]
      {
        sink = windowEventStreams[objectIdentifier]
        label = state.label
      }
      stateLock.unlock()

      if let sink, let label {
        let payload = VeloxRuntimeWry.makeWindowEvent(label: label, event: event)
        sink.yield(payload)
      }
    }

    private func deliverWebviewEvent(label: String, event: Event) {
      var sink: VeloxEventStreamMultiplexer<WebviewEvent>?
      stateLock.lock()
      if let objectIdentifier = windowsByLabel[label] {
        sink = webviewEventStreams[objectIdentifier]
      }
      stateLock.unlock()

      if let sink {
        let payload = VeloxRuntimeWry.makeWebviewEvent(label: label, event: event)
        sink.yield(payload)
      }
    }

    private func finishAllStreams() {
      let windowSinks: [VeloxEventStreamMultiplexer<WindowEvent>]
      let webviewSinks: [VeloxEventStreamMultiplexer<WebviewEvent>]

      stateLock.lock()
      windowSinks = Array(windowEventStreams.values)
      webviewSinks = Array(webviewEventStreams.values)
      windowEventStreams.removeAll()
      webviewEventStreams.removeAll()
      stateLock.unlock()

      windowSinks.forEach { $0.finishAll() }
      webviewSinks.forEach { $0.finishAll() }
      menuEventStream.finishAll()
      trayEventStream.finishAll()
    }

    private func toRunEvent(from event: Event) -> VeloxRunEvent<Event> {
      switch event {
      case .ready:
        return .ready
      case .loopDestroyed, .userExit:
        return .exit
      case let .exitRequested(code):
        return .exitRequested(code: code)
      case let .webviewEvent(label, _):
        return .webviewEvent(label: label)
      case .windowDestroyed(let windowId):
        let label = removeWindow(forWindowIdentifier: windowId) ?? windowId
        return .windowEvent(label: label)
      case .windowCloseRequested(let windowId),
        .windowResized(let windowId, _),
        .windowMoved(let windowId, _),
        .windowFocused(let windowId, _),
        .windowScaleFactorChanged(let windowId, _, _),
        .windowKeyboardInput(let windowId, _),
        .windowImeText(let windowId, _),
        .windowModifiersChanged(let windowId, _),
        .windowCursorMoved(let windowId, _),
        .windowCursorEntered(let windowId, _),
        .windowCursorLeft(let windowId, _),
        .windowMouseInput(let windowId, _),
        .windowMouseWheel(let windowId, _, _),
        .windowDroppedFile(let windowId, _),
        .windowHoveredFile(let windowId, _),
        .windowHoveredFileCancelled(let windowId),
        .windowThemeChanged(let windowId, _),
        .windowEvent(let windowId, _):
        let label = label(forWindowIdentifier: windowId)
        return .windowEvent(label: label)
      case let .raw(description):
        return .raw(description: description)
      case .menuEvent:
        return .userEvent(event)
      default:
        return .userEvent(event)
      }
    }
  }

  /// Wrapper around `tao::event_loop::EventLoop` exposing a pump-based processing model.
  final class EventLoop {
    private var raw: UnsafeMutablePointer<VeloxEventLoopHandle>?

    public init?() {
      guard let handle = velox_event_loop_new() else {
        return nil
      }
      raw = handle
    }

    deinit {
      if let raw {
        velox_event_loop_free(raw)
      }
    }

    /// Releases the underlying Tao event loop handle immediately. Further usage is undefined.
    public func shutdown() {
      if let raw {
        velox_event_loop_free(raw)
        self.raw = nil
      }
    }

    /// Runs a single event loop iteration via `EventLoopExtRunReturn`, invoking the callback for
    /// every Tao event processed before exiting. Return `.exit` from the callback (or send an exit
    /// request through the proxy) to break the loop.
    public func pump(_ handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
      guard let raw else {
        return
      }

      let box = EventLoopCallback(handler: handler)
      let unmanaged = Unmanaged.passRetained(box)
      velox_event_loop_pump(raw, EventLoop.callback, unmanaged.toOpaque())
      unmanaged.release()
    }

    /// Creates a proxy that can be used to send user events such as exit requests.
    public func makeProxy() -> EventLoopProxy? {
      guard let raw else {
        return nil
      }
      guard let handle = velox_event_loop_create_proxy(raw) else {
        return nil
      }
      return EventLoopProxy(raw: handle)
    }

    /// Convenience to build a Tao window using the underlying event loop.
    public func makeWindow(configuration: WindowConfiguration? = nil) -> Window? {
      guard let raw else {
        return nil
      }

      if let configuration {
        return withOptionalCString(configuration.title) { titlePointer in
          var native = VeloxWindowConfig(width: configuration.width, height: configuration.height, title: titlePointer)
          return withUnsafePointer(to: &native) { pointer in
            guard let handle = velox_window_build(raw, pointer) else {
              return nil
            }
            return Window(raw: handle)
          }
        }
      } else {
        guard let handle = velox_window_build(raw, nil) else {
          return nil
        }
        return Window(raw: handle)
      }
    }

#if os(macOS)
    public enum ActivationPolicy {
      case regular
      case accessory
      case prohibited
    }

    @discardableResult
    public func setActivationPolicy(_ policy: ActivationPolicy) -> Bool {
      guard let raw else {
        return false
      }

      let ffiPolicy: VeloxActivationPolicy
      switch policy {
      case .regular: ffiPolicy = VELOX_ACTIVATION_POLICY_REGULAR
      case .accessory: ffiPolicy = VELOX_ACTIVATION_POLICY_ACCESSORY
      case .prohibited: ffiPolicy = VELOX_ACTIVATION_POLICY_PROHIBITED
      }
      return velox_event_loop_set_activation_policy(raw, ffiPolicy)
    }

    @discardableResult
    public func setDockVisibility(_ visible: Bool) -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_set_dock_visibility(raw, visible)
    }

    @discardableResult
    public func hideApplication() -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_hide_application(raw)
    }

    @discardableResult
    public func showApplication() -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_show_application(raw)
    }
#endif

    private final class EventLoopCallback {
      let handler: @Sendable (_ event: Event) -> ControlFlow

      init(handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
        self.handler = handler
      }
    }

    private static let callback: @convention(c) (
      UnsafePointer<CChar>?,
      UnsafeMutableRawPointer?
    ) -> VeloxRuntimeWryFFI.VeloxEventLoopControlFlow = { event, userData in
      guard let userData else {
        return VELOX_CONTROL_FLOW_EXIT
      }

      let box = Unmanaged<EventLoopCallback>.fromOpaque(userData).takeUnretainedValue()
      let json = event.map { String(cString: $0) } ?? "{}"
      let parsedEvent = Event(fromJSON: json)
      let flow = box.handler(parsedEvent)
      return VeloxRuntimeWryFFI.VeloxEventLoopControlFlow(rawValue: UInt32(flow.rawValue))
    }
  }

  /// Handle to a Tao `EventLoopProxy` enabling exit requests from other threads.
  final class EventLoopProxy {
    private let raw: UnsafeMutablePointer<VeloxEventLoopProxyHandle>

    fileprivate init?(raw: UnsafeMutablePointer<VeloxEventLoopProxyHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_event_loop_proxy_free(raw)
    }

    /// Sends a termination request into the event loop.
    @discardableResult
    public func requestExit() -> Bool {
      velox_event_loop_proxy_request_exit(raw)
    }

    /// Sends a custom user event payload into the event loop.
    @discardableResult
    public func sendUserEvent(_ payload: String) -> Bool {
      withOptionalCString(payload) { pointer in
        velox_event_loop_proxy_send_user_event(raw, pointer)
      }
    }

    @discardableResult
    public func sendUserEvent<T: Encodable>(
      _ payload: T,
      encoder: JSONEncoder = JSONEncoder()
    ) -> Bool {
      guard let encoded = try? VeloxRuntimeWry.UserDefinedPayload(encoding: payload, encoder: encoder) else {
        return false
      }
      return sendUserEvent(encoded.rawValue)
    }
  }

  /// Handle wrapper mirroring Tao's `Window`.
  final class Window {
    fileprivate let raw: UnsafeMutablePointer<VeloxWindowHandle>
    private weak var owner: Runtime?

    public enum AttentionType: Int32, Sendable {
      case informational = 0
      case critical = 1
    }

    public enum ResizeDirection: Int32, Sendable {
      case east = 0
      case north = 1
      case northEast = 2
      case northWest = 3
      case south = 4
      case southEast = 5
      case southWest = 6
      case west = 7
    }

    public struct Color: Sendable, Equatable {
      public var red: Double
      public var green: Double
      public var blue: Double
      public var alpha: Double

      public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
      }

      fileprivate func toFFI() -> VeloxColor {
        func clamp(_ value: Double) -> UInt8 {
          let clamped = min(max(value, 0.0), 1.0)
          return UInt8((clamped * 255.0).rounded())
        }
        return VeloxColor(
          red: clamp(red),
          green: clamp(green),
          blue: clamp(blue),
          alpha: clamp(alpha)
        )
      }
    }

    public enum Theme: Sendable, Equatable {
      case light
      case dark
    }

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWindowHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_window_free(raw)
    }

    fileprivate var taoIdentifier: String {
      string(from: velox_window_identifier(raw))
    }

    fileprivate func register(owner: Runtime) {
      self.owner = owner
    }

    /// Builds a Wry webview attached to the window.
    public func makeWebview(configuration: WebviewConfiguration? = nil) -> Webview? {
      if let configuration {
        return withOptionalCString(configuration.url) { urlPointer in
          var native = VeloxWebviewConfig(url: urlPointer)
          return withUnsafePointer(to: &native) { pointer in
            guard let handle = velox_webview_build(raw, pointer) else {
              return nil
            }
            let webview = Webview(raw: handle)
            return register(webview: webview)
          }
        }
      } else {
        guard let handle = velox_webview_build(raw, nil) else {
          return nil
        }
        let webview = Webview(raw: handle)
        return register(webview: webview)
      }
    }

    private func register(webview: Webview?) -> Webview? {
      guard let webview else {
        return nil
      }
      if let owner {
        webview.register(owner: owner, windowIdentifier: ObjectIdentifier(self))
      }
      return webview
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      return title.withCString { velox_window_set_title(raw, $0) }
    }

    public func title() -> String {
      string(from: velox_window_title(raw))
    }

    @discardableResult
    public func setFullscreen(_ isFullscreen: Bool) -> Bool {
      return velox_window_set_fullscreen(raw, isFullscreen)
    }

    public func isFullscreen() -> Bool {
      velox_window_is_fullscreen(raw)
    }

    @discardableResult
    public func setDecorations(_ decorations: Bool) -> Bool {
      velox_window_set_decorations(raw, decorations)
    }

    @discardableResult
    public func setResizable(_ resizable: Bool) -> Bool {
      return velox_window_set_resizable(raw, resizable)
    }

    @discardableResult
    public func setAlwaysOnTop(_ onTop: Bool) -> Bool {
      return velox_window_set_always_on_top(raw, onTop)
    }

    @discardableResult
    public func setAlwaysOnBottom(_ onBottom: Bool) -> Bool {
      velox_window_set_always_on_bottom(raw, onBottom)
    }

    @discardableResult
    public func setVisibleOnAllWorkspaces(_ visible: Bool) -> Bool {
      velox_window_set_visible_on_all_workspaces(raw, visible)
    }

    @discardableResult
    public func setContentProtected(_ protected: Bool) -> Bool {
      velox_window_set_content_protected(raw, protected)
    }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
      return velox_window_set_visible(raw, visible)
    }

    @discardableResult
    public func setMaximized(_ maximized: Bool) -> Bool {
      velox_window_set_maximized(raw, maximized)
    }

    @discardableResult
    public func setMinimized(_ minimized: Bool) -> Bool {
      velox_window_set_minimized(raw, minimized)
    }

    @discardableResult
    public func setMinimizable(_ minimizable: Bool) -> Bool {
      velox_window_set_minimizable(raw, minimizable)
    }

    @discardableResult
    public func setMaximizable(_ maximizable: Bool) -> Bool {
      velox_window_set_maximizable(raw, maximizable)
    }

    @discardableResult
    public func setClosable(_ closable: Bool) -> Bool {
      velox_window_set_closable(raw, closable)
    }

    @discardableResult
    public func setSkipTaskbar(_ skip: Bool) -> Bool {
      velox_window_set_skip_taskbar(raw, skip)
    }

    @discardableResult
    public func setBackgroundColor(_ color: Color?) -> Bool {
      if let value = color {
        var ffiColor = value.toFFI()
        return withUnsafePointer(to: &ffiColor) { pointer in
          velox_window_set_background_color(raw, pointer)
        }
      } else {
        return velox_window_set_background_color(raw, nil)
      }
    }

    @discardableResult
    public func setTheme(_ theme: Theme?) -> Bool {
      let ffiTheme: VeloxWindowTheme
      switch theme {
      case .some(.light): ffiTheme = VELOX_WINDOW_THEME_LIGHT
      case .some(.dark): ffiTheme = VELOX_WINDOW_THEME_DARK
      case .none: ffiTheme = VELOX_WINDOW_THEME_UNSPECIFIED
      }
      return velox_window_set_theme(raw, ffiTheme)
    }

    public func currentMonitor() -> MonitorInfo? {
      decodeMonitorInfo(from: velox_window_current_monitor(raw))
    }

    public func primaryMonitor() -> MonitorInfo? {
      decodeMonitorInfo(from: velox_window_primary_monitor(raw))
    }

    public func availableMonitors() -> [MonitorInfo] {
      decodeMonitorInfoList(from: velox_window_available_monitors(raw))
    }

    public func monitor(at position: WindowPosition) -> MonitorInfo? {
      let point = VeloxPoint(x: position.x, y: position.y)
      return decodeMonitorInfo(from: velox_window_monitor_from_point(raw, point))
    }

    public func cursorPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_cursor_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func isMaximized() -> Bool {
      velox_window_is_maximized(raw)
    }

    public func isMinimized() -> Bool {
      velox_window_is_minimized(raw)
    }

    public func isVisible() -> Bool {
      velox_window_is_visible(raw)
    }

    public func isResizable() -> Bool {
      velox_window_is_resizable(raw)
    }

    public func isDecorated() -> Bool {
      velox_window_is_decorated(raw)
    }

    public func isAlwaysOnTop() -> Bool {
      velox_window_is_always_on_top(raw)
    }

    public func isMinimizable() -> Bool {
      velox_window_is_minimizable(raw)
    }

    public func isMaximizable() -> Bool {
      velox_window_is_maximizable(raw)
    }

    public func isClosable() -> Bool {
      velox_window_is_closable(raw)
    }

    public func scaleFactor() -> Double? {
      var value: Double = 0
      guard velox_window_scale_factor(raw, &value) else {
        return nil
      }
      return value
    }

    public func innerPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_inner_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func outerPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_outer_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func innerSize() -> WindowSize? {
      var size = VeloxSize(width: 0, height: 0)
      guard velox_window_inner_size(raw, &size) else {
        return nil
      }
          return WindowSize(width: size.width, height: size.height)
    }

    public func outerSize() -> WindowSize? {
      var size = VeloxSize(width: 0, height: 0)
      guard velox_window_outer_size(raw, &size) else {
        return nil
      }
      return WindowSize(width: size.width, height: size.height)
    }

    public func isFocused() -> Bool {
      velox_window_is_focused(raw)
    }

    public func events(
      bufferingPolicy: AsyncStream<WindowEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<WindowEvent> {
      guard let owner else {
        return AsyncStream { continuation in
          continuation.finish()
        }
      }
      return owner.windowEventStream(for: ObjectIdentifier(self), bufferingPolicy: bufferingPolicy)
    }

    @discardableResult
    public func focus() -> Bool {
      velox_window_focus(raw)
    }

    @discardableResult
    public func setFocusable(_ focusable: Bool) -> Bool {
      velox_window_set_focusable(raw, focusable)
    }

    @discardableResult
    public func requestRedraw() -> Bool {
      return velox_window_request_redraw(raw)
    }

    @discardableResult
    public func setSize(width: Double, height: Double) -> Bool {
      return velox_window_set_size(raw, width, height)
    }

    @discardableResult
    public func setPosition(x: Double, y: Double) -> Bool {
      return velox_window_set_position(raw, x, y)
    }

    @discardableResult
    public func setMinimumSize(width: Double, height: Double) -> Bool {
      return velox_window_set_min_size(raw, width, height)
    }

    @discardableResult
    public func setMaximumSize(width: Double, height: Double) -> Bool {
      return velox_window_set_max_size(raw, width, height)
    }

    @discardableResult
    public func requestUserAttention(_ type: AttentionType) -> Bool {
      let ffiType = VeloxUserAttentionType(rawValue: UInt32(type.rawValue))
      return velox_window_request_user_attention(raw, ffiType)
    }

    @discardableResult
    public func clearUserAttention() -> Bool {
      velox_window_clear_user_attention(raw)
    }

    @discardableResult
    public func startDragging() -> Bool {
      velox_window_start_dragging(raw)
    }

    @discardableResult
    public func startResizeDragging(_ direction: ResizeDirection) -> Bool {
      let ffiDirection = VeloxResizeDirection(rawValue: UInt32(direction.rawValue))
      return velox_window_start_resize_dragging(raw, ffiDirection)
    }

    @discardableResult
    public func setCursorGrab(_ grab: Bool) -> Bool {
      velox_window_set_cursor_grab(raw, grab)
    }

    @discardableResult
    public func setCursorVisible(_ visible: Bool) -> Bool {
      velox_window_set_cursor_visible(raw, visible)
    }

    @discardableResult
    public func setCursorPosition(x: Double, y: Double) -> Bool {
      velox_window_set_cursor_position(raw, x, y)
    }

    @discardableResult
    public func setIgnoreCursorEvents(_ ignore: Bool) -> Bool {
      velox_window_set_ignore_cursor_events(raw, ignore)
    }
  }

  /// Handle wrapper mirroring Wry's `WebView`.
  final class Webview {
    private let raw: UnsafeMutablePointer<VeloxWebviewHandle>
    private weak var owner: Runtime?
    private var windowIdentifier: ObjectIdentifier?

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWebviewHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_webview_free(raw)
    }

    fileprivate func register(owner: Runtime, windowIdentifier: ObjectIdentifier) {
      self.owner = owner
      self.windowIdentifier = windowIdentifier
    }

    public func events(
      bufferingPolicy: AsyncStream<WebviewEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<WebviewEvent> {
      guard let owner, let windowIdentifier else {
        return AsyncStream { continuation in
          continuation.finish()
        }
      }
      return owner.webviewEventStream(for: windowIdentifier, bufferingPolicy: bufferingPolicy)
    }

    @discardableResult
    public func navigate(to url: String) -> Bool {
      url.withCString { velox_webview_navigate(raw, $0) }
    }

    @discardableResult
    public func reload() -> Bool {
      velox_webview_reload(raw)
    }

    @discardableResult
    public func evaluate(script: String) -> Bool {
      script.withCString { velox_webview_evaluate_script(raw, $0) }
    }

    @discardableResult
    public func setZoom(_ scale: Double) -> Bool {
      velox_webview_set_zoom(raw, scale)
    }

    @discardableResult
    public func show() -> Bool {
      velox_webview_show(raw)
    }

    @discardableResult
    public func hide() -> Bool {
      velox_webview_hide(raw)
    }

    @discardableResult
    public func clearBrowsingData() -> Bool {
      velox_webview_clear_browsing_data(raw)
    }
  }
}

public extension VeloxRuntimeWry {
  struct WindowSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
    }
  }

  struct WindowPosition: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  struct MonitorInfo: Sendable, Equatable {
    public var name: String
    public var position: WindowPosition
    public var size: WindowSize
    public var scaleFactor: Double

    public init(name: String, position: WindowPosition, size: WindowSize, scaleFactor: Double) {
      self.name = name
      self.position = position
      self.size = size
      self.scaleFactor = scaleFactor
    }
  }

  struct TrayRect: Sendable, Equatable {
    public var origin: WindowPosition
    public var size: WindowSize

    public init(origin: WindowPosition, size: WindowSize) {
      self.origin = origin
      self.size = size
    }
  }

  struct TrayEvent: Sendable, Equatable {
    public enum EventType: String, Sendable, Equatable {
      case click
      case doubleClick = "double-click"
      case enter
      case move
      case leave
      case unknown
    }

    public var identifier: String
    public var type: EventType
    public var button: String?
    public var buttonState: String?
    public var position: WindowPosition?
    public var rect: TrayRect?

    public init(
      identifier: String,
      type: EventType,
      button: String?,
      buttonState: String?,
      position: WindowPosition?,
      rect: TrayRect?
    ) {
      self.identifier = identifier
      self.type = type
      self.button = button
      self.buttonState = buttonState
      self.position = position
      self.rect = rect
    }
  }

  struct KeyboardInput: Sendable, Equatable {
    public var state: String
    public var logicalKey: String
    public var physicalKey: String
    public var text: String?
    public var isRepeat: Bool
    public var location: String
    public var isSynthetic: Bool

    public init(
      state: String,
      logicalKey: String,
      physicalKey: String,
      text: String?,
      isRepeat: Bool,
      location: String,
      isSynthetic: Bool
    ) {
      self.state = state
      self.logicalKey = logicalKey
      self.physicalKey = physicalKey
      self.text = text
      self.isRepeat = isRepeat
      self.location = location
      self.isSynthetic = isSynthetic
    }
  }

  struct Modifiers: Sendable, Equatable {
    public var shift: Bool
    public var control: Bool
    public var alt: Bool
    public var superKey: Bool

    public init(shift: Bool, control: Bool, alt: Bool, superKey: Bool) {
      self.shift = shift
      self.control = control
      self.alt = alt
      self.superKey = superKey
    }
  }

  struct MouseInput: Sendable, Equatable {
    public var state: String
    public var button: String

    public init(state: String, button: String) {
      self.state = state
      self.button = button
    }
  }

  struct MouseWheelDelta: Sendable, Equatable {
    public enum Unit: String, Sendable, Equatable {
      case line
      case pixel
      case unknown
    }

    public var unit: Unit
    public var x: Double?
    public var y: Double?

    public init(unit: Unit, x: Double?, y: Double?) {
      self.unit = unit
      self.x = x
      self.y = y
    }
  }

  struct UserDefinedPayload: Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONEncoder()) throws {
      let data = try encoder.encode(value)
      guard let string = String(data: data, encoding: .utf8) else {
        throw VeloxRuntimeError.failed(description: "Unable to encode user event payload as UTF-8")
      }
      self.rawValue = string
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
      guard let data = rawValue.data(using: .utf8) else {
        return nil
      }
      return try? decoder.decode(T.self, from: data)
    }
  }

  enum Event: Sendable, Equatable {
    case ready
    case newEvents(cause: String)
    case mainEventsCleared
    case redrawEventsCleared
    case loopDestroyed
    case exit
    case suspended
    case resumed
    case windowRedrawRequested(windowId: String)
    case userExit
    case exitRequested(code: Int32?)
    case deviceEvent(deviceId: String, description: String)
    case opened(urls: [String])
    case reopen(hasVisibleWindows: Bool)
    case windowCloseRequested(windowId: String)
    case windowDestroyed(windowId: String)
    case windowResized(windowId: String, size: WindowSize)
    case windowMoved(windowId: String, position: WindowPosition)
    case windowFocused(windowId: String, isFocused: Bool)
    case windowScaleFactorChanged(windowId: String, scaleFactor: Double, size: WindowSize)
    case windowKeyboardInput(windowId: String, input: KeyboardInput)
    case windowImeText(windowId: String, text: String)
    case windowModifiersChanged(windowId: String, modifiers: Modifiers)
    case windowCursorMoved(windowId: String, position: WindowPosition)
    case windowCursorEntered(windowId: String, deviceId: String)
    case windowCursorLeft(windowId: String, deviceId: String)
    case windowMouseInput(windowId: String, input: MouseInput)
    case windowMouseWheel(windowId: String, delta: MouseWheelDelta, phase: String)
    case webviewEvent(label: String, description: String)
    case windowDroppedFile(windowId: String, path: String)
    case windowHoveredFile(windowId: String, path: String)
    case windowHoveredFileCancelled(windowId: String)
    case windowThemeChanged(windowId: String, theme: String)
    case windowEvent(windowId: String, description: String)
    case userDefined(payload: UserDefinedPayload)
    case menuEvent(menuId: String)
    case trayEvent(event: TrayEvent)
    case raw(description: String)
    case unknown(json: String)

    init(fromJSON json: String) {
      guard
        let data = json.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let type = VeloxEventDecoder.string(object["type"])
      else {
        self = .unknown(json: json)
        return
      }

      switch type {
      case "ready":
        self = .ready
      case "new-events":
        let cause = VeloxEventDecoder.string(object["cause"]) ?? "unknown"
        self = .newEvents(cause: cause)
      case "main-events-cleared":
        self = .mainEventsCleared
      case "redraw-events-cleared":
        self = .redrawEventsCleared
      case "loop-destroyed":
        self = .loopDestroyed
      case "exit":
        self = .exit
      case "suspended":
        self = .suspended
      case "resumed":
        self = .resumed
      case "window-redraw-requested":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowRedrawRequested(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "user-exit":
        self = .userExit
      case "exit-requested":
        let codeValue = VeloxEventDecoder.double(object["code"]).map { Int32($0) }
        self = .exitRequested(code: codeValue)
      case "device-event":
        if
          let deviceId = VeloxEventDecoder.string(object["device_id"]),
          let description = VeloxEventDecoder.string(object["event"])
        {
          self = .deviceEvent(deviceId: deviceId, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "opened":
        let urls = VeloxEventDecoder.array(object["urls"])?.compactMap { VeloxEventDecoder.string($0) } ?? []
        self = .opened(urls: urls)
      case "reopen":
        let hasVisible = VeloxEventDecoder.bool(object["has_visible_windows"]) ?? false
        self = .reopen(hasVisibleWindows: hasVisible)
      case "window-close-requested":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowCloseRequested(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-destroyed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowDestroyed(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-resized":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let size = Event.decodeSize(VeloxEventDecoder.dictionary(object["size"])) ?? WindowSize(width: 0, height: 0)
          self = .windowResized(windowId: windowId, size: size)
        } else {
          self = .unknown(json: json)
        }
      case "window-moved":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"])) ?? WindowPosition(x: 0, y: 0)
          self = .windowMoved(windowId: windowId, position: position)
        } else {
          self = .unknown(json: json)
        }
      case "window-focused":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let focused = VeloxEventDecoder.bool(object["focused"]) ?? false
          self = .windowFocused(windowId: windowId, isFocused: focused)
        } else {
          self = .unknown(json: json)
        }
      case "window-scale-factor-changed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let scale = VeloxEventDecoder.double(object["scale_factor"]) ?? 1
          let size = Event.decodeSize(VeloxEventDecoder.dictionary(object["size"])) ?? WindowSize(width: 0, height: 0)
          self = .windowScaleFactorChanged(windowId: windowId, scaleFactor: scale, size: size)
        } else {
          self = .unknown(json: json)
        }
      case "window-keyboard-input":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let input = KeyboardInput(
            state: VeloxEventDecoder.string(object["state"]) ?? "unknown",
            logicalKey: VeloxEventDecoder.string(object["logical_key"]) ?? "unknown",
            physicalKey: VeloxEventDecoder.string(object["physical_key"]) ?? "unknown",
            text: VeloxEventDecoder.string(object["text"]),
            isRepeat: VeloxEventDecoder.bool(object["repeat"]) ?? false,
            location: VeloxEventDecoder.string(object["location"]) ?? "unknown",
            isSynthetic: VeloxEventDecoder.bool(object["is_synthetic"]) ?? false
          )
          self = .windowKeyboardInput(windowId: windowId, input: input)
        } else {
          self = .unknown(json: json)
        }
      case "window-ime-text":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let text = VeloxEventDecoder.string(object["text"])
        {
          self = .windowImeText(windowId: windowId, text: text)
        } else {
          self = .unknown(json: json)
        }
      case "window-modifiers-changed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let modifiersObject = VeloxEventDecoder.dictionary(object["modifiers"]) ?? [:]
          let modifiers = Modifiers(
            shift: VeloxEventDecoder.bool(modifiersObject["shift"]) ?? false,
            control: VeloxEventDecoder.bool(modifiersObject["control"]) ?? false,
            alt: VeloxEventDecoder.bool(modifiersObject["alt"]) ?? false,
            superKey: VeloxEventDecoder.bool(modifiersObject["super_key"]) ?? false
          )
          self = .windowModifiersChanged(windowId: windowId, modifiers: modifiers)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-moved":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"])) ?? WindowPosition(x: 0, y: 0)
          self = .windowCursorMoved(windowId: windowId, position: position)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-entered":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let deviceId = VeloxEventDecoder.string(object["device_id"])
        {
          self = .windowCursorEntered(windowId: windowId, deviceId: deviceId)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-left":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let deviceId = VeloxEventDecoder.string(object["device_id"])
        {
          self = .windowCursorLeft(windowId: windowId, deviceId: deviceId)
        } else {
          self = .unknown(json: json)
        }
      case "window-mouse-input":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let input = MouseInput(
            state: VeloxEventDecoder.string(object["state"]) ?? "unknown",
            button: VeloxEventDecoder.string(object["button"]) ?? "unknown"
          )
          self = .windowMouseInput(windowId: windowId, input: input)
        } else {
          self = .unknown(json: json)
        }
      case "window-mouse-wheel":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let deltaObject = VeloxEventDecoder.dictionary(object["delta"]) ?? [:]
          let unitString = VeloxEventDecoder.string(deltaObject["unit"]) ?? MouseWheelDelta.Unit.unknown.rawValue
          let delta = MouseWheelDelta(
            unit: MouseWheelDelta.Unit(rawValue: unitString) ?? .unknown,
            x: VeloxEventDecoder.double(deltaObject["x"]),
            y: VeloxEventDecoder.double(deltaObject["y"])
          )
          let phase = VeloxEventDecoder.string(object["phase"]) ?? "unknown"
          self = .windowMouseWheel(windowId: windowId, delta: delta, phase: phase)
        } else {
          self = .unknown(json: json)
        }
      case "webview-event":
        if
          let label = VeloxEventDecoder.string(object["label"]),
          let description = VeloxEventDecoder.string(object["event"])
        {
          self = .webviewEvent(label: label, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "window-dropped-file":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let path = VeloxEventDecoder.string(object["path"])
        {
          self = .windowDroppedFile(windowId: windowId, path: path)
        } else {
          self = .unknown(json: json)
        }
      case "window-hovered-file":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let path = VeloxEventDecoder.string(object["path"])
        {
          self = .windowHoveredFile(windowId: windowId, path: path)
        } else {
          self = .unknown(json: json)
        }
      case "window-hovered-file-cancelled":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowHoveredFileCancelled(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-theme-changed":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let theme = VeloxEventDecoder.string(object["theme"])
        {
          self = .windowThemeChanged(windowId: windowId, theme: theme)
        } else {
          self = .unknown(json: json)
        }
      case "window-event":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let description = VeloxEventDecoder.string(object["kind"])
        {
          self = .windowEvent(windowId: windowId, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "user-event":
        if VeloxEventDecoder.string(object["event"])?.lowercased() == "exit" {
          self = .userExit
        } else {
          let payload = VeloxEventDecoder.string(object["payload"]) ?? ""
          self = .userDefined(payload: UserDefinedPayload(rawValue: payload))
        }
      case "menu-event":
        if let menuId = VeloxEventDecoder.string(object["menu_id"]) {
          self = .menuEvent(menuId: menuId)
        } else {
          self = .unknown(json: json)
        }
      case "tray-event":
        let identifier = VeloxEventDecoder.string(object["tray_id"]) ?? ""
        let eventTypeString = VeloxEventDecoder.string(object["event_type"]) ?? "unknown"
        let eventType = TrayEvent.EventType(rawValue: eventTypeString) ?? .unknown
        let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"]))
        let rect = Event.decodeTrayRect(VeloxEventDecoder.dictionary(object["rect"]))
        let button = VeloxEventDecoder.string(object["button"])
        let buttonState = VeloxEventDecoder.string(object["button_state"])
        self = .trayEvent(
          event: TrayEvent(
            identifier: identifier,
            type: eventType,
            button: button,
            buttonState: buttonState,
            position: position,
            rect: rect
          )
        )
      case "raw":
        let description = VeloxEventDecoder.string(object["debug"]) ?? json
        self = .raw(description: description)
      default:
        self = .unknown(json: json)
      }
    }

  private static func decodeSize(_ dictionary: [String: Any]?) -> WindowSize? {
    guard let dictionary else { return nil }
    guard
      let width = VeloxEventDecoder.double(dictionary["width"]),
      let height = VeloxEventDecoder.double(dictionary["height"])
      else {
        return nil
      }
      return WindowSize(width: width, height: height)
    }

  private static func decodePosition(_ dictionary: [String: Any]?) -> WindowPosition? {
    guard let dictionary else { return nil }
    guard
      let x = VeloxEventDecoder.double(dictionary["x"]),
      let y = VeloxEventDecoder.double(dictionary["y"])
    else {
      return nil
    }
    return WindowPosition(x: x, y: y)
  }

  private static func decodeTrayRect(_ dictionary: [String: Any]?) -> TrayRect? {
    guard
      let dictionary,
      let x = VeloxEventDecoder.double(dictionary["x"]),
      let y = VeloxEventDecoder.double(dictionary["y"]),
      let width = VeloxEventDecoder.double(dictionary["width"]),
      let height = VeloxEventDecoder.double(dictionary["height"])
    else {
      return nil
    }
    return TrayRect(
      origin: WindowPosition(x: x, y: y),
      size: WindowSize(width: width, height: height)
    )
  }
  }
}

public extension VeloxRuntimeWry {
  enum WindowEvent: Sendable, Equatable {
    case closeRequested(label: String)
    case destroyed(label: String)
    case resized(label: String, size: WindowSize)
    case moved(label: String, position: WindowPosition)
    case focused(label: String, isFocused: Bool)
    case scaleFactorChanged(label: String, scaleFactor: Double, size: WindowSize)
    case keyboardInput(label: String, input: KeyboardInput)
    case imeText(label: String, text: String)
    case modifiersChanged(label: String, modifiers: Modifiers)
    case cursorMoved(label: String, position: WindowPosition)
    case cursorEntered(label: String, deviceId: String)
    case cursorLeft(label: String, deviceId: String)
    case mouseInput(label: String, input: MouseInput)
    case mouseWheel(label: String, delta: MouseWheelDelta, phase: String)
    case droppedFile(label: String, path: String)
    case hoveredFile(label: String, path: String)
    case hoveredFileCancelled(label: String)
    case themeChanged(label: String, theme: String)
    case raw(label: String, description: String)
    case redrawRequested(label: String)
    case other(label: String, event: VeloxRuntimeWry.Event)
  }

  enum WebviewEvent: Sendable, Equatable {
    case userEvent(label: String, description: String)
    case other(label: String, event: VeloxRuntimeWry.Event)
  }

  static func makeWindowEvent(label: String, event: VeloxRuntimeWry.Event) -> WindowEvent {
    switch event {
    case .windowCloseRequested:
      return .closeRequested(label: label)
    case .windowDestroyed:
      return .destroyed(label: label)
    case .windowResized(_, let size):
      return .resized(label: label, size: size)
    case .windowMoved(_, let position):
      return .moved(label: label, position: position)
    case .windowFocused(_, let isFocused):
      return .focused(label: label, isFocused: isFocused)
    case .windowScaleFactorChanged(_, let scaleFactor, let size):
      return .scaleFactorChanged(label: label, scaleFactor: scaleFactor, size: size)
    case .windowKeyboardInput(_, let input):
      return .keyboardInput(label: label, input: input)
    case .windowImeText(_, let text):
      return .imeText(label: label, text: text)
    case .windowModifiersChanged(_, let modifiers):
      return .modifiersChanged(label: label, modifiers: modifiers)
    case .windowCursorMoved(_, let position):
      return .cursorMoved(label: label, position: position)
    case .windowCursorEntered(_, let deviceId):
      return .cursorEntered(label: label, deviceId: deviceId)
    case .windowCursorLeft(_, let deviceId):
      return .cursorLeft(label: label, deviceId: deviceId)
    case .windowMouseInput(_, let input):
      return .mouseInput(label: label, input: input)
    case .windowMouseWheel(_, let delta, let phase):
      return .mouseWheel(label: label, delta: delta, phase: phase)
    case .windowDroppedFile(_, let path):
      return .droppedFile(label: label, path: path)
    case .windowHoveredFile(_, let path):
      return .hoveredFile(label: label, path: path)
    case .windowHoveredFileCancelled:
      return .hoveredFileCancelled(label: label)
    case .windowThemeChanged(_, let theme):
      return .themeChanged(label: label, theme: theme)
    case .windowEvent(_, let description):
      return .raw(label: label, description: description)
    case .windowRedrawRequested:
      return .redrawRequested(label: label)
    default:
      return .other(label: label, event: event)
    }
  }

  static func makeWebviewEvent(label: String, event: VeloxRuntimeWry.Event) -> WebviewEvent {
    switch event {
    case .webviewEvent(_, let description):
      return .userEvent(label: label, description: description)
    default:
      return .other(label: label, event: event)
    }
  }

  enum MenuEvent: Sendable, Equatable {
    case activated(identifier: String)
    case other(identifier: String, event: VeloxRuntimeWry.Event)
  }

  struct TrayEventNotification: Sendable, Equatable {
    public let identifier: String
    public let event: TrayEvent

    public init(identifier: String, event: TrayEvent) {
      self.identifier = identifier
      self.event = event
    }
  }
}

private enum VeloxEventDecoder {
  static func string(_ value: Any?) -> String? {
    if let string = value as? String {
      return string
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  static func double(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  static func bool(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
      return bool
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    if let string = value as? String {
      switch string.lowercased() {
      case "true", "1", "yes", "y":
        return true
      case "false", "0", "no", "n":
        return false
      default:
        return nil
      }
    }
    return nil
  }

  static func dictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  static func array(_ value: Any?) -> [Any]? {
    value as? [Any]
  }
}

extension VeloxRuntimeWry.Runtime: VeloxRuntimeHandle {
  public typealias WindowDispatcher = VeloxRuntimeWry.Window
  public typealias WebviewDispatcher = VeloxRuntimeWry.Webview
}

extension VeloxRuntimeWry.Window: VeloxWindowDispatcher {
  public typealias Event = VeloxRuntimeWry.Event
  public typealias Identifier = ObjectIdentifier
}

extension VeloxRuntimeWry.Webview: VeloxWebviewDispatcher {
  public typealias Event = VeloxRuntimeWry.Event
  public typealias Identifier = ObjectIdentifier
}

extension VeloxRuntimeWry.Event: VeloxUserEvent {}

public final class EventLoopProxyAdapter: VeloxEventLoopProxy {
  public typealias Event = VeloxRuntimeWry.Event

  private let proxy: VeloxRuntimeWry.EventLoopProxy

  init(proxy: VeloxRuntimeWry.EventLoopProxy) {
    self.proxy = proxy
  }

  public func send(event: VeloxRuntimeWry.Event) throws {
    switch event {
    case .userExit, .exitRequested(_):
      guard proxy.requestExit() else {
        throw VeloxRuntimeError.failed(description: "failed to signal event loop")
      }
    case .userDefined(let payload):
      guard proxy.sendUserEvent(payload.rawValue) else {
        throw VeloxRuntimeError.failed(description: "failed to send user event")
      }
    default:
      throw VeloxRuntimeError.unsupported
    }
  }

  public func sendUserEvent<T: Encodable>(
    _ payload: T,
    encoder: JSONEncoder = JSONEncoder()
  ) throws {
    let encoded = try VeloxRuntimeWry.UserDefinedPayload(encoding: payload, encoder: encoder)
    try send(event: .userDefined(payload: encoded))
  }
}

#if os(macOS)
public extension VeloxRuntimeWry {
  final class MenuBar: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxMenuBarHandle>
    private var retainedSubmenus: [Submenu] = []

    public let identifier: String

    public init?(identifier: String? = nil) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxMenuBarHandle>? = withOptionalCString(identifier ?? "") { idPointer in
        if let idPointer {
          velox_menu_bar_new_with_id(idPointer)
        } else {
          velox_menu_bar_new()
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_menu_bar_identifier(handle))
    }

    deinit {
      velox_menu_bar_free(raw)
    }

    @discardableResult
    public func append(_ submenu: Submenu) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_menu_bar_append_submenu(raw, submenu.raw) else {
        return false
      }
      retainedSubmenus.append(submenu)
      return true
    }

    @discardableResult
    public func setAsApplicationMenu() -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_menu_bar_set_app_menu(raw)
    }
  }

  final class Submenu: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxSubmenuHandle>
    private var retainedItems: [MenuItem] = []

    public let identifier: String

    public init?(title: String, identifier: String? = nil, isEnabled: Bool = true) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxSubmenuHandle>? = title.withCString { titlePointer in
        withOptionalCString(identifier ?? "") { idPointer in
          if let idPointer {
            velox_submenu_new_with_id(idPointer, titlePointer, isEnabled)
          } else {
            velox_submenu_new(titlePointer, isEnabled)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_submenu_identifier(handle))
    }

    deinit {
      velox_submenu_free(raw)
    }

    @discardableResult
    public func append(_ item: MenuItem) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_submenu_append_item(raw, item.raw) else {
        return false
      }
      retainedItems.append(item)
      return true
    }
  }

  final class MenuItem: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxMenuItemHandle>
    public let identifier: String

    public init?(
      identifier: String? = nil,
      title: String,
      isEnabled: Bool = true,
      accelerator: String? = nil
    ) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxMenuItemHandle>? = title.withCString { titlePointer in
        withOptionalCString(identifier ?? "") { idPointer in
          withOptionalCString(accelerator ?? "") { acceleratorPointer in
            velox_menu_item_new(idPointer, titlePointer, isEnabled, acceleratorPointer)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_menu_item_identifier(handle))
    }

    deinit {
      velox_menu_item_free(raw)
    }

    @discardableResult
    public func setEnabled(_ isEnabled: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_menu_item_set_enabled(raw, isEnabled)
    }
  }

  final class TrayIcon: @unchecked Sendable {
    private let raw: UnsafeMutablePointer<VeloxTrayHandle>

    public let identifier: String

    public init?(
      identifier: String? = nil,
      title: String? = nil,
      tooltip: String? = nil,
      visible: Bool = true,
      showMenuOnLeftClick: Bool = true
    ) {
      guard Thread.isMainThread else {
        return nil
      }

      var config = VeloxTrayConfig(
        identifier: nil,
        title: nil,
        tooltip: nil,
        visible: visible,
        show_menu_on_left_click: showMenuOnLeftClick
      )

      let handle: UnsafeMutablePointer<VeloxTrayHandle>? = withOptionalCString(identifier ?? "") { identifierPointer in
        config.identifier = identifierPointer
        return withOptionalCString(title ?? "") { titlePointer in
          config.title = titlePointer
          return withOptionalCString(tooltip ?? "") { tooltipPointer in
            config.tooltip = tooltipPointer
            return velox_tray_new(&config)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_tray_identifier(handle))
    }

    deinit {
      velox_tray_free(raw)
    }

    @discardableResult
    public func setTitle(_ title: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return withOptionalCString(title ?? "") { pointer in
        velox_tray_set_title(raw, pointer)
      }
    }

    @discardableResult
    public func setTooltip(_ tooltip: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return withOptionalCString(tooltip ?? "") { pointer in
        velox_tray_set_tooltip(raw, pointer)
      }
    }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_visible(raw, visible)
    }

    @discardableResult
    public func setShowMenuOnLeftClick(_ enable: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_show_menu_on_left_click(raw, enable)
    }

    @discardableResult
    public func setMenu(_ menu: MenuBar?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_menu(raw, menu?.raw)
    }
  }
}
#endif

private func decodeMonitorInfo(from pointer: UnsafePointer<CChar>?) -> VeloxRuntimeWry.MonitorInfo? {
  guard let pointer else {
    return nil
  }

  let jsonString = String(cString: pointer)
  guard let data = jsonString.data(using: .utf8),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let monitor = decodeMonitorInfo(dictionary: object)
  else {
    return nil
  }
  return monitor
}

private func decodeMonitorInfoList(from pointer: UnsafePointer<CChar>?) -> [VeloxRuntimeWry.MonitorInfo] {
  guard let pointer else {
    return []
  }

  let jsonString = String(cString: pointer)
  guard let data = jsonString.data(using: .utf8),
    let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
  else {
    return []
  }

  return array.compactMap { element in
    guard let dictionary = element as? [String: Any] else {
      return nil
    }
    return decodeMonitorInfo(dictionary: dictionary)
  }
}

private func decodeMonitorInfo(dictionary: [String: Any]) -> VeloxRuntimeWry.MonitorInfo? {
  guard
    let scaleFactor = VeloxEventDecoder.double(dictionary["scale_factor"]),
    let positionDictionary = VeloxEventDecoder.dictionary(dictionary["position"]),
    let sizeDictionary = VeloxEventDecoder.dictionary(dictionary["size"])
  else {
    return nil
  }

  let position = VeloxRuntimeWry.WindowPosition(
    x: VeloxEventDecoder.double(positionDictionary["x"]) ?? 0,
    y: VeloxEventDecoder.double(positionDictionary["y"]) ?? 0
  )

  let size = VeloxRuntimeWry.WindowSize(
    width: VeloxEventDecoder.double(sizeDictionary["width"]) ?? 0,
    height: VeloxEventDecoder.double(sizeDictionary["height"]) ?? 0
  )

  let name = VeloxEventDecoder.string(dictionary["name"]) ?? ""

  return VeloxRuntimeWry.MonitorInfo(
    name: name,
    position: position,
    size: size,
    scaleFactor: scaleFactor
  )
}

private func string(from pointer: UnsafePointer<CChar>?) -> String {
  guard let pointer else {
    return ""
  }
  return String(cString: pointer)
}

private func withOptionalCString<R>(
  _ string: String,
  perform: (UnsafePointer<CChar>?) -> R
) -> R {
  if string.isEmpty {
    return perform(nil)
  }

  return string.withCString { pointer in
    perform(pointer)
  }
}
