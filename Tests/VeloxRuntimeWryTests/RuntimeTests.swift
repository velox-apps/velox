import XCTest
import VeloxRuntime
#if canImport(AppKit)
import AppKit
#endif
@testable import VeloxRuntimeWry

final class RuntimeTests: XCTestCase {
  func testRuntimeIterationProducesEvents() throws {
    guard let runtime = VeloxRuntimeWry.Runtime() else {
      throw XCTSkip("Runtime not available in the current environment")
    }

#if canImport(AppKit)
    if ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] != "1" {
      throw XCTSkip("UI integration tests disabled")
    }
    if NSApp == nil {
      throw XCTSkip("AppKit application is not running")
    }
#else
    throw XCTSkip("UI integration tests unavailable on this platform")
#endif

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
    guard let runtime = VeloxRuntimeWry.Runtime() else {
      throw XCTSkip("Runtime not available in the current environment")
    }

#if canImport(AppKit)
    if ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] != "1" {
      throw XCTSkip("UI integration tests disabled")
    }
    if NSApp == nil {
      throw XCTSkip("AppKit application is not running")
    }
#else
    throw XCTSkip("UI integration tests unavailable on this platform")
#endif

    guard let detached = try? runtime.createWindow(
      configuration: .init(width: 320, height: 240, title: "Runtime Window")
    ) else {
      throw XCTSkip("Window creation not supported in this environment")
    }

    let window = detached.dispatcher

    XCTAssertTrue(window.setTitle("Runtime Window Updated"))

    guard let webview = window.makeWebview(configuration: .init(url: "https://example.com")) else {
      throw XCTSkip("Webview creation not supported in this environment")
    }

    XCTAssertTrue(webview.navigate(to: "https://example.com"))
  }

  func testRuntimeIndexesWindowsByLabel() throws {
    guard let runtime = VeloxRuntimeWry.Runtime() else {
      throw XCTSkip("Runtime not available in the current environment")
    }

#if canImport(AppKit)
    if ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] != "1" {
      throw XCTSkip("UI integration tests disabled")
    }
    if NSApp == nil {
      throw XCTSkip("AppKit application is not running")
    }
#else
    throw XCTSkip("UI integration tests unavailable on this platform")
#endif

    let label = "TestWindow"
    let detached = try runtime.createWindow(
      configuration: .init(width: 200, height: 200, title: label),
      label: label
    )
    let identifier = try XCTUnwrap(runtime.windowIdentifier(forLabel: label))
    XCTAssertEqual(identifier, detached.id)
    let retrieved = runtime.window(for: label)
    XCTAssertTrue(retrieved === detached.dispatcher)
  }
}
