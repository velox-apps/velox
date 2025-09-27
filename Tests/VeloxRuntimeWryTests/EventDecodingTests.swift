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
      .windowResized(windowId: "WindowId(1)", size: .init(width: 800, height: 600))
    )
  }

  func testFallbackToUnknown() {
    let json = "{\"unexpected\":true}"
    XCTAssertEqual(VeloxRuntimeWry.Event(fromJSON: json), .unknown(json: json))
  }

  func testKeyboardInputDecoding() {
    let json = "{\"type\":\"window-keyboard-input\",\"window_id\":\"WindowId(2)\",\"state\":\"Pressed\",\"logical_key\":\"Character(\\\"A\\\")\",\"physical_key\":\"KeyA\",\"text\":\"a\",\"repeat\":false,\"location\":\"Standard\",\"is_synthetic\":true}"
    let expected = VeloxRuntimeWry.KeyboardInput(
      state: "Pressed",
      logicalKey: "Character(\"A\")",
      physicalKey: "KeyA",
      text: "a",
      isRepeat: false,
      location: "Standard",
      isSynthetic: true
    )
    XCTAssertEqual(
      VeloxRuntimeWry.Event(fromJSON: json),
      .windowKeyboardInput(windowId: "WindowId(2)", input: expected)
    )
  }

  func testMouseWheelDecoding() {
    let json = "{\"type\":\"window-mouse-wheel\",\"window_id\":\"WindowId(3)\",\"delta\":{\"unit\":\"line\",\"x\":1.5,\"y\":-2.0},\"phase\":\"Started\"}"
    let expected = VeloxRuntimeWry.MouseWheelDelta(unit: .line, x: 1.5, y: -2.0)
    XCTAssertEqual(
      VeloxRuntimeWry.Event(fromJSON: json),
      .windowMouseWheel(windowId: "WindowId(3)", delta: expected, phase: "Started")
    )
  }

  func testExitRequestedDecoding() {
    let json = "{\"type\":\"exit-requested\",\"code\":42}"
    XCTAssertEqual(
      VeloxRuntimeWry.Event(fromJSON: json),
      .exitRequested(code: 42)
    )
  }
}
