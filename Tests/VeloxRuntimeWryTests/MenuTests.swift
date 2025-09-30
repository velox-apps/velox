#if os(macOS)
import Foundation
import XCTest
@testable import VeloxRuntimeWry

final class MenuTests: XCTestCase {
  func testMenuBarLifecycle() throws {
    guard ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] == "1" else {
      throw XCTSkip("UI integration tests disabled")
    }
    AppKitHost.prepareIfNeeded()

    guard let menuBar = try runOnMain({ VeloxRuntimeWry.MenuBar() }) else {
      throw XCTSkip("Menu bar creation not supported in this environment")
    }
    XCTAssertFalse(menuBar.identifier.isEmpty)

    guard let submenu = try runOnMain({ VeloxRuntimeWry.Submenu(title: "File") }) else {
      throw XCTSkip("Submenu creation not supported")
    }
    XCTAssertFalse(submenu.identifier.isEmpty)

    guard let menuItem = try runOnMain({
      VeloxRuntimeWry.MenuItem(identifier: "app.quit", title: "Quit", accelerator: "cmd+Q")
    }) else {
      throw XCTSkip("Menu item creation not supported")
    }
    XCTAssertEqual(menuItem.identifier, "app.quit")

    try runOnMain {
      XCTAssertTrue(submenu.append(menuItem))
      XCTAssertTrue(menuBar.append(submenu))
    }
  }

  func testTrayLifecycle() throws {
    guard ProcessInfo.processInfo.environment["VELOX_ENABLE_UI_TESTS"] == "1" else {
      throw XCTSkip("UI integration tests disabled")
    }
    AppKitHost.prepareIfNeeded()
    AppKitHost.finishLaunchingIfNeeded()

    var skipReason: String?

    guard let tray = try runOnMain({
      VeloxRuntimeWry.TrayIcon(
        identifier: "velox.tray.tests",
        title: "Velox",
        tooltip: "Testing"
      )
    }) else {
      throw XCTSkip("Tray icon creation not supported in this environment")
    }
    XCTAssertFalse(tray.identifier.isEmpty)

    try runOnMain {
      if !tray.setTitle("Updated") {
        skipReason = "Setting tray title not supported"
        return
      }
      if !tray.setTooltip("Tooltip") {
        skipReason = "Setting tray tooltip not supported"
        return
      }
      XCTAssertTrue(tray.setShowMenuOnLeftClick(false))
      XCTAssertTrue(tray.setVisible(false))
      XCTAssertTrue(tray.setVisible(true))
    }

    if let reason = skipReason {
      throw XCTSkip(reason)
    }

    guard let menu = try runOnMain({ VeloxRuntimeWry.MenuBar(identifier: "velox.tray.menu") }) else {
      throw XCTSkip("Tray menu creation not supported")
    }
    guard let submenu = try runOnMain({ VeloxRuntimeWry.Submenu(title: "Actions") }) else {
      throw XCTSkip("Tray submenu creation not supported")
    }
    guard let item = try runOnMain({ VeloxRuntimeWry.MenuItem(identifier: "tray.quit", title: "Quit") }) else {
      throw XCTSkip("Tray menu item creation not supported")
    }

    try runOnMain {
      XCTAssertTrue(submenu.append(item))
      XCTAssertTrue(menu.append(submenu))
      XCTAssertTrue(tray.setMenu(menu))
      XCTAssertTrue(tray.setMenu(nil))
    }
  }
}
#endif
