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

  func testUserDefinedPayloadDecoding() {
    let json = "{\"type\":\"user-event\",\"payload\":\"{\\\"action\\\":\\\"ping\\\",\\\"value\\\":42}\"}"
    let event = VeloxRuntimeWry.Event(fromJSON: json)
    let expected = VeloxRuntimeWry.UserDefinedPayload(rawValue: "{\"action\":\"ping\",\"value\":42}")
    XCTAssertEqual(event, .userDefined(payload: expected))

    struct Payload: Decodable, Equatable {
      let action: String
      let value: Int
    }

    if case .userDefined(let payload) = event {
      XCTAssertEqual(payload.decode(Payload.self), Payload(action: "ping", value: 42))
    } else {
      XCTFail("Expected userDefined event")
    }
  }

  func testMenuEventDecoding() {
    let json = "{\"type\":\"menu-event\",\"menu_id\":\"file\"}"
    XCTAssertEqual(VeloxRuntimeWry.Event(fromJSON: json), .menuEvent(menuId: "file"))
  }

  func testTrayEventDecoding() {
    let json = "{\"type\":\"tray-event\",\"tray_id\":\"tray.1\",\"event_type\":\"click\",\"button\":\"left\",\"button_state\":\"down\",\"position\":{\"x\":12.0,\"y\":4.0},\"rect\":{\"x\":1.0,\"y\":2.0,\"width\":24.0,\"height\":16.0}}"
    let expected = VeloxRuntimeWry.TrayEvent(
      identifier: "tray.1",
      type: .click,
      button: "left",
      buttonState: "down",
      position: VeloxRuntimeWry.WindowPosition(x: 12, y: 4),
      rect: VeloxRuntimeWry.TrayRect(
        origin: VeloxRuntimeWry.WindowPosition(x: 1, y: 2),
        size: VeloxRuntimeWry.WindowSize(width: 24, height: 16)
      )
    )
    XCTAssertEqual(VeloxRuntimeWry.Event(fromJSON: json), .trayEvent(event: expected))
  }
}
