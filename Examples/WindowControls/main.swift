// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - IPC Handler

func handleInvoke(
  request: VeloxRuntimeWry.CustomProtocol.Request,
  window: VeloxRuntimeWry.Window,
  webview: VeloxRuntimeWry.Webview
) -> VeloxRuntimeWry.CustomProtocol.Response? {
  guard let url = URL(string: request.url) else {
    return errorResponse(error: "InvalidURL", message: "Invalid request URL")
  }

  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  var args: [String: Any] = [:]
  if !request.body.isEmpty,
     let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
    args = json
  }

  print("[IPC] Command: \(command)")

  switch command {
  // Window state
  case "minimize":
    let success = window.setMinimized(true)
    return jsonResponse(["result": success])

  case "maximize":
    let success = window.setMaximized(!window.isMaximized())
    return jsonResponse(["result": success, "maximized": window.isMaximized()])

  case "fullscreen":
    let success = window.setFullscreen(!window.isFullscreen())
    return jsonResponse(["result": success, "fullscreen": window.isFullscreen()])

  case "focus":
    let success = window.focus()
    return jsonResponse(["result": success])

  // Window visibility
  case "set_visible":
    let visible = args["visible"] as? Bool ?? true
    let success = window.setVisible(visible)
    return jsonResponse(["result": success])

  // Window properties
  case "set_title":
    guard let title = args["title"] as? String else {
      return errorResponse(error: "MissingArgument", message: "title is required")
    }
    let success = window.setTitle(title)
    return jsonResponse(["result": success])

  case "set_resizable":
    let resizable = args["resizable"] as? Bool ?? true
    let success = window.setResizable(resizable)
    return jsonResponse(["result": success])

  case "set_decorations":
    let decorations = args["decorations"] as? Bool ?? true
    let success = window.setDecorations(decorations)
    return jsonResponse(["result": success])

  case "set_always_on_top":
    let onTop = args["onTop"] as? Bool ?? true
    let success = window.setAlwaysOnTop(onTop)
    return jsonResponse(["result": success])

  case "set_minimizable":
    let minimizable = args["minimizable"] as? Bool ?? true
    let success = window.setMinimizable(minimizable)
    return jsonResponse(["result": success])

  case "set_maximizable":
    let maximizable = args["maximizable"] as? Bool ?? true
    let success = window.setMaximizable(maximizable)
    return jsonResponse(["result": success])

  case "set_closable":
    let closable = args["closable"] as? Bool ?? true
    let success = window.setClosable(closable)
    return jsonResponse(["result": success])

  // Size and position
  case "set_size":
    guard let width = args["width"] as? Double,
          let height = args["height"] as? Double else {
      return errorResponse(error: "MissingArgument", message: "width and height are required")
    }
    let success = window.setSize(width: width, height: height)
    return jsonResponse(["result": success])

  case "set_position":
    guard let x = args["x"] as? Double,
          let y = args["y"] as? Double else {
      return errorResponse(error: "MissingArgument", message: "x and y are required")
    }
    let success = window.setPosition(x: x, y: y)
    return jsonResponse(["result": success])

  case "set_min_size":
    guard let width = args["width"] as? Double,
          let height = args["height"] as? Double else {
      return errorResponse(error: "MissingArgument", message: "width and height are required")
    }
    let success = window.setMinimumSize(width: width, height: height)
    return jsonResponse(["result": success])

  case "set_max_size":
    guard let width = args["width"] as? Double,
          let height = args["height"] as? Double else {
      return errorResponse(error: "MissingArgument", message: "width and height are required")
    }
    let success = window.setMaximumSize(width: width, height: height)
    return jsonResponse(["result": success])

  // Cursor controls
  case "set_cursor_visible":
    let visible = args["visible"] as? Bool ?? true
    let success = window.setCursorVisible(visible)
    return jsonResponse(["result": success])

  case "set_cursor_grab":
    let grab = args["grab"] as? Bool ?? false
    let success = window.setCursorGrab(grab)
    return jsonResponse(["result": success])

  // Webview controls
  case "set_zoom":
    guard let scale = args["scale"] as? Double else {
      return errorResponse(error: "MissingArgument", message: "scale is required")
    }
    let success = webview.setZoom(scale)
    return jsonResponse(["result": success])

  case "navigate":
    guard let urlStr = args["url"] as? String else {
      return errorResponse(error: "MissingArgument", message: "url is required")
    }
    let success = webview.navigate(to: urlStr)
    return jsonResponse(["result": success])

  case "reload":
    let success = webview.reload()
    return jsonResponse(["result": success])

  // Get window state
  case "get_state":
    let state: [String: Any] = [
      "isMaximized": window.isMaximized(),
      "isMinimized": window.isMinimized(),
      "isVisible": window.isVisible(),
      "isFullscreen": window.isFullscreen(),
      "isResizable": window.isResizable(),
      "isDecorated": window.isDecorated(),
      "isAlwaysOnTop": window.isAlwaysOnTop(),
      "isMinimizable": window.isMinimizable(),
      "isMaximizable": window.isMaximizable(),
      "isClosable": window.isClosable(),
      "isFocused": window.isFocused()
    ]
    return jsonResponse(["result": state])

  // Theme
  case "set_theme":
    let themeStr = args["theme"] as? String
    var theme: VeloxRuntimeWry.Window.Theme?
    switch themeStr {
    case "light":
      theme = .light
    case "dark":
      theme = .dark
    default:
      theme = nil
    }
    let success = window.setTheme(theme)
    return jsonResponse(["result": success])

  default:
    return errorResponse(error: "UnknownCommand", message: "Unknown command: \(command)")
  }
}

