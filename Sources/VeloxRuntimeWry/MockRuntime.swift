import Foundation
import VeloxRuntime

extension VeloxRuntimeWry {
  /// Lightweight Swift-only runtime used by unit tests. It mirrors the public
  /// API of the Wry-backed runtime but keeps all state in memory so tests never
  /// have to touch Tao/AppKit.
  public final class MockRuntime: VeloxRuntime {
    public typealias Event = VeloxRuntimeWry.Event
    public typealias Handle = MockRuntime
    public typealias EventLoopProxyType = MockEventLoopProxy

    private struct WindowState {
      let id: UUID
      let label: String
      let window: Window
      var webview: Webview?
    }

    private let lock = NSLock()
    private var windows: [UUID: WindowState] = [:]
    private var windowsByLabel: [String: UUID] = [:]
    private var queuedEvents: [VeloxRunEvent<Event>] = []
    private var readyDelivered = false
    private var pendingExitCode: Int32?
    private var windowIndex: UInt = 0

    public init() {}

    public static func make(args _: VeloxRuntimeInitArgs) throws -> MockRuntime {
      MockRuntime()
    }

    public func handle() -> MockRuntime { self }

    public func createProxy() throws -> MockEventLoopProxy {
      MockEventLoopProxy(runtime: self)
    }

    public func createWindow(
      pending: VeloxPendingWindow<Event>
    ) throws -> VeloxDetachedWindow<Event, Window, Webview> {
      registerWindow(label: pending.label)
    }

    public func createWebview(
      window identifier: UUID,
      pending _: VeloxPendingWebview<Event>
    ) throws -> Webview {
      guard let state = withLock({ windows[identifier] }) else {
        throw VeloxRuntimeError.failed(description: "window not found")
      }

      let webview = Webview(id: identifier, runtime: self)
      withLock {
        var updated = state
        updated.webview = webview
        windows[identifier] = updated
      }
      return webview
    }

    public func runIteration(
      handler: @Sendable @escaping (VeloxRunEvent<Event>) -> VeloxControlFlow
    ) {
      let events = dequeueEvents()
      for event in events {
        let flow = handler(event)
        if flow == .exit {
          break
        }
      }
    }

    public func requestExit(code: Int32) throws {
      withLock {
        pendingExitCode = code
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
      let resolvedLabel = label ?? configuration?.title ?? makeDefaultLabel()
      let detached = registerWindow(label: resolvedLabel)
      if let configuration {
        detached.dispatcher.apply(configuration: configuration)
      }
      return detached
    }

    public func windowIdentifier(forLabel label: String) -> UUID? {
      withLock { windowsByLabel[label] }
    }

    public func window(for label: String) -> Window? {
      withLock {
        guard let identifier = windowsByLabel[label] else {
          return nil
        }
        return windows[identifier]?.window
      }
    }

    fileprivate func attach(webview: Webview, to identifier: UUID) {
      withLock {
        guard var state = windows[identifier] else {
          return
        }
        state.webview = webview
        windows[identifier] = state
      }
    }

    fileprivate func enqueueRunEvent(_ event: VeloxRunEvent<Event>) {
      withLock {
        queuedEvents.append(event)
      }
    }

    fileprivate func enqueueUserEvent(_ event: Event) {
      enqueueRunEvent(VeloxRunEvent<Event>.userEvent(event))
    }

    fileprivate func enqueueRaw(description: String) {
      enqueueRunEvent(VeloxRunEvent<Event>.raw(description: description))
    }

    fileprivate func enqueueWindowEvent(label: String) {
      enqueueRunEvent(VeloxRunEvent<Event>.windowEvent(label: label))
    }

    fileprivate func enqueueWebviewEvent(label: String) {
      enqueueRunEvent(VeloxRunEvent<Event>.webviewEvent(label: label))
    }

    private func registerWindow(
      label: String
    ) -> VeloxDetachedWindow<Event, Window, Webview> {
      let id = UUID()
      let window = Window(id: id, label: label, runtime: self)
      let state = WindowState(id: id, label: label, window: window, webview: nil)
      withLock {
        windows[id] = state
        windowsByLabel[label] = id
      }
      return VeloxDetachedWindow(id: id, label: label, dispatcher: window, webview: nil)
    }

    private func makeDefaultLabel() -> String {
      withLock {
        windowIndex += 1
        return "window-\(windowIndex)"
      }
    }

    private func dequeueEvents() -> [VeloxRunEvent<Event>] {
      withLock {
        var events: [VeloxRunEvent<Event>] = []
        if !readyDelivered {
          readyDelivered = true
          events.append(.ready)
        }
        events.append(contentsOf: queuedEvents)
        queuedEvents.removeAll()
        if let exitCode = pendingExitCode {
          events.append(.exitRequested(code: exitCode))
          events.append(.exit)
          pendingExitCode = nil
        }
        return events
      }
    }

    private func withLock<R>(_ work: () -> R) -> R {
      lock.lock()
      defer { lock.unlock() }
      return work()
    }
  }
}

extension VeloxRuntimeWry.MockRuntime {
  public final class MockEventLoopProxy: VeloxEventLoopProxy {
    public typealias Event = VeloxRuntimeWry.Event

