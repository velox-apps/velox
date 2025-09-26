import XCTest
@testable import VeloxRuntimeWry

final class EventDecodingTests: XCTestCase {
  func testNewEvents() {
    let json = "{\"type\":\"new-events\",\"cause\":\"Init\"}"
    XCTAssertEqual(VeloxRuntimeWry.Event(fromJSON: json), .newEvents(cause: "Init"))
  }

  func testWindowResized() {
    let json = "{\"type\":\"window-resized\",\"window_id\":\"WindowId(1)\",\"size\":{\"width\":800.0,\"height\":600.0}}"
    XCTAssertEqual(
      VeloxRuntimeWry.Event(fromJSON: json),
      .windowResized(windowId: "WindowId(1)", width: 800, height: 600)
    )
  }

  func testFallbackToUnknown() {
    let json = "{\"unexpected\":true}"
    XCTAssertEqual(VeloxRuntimeWry.Event(fromJSON: json), .unknown(json: json))
  }
}
