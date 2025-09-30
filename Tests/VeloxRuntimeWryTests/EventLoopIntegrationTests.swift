import Foundation
import XCTest
#if canImport(AppKit)
import AppKit
#endif

private enum EventLoopHolder {
  static var instance: VeloxRuntimeWry.EventLoop?

  enum Error: Swift.Error {
    case unavailable
  }

  static func shared() throws -> VeloxRuntimeWry.EventLoop {
    if let existing = instance {
      return existing
    }

#if canImport(AppKit)
    AppKitHost.prepareIfNeeded()
#endif

    guard let loop = VeloxRuntimeWry.EventLoop() else {
      throw Error.unavailable
    }

#if canImport(AppKit)
    AppKitHost.finishLaunchingIfNeeded()
#endif

    instance = loop
    return loop
  }

  static func reset() {
    instance?.shutdown()
    instance = nil
  }
}
@testable import VeloxRuntimeWry

final class EventLoopIntegrationTests: XCTestCase {
  override class func tearDown() {
    EventLoopHolder.reset()
    super.tearDown()
  }

  func testPumpReceivesAtLeastOneEvent() throws {
#if canImport(AppKit)
    if ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] != "1" {
      throw XCTSkip("UI integration tests disabled")
    }
    AppKitHost.prepareIfNeeded()
#else
    throw XCTSkip("UI integration tests unavailable on this platform")
#endif

    final class EventAccumulator: @unchecked Sendable {
      var events: [VeloxRuntimeWry.Event] = []
    }

    let accumulator = EventAccumulator()
    var skipReason: String?

    do {
      try runOnMain {
        let loop = try EventLoopHolder.shared()

        guard let window = loop.makeWindow(configuration: .init(width: 640, height: 480, title: "Integration")) else {
          skipReason = "Window creation not supported in this environment"
          return
        }

        guard let webview = window.makeWebview(configuration: .init(url: "https://tauri.app")) else {
          skipReason = "Webview creation not supported in this environment"
          return
        }

        _ = window.setTitle("Integration Window")
        _ = window.setSize(width: 640, height: 480)
        _ = window.setPosition(x: 10, y: 10)
        _ = window.setMinimumSize(width: 320, height: 240)
        _ = window.setMaximumSize(width: 1280, height: 720)
        _ = window.setDecorations(true)
        _ = window.setResizable(true)
        _ = window.setAlwaysOnTop(false)
        _ = window.setAlwaysOnBottom(false)
        _ = window.setVisibleOnAllWorkspaces(false)
        _ = window.setContentProtected(false)
        _ = window.setVisible(true)
        _ = window.focus()
        _ = window.setFocusable(true)
        _ = window.requestRedraw()
        _ = window.requestUserAttention(.informational)
        _ = window.clearUserAttention()
        _ = window.startDragging()
        _ = window.startResizeDragging(.south)
        _ = window.setCursorGrab(false)
        _ = window.setCursorVisible(true)
        _ = window.setCursorPosition(x: 20, y: 20)
        _ = window.setIgnoreCursorEvents(false)

        _ = webview.navigate(to: "https://tauri.app")
        _ = webview.reload()
        _ = webview.evaluate(script: "1 + 1;")
        _ = webview.setZoom(1.0)
        _ = webview.hide()
        _ = webview.show()
        _ = webview.clearBrowsingData()

        loop.pump { event in
          accumulator.events.append(event)
          return .exit
        }
      }
    } catch EventLoopHolder.Error.unavailable {
      throw XCTSkip("Velox event loop unavailable on this platform")
    }

    if let reason = skipReason {
      EventLoopHolder.reset()
      throw XCTSkip(reason)
    }

    XCTAssertFalse(accumulator.events.isEmpty)
  }

  func testProxySendsUserEvent() throws {
#if canImport(AppKit)
    if ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] == "1" {
      AppKitHost.prepareIfNeeded()
    }
#endif

    final class EventState: @unchecked Sendable {
      var sawUserEvent = false
      var iterations = 0
    }

    let state = EventState()
    var skipReason: String?

    do {
      try runOnMain {
        let loop = try EventLoopHolder.shared()

        guard let proxy = loop.makeProxy() else {
          skipReason = "Failed to create event loop proxy"
          return
        }

        struct Payload: Codable, Equatable {
          let action: String
          let value: Int
        }

        let expectedPayload = Payload(action: "ping", value: 42)
        XCTAssertTrue(proxy.sendUserEvent(expectedPayload))

        loop.pump { event in
          state.iterations += 1
          if case .userDefined(let payload) = event,
            let decoded: Payload = payload.decode(Payload.self),
            decoded == expectedPayload
          {
            state.sawUserEvent = true
            return .exit
          }
          if state.iterations > 100 {
            return .exit
          }
          return .poll
        }
      }
    } catch EventLoopHolder.Error.unavailable {
      throw XCTSkip("Velox event loop unavailable on this platform")
    }

    if let reason = skipReason {
      EventLoopHolder.reset()
      throw XCTSkip(reason)
    }
  
    XCTAssertTrue(state.sawUserEvent, "User event payload was never observed")
  }
}
