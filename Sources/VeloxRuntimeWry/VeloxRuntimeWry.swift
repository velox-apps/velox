import Foundation
import VeloxRuntimeWryFFI

/// Convenience wrapper around the Rust FFI exported by `velox-runtime-wry-ffi`.
/// This provides a Swift-first surface that mirrors the original Tauri `wry`
/// runtime API naming while renaming public symbols to the Velox domain.
public enum VeloxRuntimeWry {
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
  /// Placeholder runtime shim. The full Swift port is still under construction, so the type currently
  /// reports itself as unavailable to avoid panics from unsupported configurations.
  final class Runtime {
    public init?() {
      return nil
    }

    public func runIteration(_ handler: @escaping @Sendable (Event) -> Void) {
      _ = handler
    }

    @discardableResult
    public func requestExit(code _: Int32 = 0) -> Bool {
      false
    }

    public func createWindow(configuration _: WindowConfiguration? = nil) -> Window? {
      nil
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

    private final class EventLoopCallback {
      let handler: @Sendable (_ event: Event) -> ControlFlow

      init(handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
        self.handler = handler
      }
    }

    private static let callback: @convention(c) (
      UnsafePointer<CChar>?,
      UnsafeMutableRawPointer?
    ) -> VeloxControlFlow = { event, userData in
      guard let userData else {
        return VELOX_CONTROL_FLOW_EXIT
      }

      let box = Unmanaged<EventLoopCallback>.fromOpaque(userData).takeUnretainedValue()
      let json = event.map { String(cString: $0) } ?? "{}"
      let parsedEvent = Event(fromJSON: json)
      let flow = box.handler(parsedEvent)
      return VeloxControlFlow(rawValue: UInt32(flow.rawValue))
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
  }

  /// Handle wrapper mirroring Tao's `Window`.
  final class Window {
    fileprivate let raw: UnsafeMutablePointer<VeloxWindowHandle>

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

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWindowHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_window_free(raw)
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
            return Webview(raw: handle)
          }
        }
      } else {
        guard let handle = velox_webview_build(raw, nil) else {
          return nil
        }
        return Webview(raw: handle)
      }
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      return title.withCString { velox_window_set_title(raw, $0) }
    }

    @discardableResult
    public func setFullscreen(_ isFullscreen: Bool) -> Bool {
      return velox_window_set_fullscreen(raw, isFullscreen)
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

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWebviewHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_webview_free(raw)
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
          self = .unknown(json: json)
        }
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
