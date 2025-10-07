import XCTest
import VeloxRuntime
@testable import VeloxRuntimeWry

private enum RuntimeHolder {
  static var runtime: VeloxRuntimeWry.MockRuntime?

  static func shared() throws -> VeloxRuntimeWry.MockRuntime {
    if let runtime {
      return runtime
    }
    let created = VeloxRuntimeWry.MockRuntime()
    runtime = created
    return created
  }

  static func reset() {
    runtime = nil
  }
}

final class RuntimeTests: XCTestCase {
  override class func tearDown() {
    RuntimeHolder.reset()
    super.tearDown()
  }

  func testRuntimeIterationProducesEvents() throws {
    let runtime = try RuntimeHolder.shared()

    final class EventAccumulator: @unchecked Sendable {
      var events: [VeloxRunEvent<VeloxRuntimeWry.Event>] = []
    }

    let accumulator = EventAccumulator()
    runtime.runIteration { event in
      accumulator.events.append(event)
      return .exit
    }

    XCTAssertFalse(accumulator.events.isEmpty)
    XCTAssertTrue(accumulator.events.contains { runEvent in
      if case .ready = runEvent {
        return true
      }
      return false
    })
  }

  func testRuntimeCreatesWindowAndWebview() throws {
    let runtime = try RuntimeHolder.shared()

    let detachedWindow = try runtime.createWindow(
      configuration: .init(width: 320, height: 240, title: "Runtime Window")
    )

    let window = detachedWindow.dispatcher
    XCTAssertTrue(window.setTitle("Runtime Window Updated"))

    let webview = try XCTUnwrap(
      window.makeWebview(configuration: .init(url: "https://example.com")),
      "Mock runtime should provide a webview dispatcher"
    )

    XCTAssertTrue(webview.navigate(to: "https://example.com"))
  }

  func testRuntimeIndexesWindowsByLabel() throws {
    let runtime = try RuntimeHolder.shared()

    let label = "TestWindow"
    let detached = try runtime.createWindow(
      configuration: .init(width: 200, height: 200, title: label),
      label: label
    )

    let identifier = try XCTUnwrap(runtime.windowIdentifier(forLabel: label))
    XCTAssertEqual(identifier, detached.id)

    let retrieved = try XCTUnwrap(runtime.window(for: label))
    XCTAssertTrue(retrieved === detached.dispatcher)
  }

