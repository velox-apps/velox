// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// Tray - Demonstrates system tray icon with context menu
// - Creates a tray icon with title and tooltip
// - Adds a context menu with items
// - Handles menu events and tray clicks

import Foundation
import VeloxRuntimeWry

#if os(macOS)

// MARK: - HTML Content

let html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Velox Tray Demo</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 30px;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      min-height: 100vh;
      color: white;
    }
    h1 { margin-bottom: 10px; }
    .subtitle { color: rgba(255,255,255,0.6); margin-bottom: 30px; }
    .card {
      background: rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 20px;
    }
    .card h2 { font-size: 16px; margin-bottom: 15px; color: #4fc3f7; }
    .log {
      background: rgba(0,0,0,0.3);
      border-radius: 8px;
      padding: 15px;
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 12px;
      max-height: 200px;
      overflow-y: auto;
    }
    .log-entry { padding: 4px 0; border-bottom: 1px solid rgba(255,255,255,0.1); }
    .log-entry:last-child { border-bottom: none; }
    .log-entry .time { color: rgba(255,255,255,0.4); }
    .log-entry .event { color: #81c784; }
    .status {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 14px;
      background: #4fc3f7;
      color: #1a1a2e;
    }
    .info { color: rgba(255,255,255,0.7); font-size: 14px; line-height: 1.6; }
  </style>
</head>
<body>
  <h1>System Tray Demo</h1>
  <p class="subtitle">Check your menu bar for the tray icon</p>

  <div class="card">
    <h2>Tray Status</h2>
    <p><span class="status" id="status">Active</span></p>
  </div>

  <div class="card">
    <h2>Instructions</h2>
    <div class="info">
      <p>Look for "Velox" in your menu bar (top right).</p>
      <p>Click the tray icon to see the context menu.</p>
      <p>Menu actions will be logged below.</p>
    </div>
  </div>

  <div class="card">
    <h2>Event Log</h2>
    <div class="log" id="log">
      <div class="log-entry">
        <span class="time">--:--:--</span>
        <span class="event">Waiting for events...</span>
      </div>
    </div>
  </div>

  <script>
    function log(message) {
      const logEl = document.getElementById('log');
      const time = new Date().toLocaleTimeString();
      const entry = document.createElement('div');
      entry.className = 'log-entry';
      entry.innerHTML = '<span class="time">' + time + '</span> <span class="event">' + message + '</span>';
      logEl.insertBefore(entry, logEl.firstChild);
    }

    // Listen for menu events from backend
    if (window.Velox && window.Velox.event) {
      Velox.event.listen('menu-event', (event) => {
        log('Menu clicked: ' + event.payload.menuId);
      });

      Velox.event.listen('tray-event', (event) => {
        log('Tray ' + event.payload.eventType + ' at (' +
          Math.round(event.payload.position?.x || 0) + ', ' +
          Math.round(event.payload.position?.y || 0) + ')');
      });
    }

    log('Tray demo started');
  </script>
</body>
</html>
"""

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("Tray must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // Create the tray icon
  guard let tray = VeloxRuntimeWry.TrayIcon(
    identifier: "velox-tray",
    title: "Velox",
    tooltip: "Velox Tray Demo - Click for menu",
    visible: true,
    showMenuOnLeftClick: true
  ) else {
    fatalError("Failed to create tray icon")
  }

  print("[Tray] Created tray icon: \(tray.identifier)")

  // Create context menu
  guard let menu = VeloxRuntimeWry.MenuBar() else {
    fatalError("Failed to create menu")
  }

  // Create File submenu
  guard let fileSubmenu = VeloxRuntimeWry.Submenu(title: "Actions") else {
    fatalError("Failed to create submenu")
  }

  // Add menu items
  if let showItem = VeloxRuntimeWry.MenuItem(
    identifier: "show-window",
    title: "Show Window",
    isEnabled: true,
    accelerator: "CmdOrCtrl+S"
  ) {
    fileSubmenu.append(showItem)
  }

  if let hideItem = VeloxRuntimeWry.MenuItem(
    identifier: "hide-window",
    title: "Hide Window",
    isEnabled: true,
    accelerator: "CmdOrCtrl+H"
  ) {
    fileSubmenu.append(hideItem)
  }

  if let aboutItem = VeloxRuntimeWry.MenuItem(
    identifier: "about",
    title: "About Velox",
    isEnabled: true
  ) {
    fileSubmenu.append(aboutItem)
  }

  if let quitItem = VeloxRuntimeWry.MenuItem(
    identifier: "quit",
    title: "Quit",
    isEnabled: true,
    accelerator: "CmdOrCtrl+Q"
  ) {
    fileSubmenu.append(quitItem)
  }

  menu.append(fileSubmenu)
  tray.setMenu(menu)

  print("[Tray] Menu configured")

  // Create app protocol
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html"],
      body: Data(html.utf8)
    )
  }

  // Create window
  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 500,
    height: 500,
    title: "Velox Tray Demo"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [appProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }

  webview.show()
  window.setVisible(true)
  eventLoop.showApplication()

  print("[Tray] Application started")
  print("[Tray] Look for 'Velox' in your menu bar")

  // Run event loop
  final class AppState: @unchecked Sendable {
    var shouldExit = false
  }
  let state = AppState()

  while !state.shouldExit {
    eventLoop.pump { event in
      switch event {
      case .windowCloseRequested, .userExit:
        state.shouldExit = true
        return .exit

      case .menuEvent(let menuId):
        print("[Tray] Menu event: \(menuId)")
        if menuId == "quit" {
          state.shouldExit = true
          return .exit
        } else if menuId == "show-window" {
          window.setVisible(true)
          window.focus()
        } else if menuId == "hide-window" {
          window.setVisible(false)
        }
        return .wait

      case .trayEvent(let event):
        print("[Tray] Tray event: \(event.type) at \(event.position?.x ?? 0), \(event.position?.y ?? 0)")
        return .wait

      default:
        return .wait
      }
    }
  }

  print("[Tray] Application exiting")
}

main()

#else

// Non-macOS stub
func main() {
  print("System tray is only supported on macOS")
}

main()

#endif