    private weak var runtime: VeloxRuntimeWry.MockRuntime?

    fileprivate init(runtime: VeloxRuntimeWry.MockRuntime) {
      self.runtime = runtime
    }

    public func send(event: Event) throws {
      runtime?.enqueueUserEvent(event)
    }

    @discardableResult
    public func sendUserEvent<T: Codable & Sendable>(
      _ payload: T,
      encoder: JSONEncoder = JSONEncoder()
    ) -> Bool {
      guard let data = try? encoder.encode(payload),
        let json = String(data: data, encoding: .utf8)
      else {
        return false
      }
      runtime?.enqueueRaw(description: json)
      return true
    }
  }
}

extension VeloxRuntimeWry.MockRuntime {
  public final class Window: VeloxWindowDispatcher {
    public typealias Event = VeloxRuntimeWry.Event
    public typealias Identifier = UUID

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

    private unowned let runtime: VeloxRuntimeWry.MockRuntime
    public let id: UUID
    public let label: String

    private var title: String
    private var size: (width: Double, height: Double)?
    private var position: (x: Double, y: Double)?
    private var minSize: (width: Double, height: Double)?
    private var maxSize: (width: Double, height: Double)?
    private var isFullscreen = false
    private var decorations = true
    private var resizable = true
    private var alwaysOnTop = false
    private var alwaysOnBottom = false
    private var visibleOnAllWorkspaces = false
    private var contentProtected = false
    private var isVisible = true
    private var isFocused = false
    private var isFocusable = true
    private var cursorGrab = false
    private var cursorVisible = true
    private var cursorPosition: (x: Double, y: Double)?
    private var ignoreCursorEvents = false

    fileprivate init(id: UUID, label: String, runtime: VeloxRuntimeWry.MockRuntime) {
      self.id = id
      self.label = label
      self.runtime = runtime
      self.title = label
    }

    fileprivate func apply(configuration: VeloxRuntimeWry.WindowConfiguration) {
      size = (Double(configuration.width), Double(configuration.height))
      title = configuration.title
    }

    public func makeWebview(configuration _: VeloxRuntimeWry.WebviewConfiguration? = nil) -> Webview? {
      let webview = Webview(id: id, runtime: runtime)
      runtime.attach(webview: webview, to: id)
      return webview
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      self.title = title
      return true
    }

    @discardableResult
    public func setFullscreen(_ isFullscreen: Bool) -> Bool {
      self.isFullscreen = isFullscreen
      return true
    }

    @discardableResult
    public func setDecorations(_ decorations: Bool) -> Bool {
      self.decorations = decorations
      return true
    }

    @discardableResult
    public func setResizable(_ resizable: Bool) -> Bool {
      self.resizable = resizable
      return true
    }

