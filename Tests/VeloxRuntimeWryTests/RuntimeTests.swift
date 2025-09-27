import XCTest
@testable import VeloxRuntimeWry

final class RuntimeTests: XCTestCase {
  func testRuntimeIterationProducesEvents() throws {
    guard let runtime = VeloxRuntimeWry.Runtime() else {
      throw XCTSkip("Runtime not available in the current environment")
    }

    final class EventAccumulator: @unchecked Sendable {
      var events: [VeloxRuntimeWry.Event] = []
    }

    let accumulator = EventAccumulator()
    runtime.runIteration { event in
      accumulator.events.append(event)
    }

    XCTAssertFalse(accumulator.events.isEmpty)
    _ = runtime.requestExit(code: 0)
  }

  func testRuntimeCreatesWindowAndWebview() throws {
    guard let runtime = VeloxRuntimeWry.Runtime() else {
      throw XCTSkip("Runtime not available in the current environment")
    }

    guard let window = runtime.createWindow(
      configuration: .init(width: 320, height: 240, title: "Runtime Window")
    ) else {
      throw XCTSkip("Window creation not supported in this environment")
    }

    XCTAssertTrue(window.setTitle("Runtime Window Updated"))

    guard let webview = window.makeWebview(configuration: .init(url: "https://example.com")) else {
      throw XCTSkip("Webview creation not supported in this environment")
    }

    XCTAssertTrue(webview.navigate(to: "https://example.com"))
  }
}