func jsonResponse(_ data: [String: Any]) -> VeloxRuntimeWry.CustomProtocol.Response {
  let jsonData = (try? JSONSerialization.data(withJSONObject: data)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 200,
    headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
    mimeType: "application/json",
    body: jsonData
  )
}

func errorResponse(error: String, message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  let errorData: [String: Any] = ["error": error, "message": message]
  let jsonData = (try? JSONSerialization.data(withJSONObject: errorData)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 400,
    headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
    mimeType: "application/json",
    body: jsonData
  )
}

// MARK: - HTML Content

let htmlContent = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Velox Window Controls</title>
    <style>
      * { box-sizing: border-box; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        margin: 0;
        padding: 20px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        min-height: 100vh;
        color: white;
      }
      h1 { text-align: center; margin-bottom: 30px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
      .container {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        gap: 20px;
        max-width: 1200px;
        margin: 0 auto;
      }
      .card {
        background: rgba(255,255,255,0.95);
        border-radius: 12px;
        padding: 20px;
        color: #333;
        box-shadow: 0 8px 32px rgba(0,0,0,0.2);
      }
      .card h3 {
        margin-top: 0;
        color: #667eea;
        border-bottom: 2px solid #667eea;
        padding-bottom: 10px;
      }
      button {
        padding: 10px 16px;
        margin: 4px;
        font-size: 13px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border: none;
        border-radius: 6px;
        cursor: pointer;
        transition: transform 0.1s, box-shadow 0.2s;
      }
      button:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
      }
      button:active { transform: translateY(0); }
      .button-row { margin: 8px 0; }
      input[type="text"], input[type="number"] {
        padding: 8px 12px;
        border: 2px solid #ddd;
        border-radius: 6px;
        font-size: 13px;
        width: 80px;
        margin-right: 8px;
      }
      input:focus { border-color: #667eea; outline: none; }
      .state-box {
        background: #f5f5f7;
        border-radius: 8px;
        padding: 12px;
        font-family: monospace;
        font-size: 12px;
        max-height: 200px;
        overflow-y: auto;
      }
      .state-item { margin: 4px 0; }
      .true { color: #34c759; }
      .false { color: #ff3b30; }
      label { display: inline-block; min-width: 60px; }
    </style>
  </head>
  <body>
    <h1>Velox Window Controls</h1>

    <div class="container">
      <div class="card">
        <h3>Window State</h3>
        <div class="button-row">
          <button onclick="invoke('minimize')">Minimize</button>
          <button onclick="invoke('maximize')">Toggle Maximize</button>
          <button onclick="invoke('fullscreen')">Toggle Fullscreen</button>
          <button onclick="invoke('focus')">Focus</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_visible', {visible: true})">Show</button>
          <button onclick="invoke('set_visible', {visible: false})">Hide (3s)</button>
        </div>
      </div>

      <div class="card">
        <h3>Window Properties</h3>
        <div class="button-row">
          <input type="text" id="title" placeholder="New Title" value="My Window">
          <button onclick="invoke('set_title', {title: document.getElementById('title').value})">Set Title</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_resizable', {resizable: true})">Resizable: On</button>
          <button onclick="invoke('set_resizable', {resizable: false})">Resizable: Off</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_decorations', {decorations: true})">Decorations: On</button>
          <button onclick="invoke('set_decorations', {decorations: false})">Decorations: Off</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_always_on_top', {onTop: true})">Always On Top: On</button>
          <button onclick="invoke('set_always_on_top', {onTop: false})">Always On Top: Off</button>
        </div>
      </div>

      <div class="card">
        <h3>Window Buttons</h3>
        <div class="button-row">
          <button onclick="invoke('set_minimizable', {minimizable: true})">Minimizable: On</button>
          <button onclick="invoke('set_minimizable', {minimizable: false})">Minimizable: Off</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_maximizable', {maximizable: true})">Maximizable: On</button>
          <button onclick="invoke('set_maximizable', {maximizable: false})">Maximizable: Off</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_closable', {closable: true})">Closable: On</button>
          <button onclick="invoke('set_closable', {closable: false})">Closable: Off</button>
        </div>
      </div>

      <div class="card">
        <h3>Size & Position</h3>
        <div class="button-row">
          <label>Size:</label>
          <input type="number" id="width" value="800" style="width:60px">x
          <input type="number" id="height" value="600" style="width:60px">
          <button onclick="invoke('set_size', {width: +document.getElementById('width').value, height: +document.getElementById('height').value})">Set</button>
        </div>
        <div class="button-row">
          <label>Position:</label>
          <input type="number" id="posX" value="100" style="width:60px">,
          <input type="number" id="posY" value="100" style="width:60px">
          <button onclick="invoke('set_position', {x: +document.getElementById('posX').value, y: +document.getElementById('posY').value})">Set</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('set_size', {width: 400, height: 300})">Small</button>
          <button onclick="invoke('set_size', {width: 800, height: 600})">Medium</button>
          <button onclick="invoke('set_size', {width: 1200, height: 800})">Large</button>
        </div>
      </div>

      <div class="card">
        <h3>Theme & Appearance</h3>
        <div class="button-row">
          <button onclick="invoke('set_theme', {theme: 'light'})">Light Theme</button>
          <button onclick="invoke('set_theme', {theme: 'dark'})">Dark Theme</button>
          <button onclick="invoke('set_theme', {theme: null})">System Theme</button>
        </div>
      </div>

      <div class="card">
        <h3>Webview Controls</h3>
        <div class="button-row">
          <button onclick="invoke('set_zoom', {scale: 0.75})">Zoom 75%</button>
          <button onclick="invoke('set_zoom', {scale: 1.0})">Zoom 100%</button>
          <button onclick="invoke('set_zoom', {scale: 1.25})">Zoom 125%</button>
          <button onclick="invoke('set_zoom', {scale: 1.5})">Zoom 150%</button>
        </div>
        <div class="button-row">
          <button onclick="invoke('reload')">Reload</button>
        </div>
      </div>

      <div class="card">
        <h3>Window State</h3>
        <button onclick="refreshState()">Refresh State</button>
        <div class="state-box" id="stateDisplay">Click "Refresh State" to see current state...</div>
      </div>
    </div>

    <script>
      async function invoke(command, args = {}) {
        let data;
        if (window.Velox && typeof window.Velox.invoke === 'function') {
          try {
            const result = await window.Velox.invoke(command, args);
            data = { result };
          } catch (e) {
            data = { error: e && e.message ? e.message : String(e) };
          }
        } else {
          const response = await fetch(`ipc://localhost/${command}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(args)
          });
          data = await response.json();
        }
        console.log(command, args, '->', data);

        // Special handling for hide - show again after 3 seconds
        if (command === 'set_visible' && args.visible === false) {
          setTimeout(() => invoke('set_visible', {visible: true}), 3000);
        }

        return data;
      }

      async function refreshState() {
        const data = await invoke('get_state');
        const stateEl = document.getElementById('stateDisplay');
        if (data.result) {
          stateEl.innerHTML = Object.entries(data.result)
            .map(([k, v]) => `<div class="state-item"><strong>${k}:</strong> <span class="${v}">${v}</span></div>`)
            .join('');
        } else {
          stateEl.textContent = 'Error: ' + (data.error || 'Unknown error');
        }
      }

      // Initial state refresh
      setTimeout(refreshState, 500);
      console.log('Velox Window Controls loaded!');
    </script>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("WindowControls example must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 900,
    height: 750,
    title: "Velox Window Controls"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  // Wrapper for webview reference (needed for closure capture)
  final class WebviewHolder: @unchecked Sendable {
    var webview: VeloxRuntimeWry.Webview?
  }
  let webviewHolder = WebviewHolder()

  // IPC protocol for commands
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    guard let webview = webviewHolder.webview else { return nil }
    return handleInvoke(request: request, window: window, webview: webview)
  }

  // App protocol serves HTML
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent.utf8)
    )
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [ipcProtocol, appProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }
  webviewHolder.webview = webview

  // Show window and activate app
  _ = window.setVisible(true)
  _ = window.focus()
  _ = webview.show()
  #if os(macOS)
  eventLoop.showApplication()
  #endif

  // Run event loop
  eventLoop.run { event in
    switch event {
    case .windowCloseRequested, .userExit:
      return .exit

    default:
      return .wait
    }
  }
}

main()
