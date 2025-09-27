import XCTest
@testable import VeloxRuntimeWry

final class EventLoopIntegrationTests: XCTestCase {
  func testPumpReceivesAtLeastOneEvent() {
    guard let loop = VeloxRuntimeWry.EventLoop() else {
      XCTFail("Unable to create VeloxRuntimeWry.EventLoop")
      return
    }

    final class EventAccumulator: @unchecked Sendable {
      var events: [VeloxRuntimeWry.Event] = []
    }

    let accumulator = EventAccumulator()
    guard let window = loop.makeWindow(configuration: .init(width: 640, height: 480, title: "Integration")) else {
      XCTFail("Failed to create window")
      return
    }

    guard let webview = window.makeWebview(configuration: .init(url: "https://tauri.app")) else {
      XCTFail("Failed to create webview")
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
    _ = window.setSkipTaskbar(false)
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

    XCTAssertFalse(accumulator.events.isEmpty)
  }
}