  func testWindowAdvancedMutations() throws {
    let runtime = try RuntimeHolder.shared()

    let detached = try runtime.createWindow(
      configuration: .init(width: 480, height: 320, title: "Advanced"),
      label: "Advanced"
    )

    let window = detached.dispatcher
    XCTAssertEqual(window.title(), "Advanced")
    XCTAssertTrue(window.setSize(width: 640, height: 480))
    XCTAssertTrue(window.setPosition(x: 32, y: 64))
    XCTAssertEqual(window.innerSize(), VeloxRuntimeWry.WindowSize(width: 640, height: 480))
    XCTAssertEqual(window.outerSize(), VeloxRuntimeWry.WindowSize(width: 640, height: 480))
    XCTAssertEqual(window.innerPosition(), VeloxRuntimeWry.WindowPosition(x: 32, y: 64))
    XCTAssertEqual(window.outerPosition(), VeloxRuntimeWry.WindowPosition(x: 32, y: 64))
    XCTAssertEqual(window.scaleFactor(), Optional(2.0))
    XCTAssertTrue(window.setFullscreen(true))
    XCTAssertTrue(window.isFullscreen())
    XCTAssertTrue(window.setMaximized(true))
    XCTAssertTrue(window.isMaximized())
    XCTAssertTrue(window.setMinimized(true))
    XCTAssertTrue(window.isMinimized())
    XCTAssertFalse(window.isMaximized())
    XCTAssertTrue(window.setMinimizable(false))
    XCTAssertFalse(window.isMinimizable())
    XCTAssertTrue(window.setMaximizable(false))
    XCTAssertFalse(window.isMaximizable())
    XCTAssertTrue(window.setClosable(false))
    XCTAssertFalse(window.isClosable())
    XCTAssertTrue(window.setSkipTaskbar(true))
    XCTAssertTrue(window.setBackgroundColor(.init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)))
    XCTAssertTrue(window.setBackgroundColor(nil))
    XCTAssertTrue(window.setTheme(.dark))
    XCTAssertTrue(window.setTheme(nil))
    XCTAssertNotNil(window.currentMonitor())
    XCTAssertNotNil(window.primaryMonitor())
    XCTAssertFalse(window.availableMonitors().isEmpty)
    XCTAssertNotNil(window.monitor(at: .init(x: 0, y: 0)))
    XCTAssertTrue(window.focus())
    XCTAssertTrue(window.isFocused())
    XCTAssertNil(window.cursorPosition())
    XCTAssertTrue(window.setCursorPosition(x: 12, y: 24))
    XCTAssertEqual(window.cursorPosition(), .init(x: 12, y: 24))
  }

  func testWindowEventAsyncStreamDeliversValues() async throws {
    guard #available(macOS 12.0, *) else {
      throw XCTSkip("AsyncStream requires macOS 12")
    }

    let runtime = try RuntimeHolder.shared()
    let label = "StreamWindow"
    let detached = try runtime.createWindow(
      configuration: .init(width: 200, height: 200, title: label),
      label: label
    )

    let stream = detached.dispatcher.events(bufferingPolicy: .bufferingNewest(1))
    let expectedPosition = VeloxRuntimeWry.WindowPosition(x: 10, y: 20)
    let eventTask = Task { await stream.first(where: { _ in true }) }

    runtime.emitWindowEvent(label: label, event: .windowMoved(windowId: label, position: expectedPosition))

    guard let event = await eventTask.value else {
      XCTFail("Window event stream yielded no value")
      return
    }

    switch event {
    case .moved(let eventLabel, let position):
      XCTAssertEqual(eventLabel, label)
      XCTAssertEqual(position, expectedPosition)
    default:
      XCTFail("Unexpected window event: \(event)")
    }
  }

  func testWebviewEventAsyncStreamDeliversValues() async throws {
    guard #available(macOS 12.0, *) else {
      throw XCTSkip("AsyncStream requires macOS 12")
    }

    let runtime = try RuntimeHolder.shared()
    let label = "StreamWebview"
    let detached = try runtime.createWindow(
      configuration: .init(width: 200, height: 200, title: label),
      label: label
    )
    let webview = try XCTUnwrap(detached.dispatcher.makeWebview(configuration: .init(url: "https://example.com")))

    let stream = webview.events(bufferingPolicy: .bufferingNewest(1))
    let expectedDescription = "mock"
    let eventTask = Task { await stream.first(where: { _ in true }) }

    runtime.emitWebviewEvent(label: label, event: .webviewEvent(label: label, description: expectedDescription))

    guard let event = await eventTask.value else {
      XCTFail("Webview event stream yielded no value")
      return
    }

    switch event {
    case .userEvent(let eventLabel, let description):
      XCTAssertEqual(eventLabel, label)
      XCTAssertEqual(description, expectedDescription)
    default:
      XCTFail("Unexpected webview event: \(event)")
    }
  }

  func testMenuEventAsyncStreamDeliversValues() async throws {
    guard #available(macOS 12.0, *) else {
      throw XCTSkip("AsyncStream requires macOS 12")
    }

    let runtime = try RuntimeHolder.shared()
    let identifier = "menu.item"
    let stream = runtime.menuEvents(bufferingPolicy: .bufferingNewest(1))
    let eventTask = Task { await stream.first(where: { _ in true }) }

    runtime.emitMenuEvent(identifier: identifier)

    guard let event = await eventTask.value else {
      XCTFail("Menu event stream yielded no value")
      return
    }

    switch event {
    case .activated(let menuId):
      XCTAssertEqual(menuId, identifier)
    default:
      XCTFail("Unexpected menu event: \(event)")
    }
  }

  func testTrayEventAsyncStreamDeliversValues() async throws {
    guard #available(macOS 12.0, *) else {
      throw XCTSkip("AsyncStream requires macOS 12")
    }

    let runtime = try RuntimeHolder.shared()
    let identifier = "tray"
    let expected = VeloxRuntimeWry.TrayEvent(
      identifier: identifier,
      type: .click,
      button: "left",
      buttonState: "up",
      position: VeloxRuntimeWry.WindowPosition(x: 5, y: 10),
      rect: nil
    )

    let stream = runtime.trayEvents(bufferingPolicy: .bufferingNewest(1))
    let eventTask = Task { await stream.first(where: { _ in true }) }

    runtime.emitTrayEvent(expected)

    guard let notification = await eventTask.value else {
      XCTFail("Tray event stream yielded no value")
      return
    }

    XCTAssertEqual(notification.identifier, identifier)
    XCTAssertEqual(notification.event, expected)
  }
}