    @discardableResult
    public func setAlwaysOnTop(_ onTop: Bool) -> Bool {
      alwaysOnTop = onTop
      return true
    }

    @discardableResult
    public func setAlwaysOnBottom(_ onBottom: Bool) -> Bool {
      alwaysOnBottom = onBottom
      return true
    }

    @discardableResult
    public func setVisibleOnAllWorkspaces(_ visible: Bool) -> Bool {
      visibleOnAllWorkspaces = visible
      return true
    }

    @discardableResult
    public func setContentProtected(_ protected: Bool) -> Bool {
      contentProtected = protected
      return true
    }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
      isVisible = visible
      return true
    }

    @discardableResult
    public func focus() -> Bool {
      isFocused = true
      return true
    }

    @discardableResult
    public func setFocusable(_ focusable: Bool) -> Bool {
      isFocusable = focusable
      return true
    }

    @discardableResult
    public func requestRedraw() -> Bool {
      runtime.enqueueWindowEvent(label: label)
      return true
    }

    @discardableResult
    public func setSize(width: Double, height: Double) -> Bool {
      size = (width, height)
      return true
    }

    @discardableResult
    public func setPosition(x: Double, y: Double) -> Bool {
      position = (x, y)
      return true
    }

    @discardableResult
    public func setMinimumSize(width: Double, height: Double) -> Bool {
      minSize = (width, height)
      return true
    }

    @discardableResult
    public func setMaximumSize(width: Double, height: Double) -> Bool {
      maxSize = (width, height)
      return true
    }

    @discardableResult
    public func requestUserAttention(_ type: AttentionType) -> Bool {
      let _ = type
      runtime.enqueueWindowEvent(label: label)
      return true
    }

    @discardableResult
    public func clearUserAttention() -> Bool { true }

    @discardableResult
    public func startDragging() -> Bool { true }

    @discardableResult
    public func startResizeDragging(_ direction: ResizeDirection) -> Bool {
      let _ = direction
      runtime.enqueueWindowEvent(label: label)
      return true
    }

    @discardableResult
    public func setCursorGrab(_ grab: Bool) -> Bool {
      cursorGrab = grab
      return true
    }

    @discardableResult
    public func setCursorVisible(_ visible: Bool) -> Bool {
      cursorVisible = visible
      return true
    }

    @discardableResult
    public func setCursorPosition(x: Double, y: Double) -> Bool {
      cursorPosition = (x, y)
      return true
    }

    @discardableResult
    public func setIgnoreCursorEvents(_ ignore: Bool) -> Bool {
      ignoreCursorEvents = ignore
      return true
    }
  }
}

extension VeloxRuntimeWry.MockRuntime {
  public final class Webview: VeloxWebviewDispatcher {
    public typealias Event = VeloxRuntimeWry.Event
    public typealias Identifier = UUID

    private unowned let runtime: VeloxRuntimeWry.MockRuntime
    public let id: UUID
    private var currentURL: String = ""
    private var zoomLevel: Double = 1.0
    private var hidden = false
    private var lastEvaluatedScript: String?

    fileprivate init(id: UUID, runtime: VeloxRuntimeWry.MockRuntime) {
      self.id = id
      self.runtime = runtime
    }

    @discardableResult
    public func navigate(to url: String) -> Bool {
      currentURL = url
      runtime.enqueueWebviewEvent(label: url)
      return true
    }

    @discardableResult
    public func reload() -> Bool { true }

    @discardableResult
    public func evaluate(script: String) -> Bool {
      lastEvaluatedScript = script
      return true
    }

    @discardableResult
    public func setZoom(_ scaleFactor: Double) -> Bool {
      zoomLevel = scaleFactor
      return true
    }

    @discardableResult
    public func hide() -> Bool {
      hidden = true
      return true
    }

    @discardableResult
    public func show() -> Bool {
      hidden = false
      return true
    }

    @discardableResult
    public func clearBrowsingData() -> Bool { true }
  }
}

extension VeloxRuntimeWry.MockRuntime: VeloxRuntimeHandle {}
