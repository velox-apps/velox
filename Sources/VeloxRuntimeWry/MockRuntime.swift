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
    private var windowStreams: [UUID: VeloxEventStreamMultiplexer<VeloxRuntimeWry.WindowEvent>] = [:]
    private var webviewStreams: [UUID: VeloxEventStreamMultiplexer<VeloxRuntimeWry.WebviewEvent>] = [:]
    private let menuStream = VeloxEventStreamMultiplexer<VeloxRuntimeWry.MenuEvent>()
    private let trayStream = VeloxEventStreamMultiplexer<VeloxRuntimeWry.TrayEventNotification>()
    private var webviewOwners: [UUID: UUID] = [:]
    private let monitors: [VeloxRuntimeWry.MonitorInfo] = [
      VeloxRuntimeWry.MonitorInfo(
        name: "MockDisplay",
        position: VeloxRuntimeWry.WindowPosition(x: 0, y: 0),
        size: VeloxRuntimeWry.WindowSize(width: 1920, height: 1080),
        scaleFactor: 2.0
      )
    ]

    public init() {}

    deinit {
      let (windowSinks, webviewSinks): ([VeloxEventStreamMultiplexer<VeloxRuntimeWry.WindowEvent>], [VeloxEventStreamMultiplexer<VeloxRuntimeWry.WebviewEvent>]) = withLock {
        let window = Array(windowStreams.values)
        let webview = Array(webviewStreams.values)
        windowStreams.removeAll()
        webviewStreams.removeAll()
        return (window, webview)
      }
      windowSinks.forEach { $0.finishAll() }
      webviewSinks.forEach { $0.finishAll() }
      menuStream.finishAll()
      trayStream.finishAll()
    }

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

    public func menuEvents(
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.MenuEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<VeloxRuntimeWry.MenuEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = menuStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.menuStream.remove(token)
        }
      }
    }

    public func trayEvents(
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.TrayEventNotification>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<VeloxRuntimeWry.TrayEventNotification> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = trayStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.trayStream.remove(token)
        }
      }
    }

    fileprivate func currentMonitor() -> VeloxRuntimeWry.MonitorInfo? { monitors.first }

    fileprivate func primaryMonitor() -> VeloxRuntimeWry.MonitorInfo? { monitors.first }

    fileprivate func availableMonitors() -> [VeloxRuntimeWry.MonitorInfo] { monitors }

    fileprivate func monitor(from _: VeloxRuntimeWry.WindowPosition) -> VeloxRuntimeWry.MonitorInfo? { monitors.first }

    fileprivate func attach(webview: Webview, to identifier: UUID) {
      withLock {
        guard var state = windows[identifier] else {
          return
        }
        state.webview = webview
        windows[identifier] = state
        webviewOwners[webview.id] = identifier
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
      let event = VeloxRuntimeWry.Event.windowEvent(windowId: label, description: "mock")
      emitWindowEvent(label: label, event: event)
      enqueueRunEvent(VeloxRunEvent<Event>.windowEvent(label: label))
    }

    fileprivate func enqueueWebviewEvent(label: String) {
      let event = VeloxRuntimeWry.Event.webviewEvent(label: label, description: "mock")
      emitWebviewEvent(label: label, event: event)
      enqueueRunEvent(VeloxRunEvent<Event>.webviewEvent(label: label))
    }

    func emitWindowEvent(label: String, event: VeloxRuntimeWry.Event) {
      guard let identifier = windowIdentifier(forLabel: label) else {
        return
      }
      let sink = withLock { windowStreams[identifier] }
      if let sink {
        sink.yield(VeloxRuntimeWry.makeWindowEvent(label: label, event: event))
      }
    }

    func emitWebviewEvent(label: String, event: VeloxRuntimeWry.Event) {
      guard let identifier = windowIdentifier(forLabel: label) else {
        return
      }
      let sink = withLock { webviewStreams[identifier] }
      if let sink {
        sink.yield(VeloxRuntimeWry.makeWebviewEvent(label: label, event: event))
      }
    }

    func emitMenuEvent(identifier: String) {
      menuStream.yield(.activated(identifier: identifier))
    }

    func emitTrayEvent(_ event: VeloxRuntimeWry.TrayEvent) {
      trayStream.yield(VeloxRuntimeWry.TrayEventNotification(identifier: event.identifier, event: event))
    }

    fileprivate func windowEventStream(
      for identifier: UUID,
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.WindowEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<VeloxRuntimeWry.WindowEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token: UUID = withLock {
          let sink = windowStreams[identifier] ?? VeloxEventStreamMultiplexer<VeloxRuntimeWry.WindowEvent>()
          let token = sink.add(continuation)
          windowStreams[identifier] = sink
          return token
        }

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.withLock {
            if let sink = self.windowStreams[identifier] {
              sink.remove(token)
              if sink.isEmpty {
                self.windowStreams.removeValue(forKey: identifier)
              }
            }
          }
        }
      }
    }

    fileprivate func webviewEventStream(
      forWebview identifier: UUID,
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.WebviewEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<VeloxRuntimeWry.WebviewEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        guard let windowIdentifier = withLock({ webviewOwners[identifier] }) else {
          continuation.finish()
          return
        }

        let token: UUID = withLock {
          let sink = webviewStreams[windowIdentifier] ?? VeloxEventStreamMultiplexer<VeloxRuntimeWry.WebviewEvent>()
          let token = sink.add(continuation)
          webviewStreams[windowIdentifier] = sink
          return token
        }

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.withLock {
            guard let windowIdentifier = self.webviewOwners[identifier],
              let sink = self.webviewStreams[windowIdentifier]
            else {
              return
            }
            sink.remove(token)
            if sink.isEmpty {
              self.webviewStreams.removeValue(forKey: windowIdentifier)
            }
          }
        }
      }
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

    private var windowTitle: String
    private var size: (width: Double, height: Double)?
    private var position: (x: Double, y: Double)?
    private var minSize: (width: Double, height: Double)?
    private var maxSize: (width: Double, height: Double)?
    private var fullscreen = false
    private var maximized = false
    private var minimized = false
    private var decorations = true
    private var resizable = true
    private var alwaysOnTop = false
    private var alwaysOnBottom = false
    private var visibleOnAllWorkspaces = false
    private var contentProtected = false
    private var visible = true
    private var focused = false
    private var isFocusable = true
    private var minimizable = true
    private var maximizable = true
    private var closable = true
    private var cursorGrab = false
    private var cursorVisible = true
    private var cursorLocation: (x: Double, y: Double)?
    private var ignoreCursorEvents = false
    private var skipTaskbar = false
    private var backgroundColor: VeloxRuntimeWry.Window.Color?
    private var theme: VeloxRuntimeWry.Window.Theme?

    fileprivate init(id: UUID, label: String, runtime: VeloxRuntimeWry.MockRuntime) {
      self.id = id
      self.label = label
      self.runtime = runtime
      self.windowTitle = label
    }

    fileprivate func apply(configuration: VeloxRuntimeWry.WindowConfiguration) {
      size = (Double(configuration.width), Double(configuration.height))
      windowTitle = configuration.title
    }

    public func makeWebview(configuration _: VeloxRuntimeWry.WebviewConfiguration? = nil) -> Webview? {
      let webview = Webview(id: id, runtime: runtime)
      runtime.attach(webview: webview, to: id)
      return webview
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      self.windowTitle = title
      return true
    }

    @discardableResult
    public func setFullscreen(_ fullscreen: Bool) -> Bool {
      self.fullscreen = fullscreen
      return true
    }

    @discardableResult
    public func setMaximized(_ maximized: Bool) -> Bool {
      self.maximized = maximized
      if maximized {
        self.minimized = false
      }
      return true
    }

    @discardableResult
    public func setMinimized(_ minimized: Bool) -> Bool {
      self.minimized = minimized
      if minimized {
        self.maximized = false
      }
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
    public func setMinimizable(_ minimizable: Bool) -> Bool {
      self.minimizable = minimizable
      return true
    }

    @discardableResult
    public func setMaximizable(_ maximizable: Bool) -> Bool {
      self.maximizable = maximizable
      return true
    }

    @discardableResult
    public func setClosable(_ closable: Bool) -> Bool {
      self.closable = closable
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
      self.visible = visible
      return true
    }

    @discardableResult
    public func setSkipTaskbar(_ skip: Bool) -> Bool {
      skipTaskbar = skip
      return true
    }

    @discardableResult
    public func focus() -> Bool {
      focused = true
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
      cursorLocation = (x, y)
      return true
    }

    @discardableResult
    public func setIgnoreCursorEvents(_ ignore: Bool) -> Bool {
      ignoreCursorEvents = ignore
      return true
    }

    @discardableResult
    public func setBackgroundColor(_ color: VeloxRuntimeWry.Window.Color?) -> Bool {
      backgroundColor = color
      return true
    }

    @discardableResult
    public func setTheme(_ theme: VeloxRuntimeWry.Window.Theme?) -> Bool {
      self.theme = theme
      return true
    }

    public func title() -> String { windowTitle }

    public func isFullscreen() -> Bool { fullscreen }

    public func isMaximized() -> Bool { maximized }

    public func isMinimized() -> Bool { minimized }

    public func isVisible() -> Bool { visible }

    public func isResizable() -> Bool { resizable }

    public func isDecorated() -> Bool { decorations }

    public func isAlwaysOnTop() -> Bool { alwaysOnTop }

    public func isMinimizable() -> Bool { minimizable }

    public func isMaximizable() -> Bool { maximizable }

    public func isClosable() -> Bool { closable }

    public func currentMonitor() -> VeloxRuntimeWry.MonitorInfo? { runtime.currentMonitor() }

    public func primaryMonitor() -> VeloxRuntimeWry.MonitorInfo? { runtime.primaryMonitor() }

    public func availableMonitors() -> [VeloxRuntimeWry.MonitorInfo] { runtime.availableMonitors() }

    public func monitor(at position: VeloxRuntimeWry.WindowPosition) -> VeloxRuntimeWry.MonitorInfo? {
      runtime.monitor(from: position)
    }

    public func isFocused() -> Bool { focused }

    public func scaleFactor() -> Double? {
      runtime.currentMonitor()?.scaleFactor
    }

    public func innerPosition() -> VeloxRuntimeWry.WindowPosition? {
      guard let position else {
        return nil
      }
      return VeloxRuntimeWry.WindowPosition(x: position.x, y: position.y)
    }

    public func outerPosition() -> VeloxRuntimeWry.WindowPosition? {
      innerPosition()
    }

    public func innerSize() -> VeloxRuntimeWry.WindowSize? {
      guard let size else {
        return nil
      }
      return VeloxRuntimeWry.WindowSize(width: size.width, height: size.height)
    }

    public func outerSize() -> VeloxRuntimeWry.WindowSize? {
      innerSize()
    }

    public func cursorPosition() -> VeloxRuntimeWry.WindowPosition? {
      guard let position = cursorLocation else {
        return nil
      }
      return VeloxRuntimeWry.WindowPosition(x: position.x, y: position.y)
    }

    public func events(
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.WindowEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<VeloxRuntimeWry.WindowEvent> {
      runtime.windowEventStream(for: id, bufferingPolicy: bufferingPolicy)
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

    public func events(
      bufferingPolicy: AsyncStream<VeloxRuntimeWry.WebviewEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<VeloxRuntimeWry.WebviewEvent> {
      runtime.webviewEventStream(forWebview: id, bufferingPolicy: bufferingPolicy)
    }
  }
}

extension VeloxRuntimeWry.MockRuntime: VeloxRuntimeHandle {}
