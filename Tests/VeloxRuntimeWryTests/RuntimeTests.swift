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
}
