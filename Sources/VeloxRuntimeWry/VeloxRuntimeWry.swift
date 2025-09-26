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
  }
}

public extension VeloxRuntimeWry {
  /// Normalised representation of Tao events delivered through the FFI layer.
  enum Event: Sendable, Equatable {
    case newEvents(cause: String)
    case mainEventsCleared
    case redrawEventsCleared
    case loopDestroyed
    case userExit
    case windowCloseRequested(windowId: String)
    case windowResized(windowId: String, width: Double, height: Double)
    case windowMoved(windowId: String, x: Double, y: Double)
    case windowFocused(windowId: String, isFocused: Bool)
    case windowScaleFactorChanged(windowId: String, scaleFactor: Double)
    case windowEvent(windowId: String, description: String)
    case raw(description: String)
    case unknown(json: String)

    init(fromJSON json: String) {
      guard
        let data = json.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let type = object["type"] as? String
      else {
        self = .unknown(json: json)
        return
      }

      switch type {
      case "new-events":
        let cause = object["cause"] as? String ?? "unknown"
        self = .newEvents(cause: cause)
      case "main-events-cleared":
        self = .mainEventsCleared
      case "redraw-events-cleared":
        self = .redrawEventsCleared
      case "loop-destroyed":
        self = .loopDestroyed
      case "user-exit":
        self = .userExit
      case "window-close-requested":
        let id = object["window_id"] as? String ?? ""
        self = .windowCloseRequested(windowId: id)
      case "window-resized":
        let id = object["window_id"] as? String ?? ""
        if
          let size = object["size"] as? [String: Any],
          let width = size["width"] as? Double,
          let height = size["height"] as? Double
        {
          self = .windowResized(windowId: id, width: width, height: height)
        } else {
          self = .windowEvent(windowId: id, description: json)
        }
      case "window-moved":
        let id = object["window_id"] as? String ?? ""
        if
          let position = object["position"] as? [String: Any],
          let x = position["x"] as? Double,
          let y = position["y"] as? Double
        {
          self = .windowMoved(windowId: id, x: x, y: y)
        } else {
          self = .windowEvent(windowId: id, description: json)
        }
      case "window-focused":
        let id = object["window_id"] as? String ?? ""
        let focused = object["focused"] as? Bool ?? false
        self = .windowFocused(windowId: id, isFocused: focused)
      case "window-scale-factor-changed":
        let id = object["window_id"] as? String ?? ""
        if let factor = object["scale_factor"] as? Double {
          self = .windowScaleFactorChanged(windowId: id, scaleFactor: factor)
        } else {
          self = .windowEvent(windowId: id, description: json)
        }
      case "window-event":
        let id = object["window_id"] as? String ?? ""
        let kind = object["kind"] as? String ?? ""
        self = .windowEvent(windowId: id, description: kind)
      case "raw":
        let debug = object["debug"] as? String ?? json
        self = .raw(description: debug)
      default:
        self = .unknown(json: json)
      }
    }
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
