// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// DynamicHTML - Demonstrates Swift-rendered dynamic HTML content
// All HTML is generated in Swift based on application state.
// The webview is re-rendered when state changes via IPC commands.

import Foundation
import VeloxRuntimeWry

// MARK: - Application State

final class AppState {
  var counter: Int = 0
  var todos: [String] = ["Learn Swift", "Build with Velox", "Ship it!"]
  var theme: String = "light"

  var themeColors: (bg: String, text: String, card: String, accent: String) {
    if theme == "dark" {
      return ("#1a1a2e", "#eee", "#16213e", "#e94560")
    } else {
      return ("#f5f5f5", "#333", "#fff", "#007AFF")
    }
  }
}

let state = AppState()

// MARK: - HTML Rendering

func renderHTML() -> String {
  let colors = state.themeColors
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
  let currentTime = dateFormatter.string(from: Date())

  let todosHTML = state.todos.enumerated().map { index, todo in
    """
    <li>
      <span>\(escapeHTML(todo))</span>
      <button onclick="removeTodo(\(index))">Remove</button>
    </li>
    """
  }.joined(separator: "\n")

  return """
  <!doctype html>
  <html>
  <head>
    <meta charset="UTF-8">
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        background: \(colors.bg);
        color: \(colors.text);
        padding: 20px;
        min-height: 100vh;
        transition: all 0.3s ease;
      }
      .container { max-width: 600px; margin: 0 auto; }
      h1 {
        font-size: 28px;
        margin-bottom: 8px;
        background: linear-gradient(135deg, \(colors.accent), #764ba2);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
      }
      .subtitle { opacity: 0.7; margin-bottom: 24px; font-size: 14px; }
      .card {
        background: \(colors.card);
        border-radius: 12px;
        padding: 20px;
        margin-bottom: 16px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
      }
      .card h2 { font-size: 16px; margin-bottom: 12px; opacity: 0.8; }
      .time { font-size: 14px; opacity: 0.6; }

      /* Counter */
      .counter-display {
        font-size: 48px;
        font-weight: bold;
        text-align: center;
        margin: 16px 0;
        color: \(colors.accent);
      }
      .counter-buttons {
        display: flex;
        gap: 12px;
        justify-content: center;
      }

      /* Buttons */
      button {
        padding: 10px 20px;
        border: none;
        border-radius: 8px;
        font-size: 14px;
        cursor: pointer;
        transition: all 0.2s;
      }
      .btn-primary {
        background: \(colors.accent);
        color: white;
      }
      .btn-primary:hover { opacity: 0.9; transform: scale(1.02); }
      .btn-secondary {
        background: rgba(128,128,128,0.2);
        color: \(colors.text);
      }
      .btn-secondary:hover { background: rgba(128,128,128,0.3); }
      .btn-small {
        padding: 4px 12px;
        font-size: 12px;
      }

      /* Todo List */
      .todo-input {
        display: flex;
        gap: 8px;
        margin-bottom: 16px;
      }
      .todo-input input {
        flex: 1;
        padding: 10px 14px;
        border: 2px solid rgba(128,128,128,0.2);
        border-radius: 8px;
        font-size: 14px;
        background: \(colors.bg);
        color: \(colors.text);
      }
      .todo-input input:focus {
        outline: none;
        border-color: \(colors.accent);
      }
      ul { list-style: none; }
      li {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 12px;
        border-bottom: 1px solid rgba(128,128,128,0.1);
      }
      li:last-child { border-bottom: none; }
      li span { flex: 1; }
      li button {
        background: rgba(255,0,0,0.1);
        color: #e74c3c;
      }
      li button:hover { background: rgba(255,0,0,0.2); }

      /* Theme Toggle */
      .theme-toggle {
        position: fixed;
        top: 20px;
        right: 20px;
      }

      /* Stats */
      .stats {
        display: flex;
        gap: 16px;
        margin-top: 12px;
      }
      .stat {
        flex: 1;
        text-align: center;
        padding: 12px;
        background: rgba(128,128,128,0.1);
        border-radius: 8px;
      }
      .stat-value { font-size: 24px; font-weight: bold; color: \(colors.accent); }
      .stat-label { font-size: 12px; opacity: 0.7; }
    </style>
  </head>
  <body>
    <button class="theme-toggle btn-secondary" onclick="toggleTheme()">
      \(state.theme == "dark" ? "Light Mode" : "Dark Mode")
    </button>

    <div class="container">
      <h1>Dynamic HTML Demo</h1>
      <p class="subtitle">All content rendered by Swift - \(currentTime)</p>

      <div class="card">
        <h2>Counter</h2>
        <div class="counter-display">\(state.counter)</div>
        <div class="counter-buttons">
          <button class="btn-secondary" onclick="decrement()">- Decrease</button>
          <button class="btn-primary" onclick="increment()">+ Increase</button>
        </div>
      </div>

      <div class="card">
        <h2>Todo List (\(state.todos.count) items)</h2>
        <div class="todo-input">
          <input type="text" id="newTodo" placeholder="Add a new todo..."
                 onkeypress="if(event.key==='Enter')addTodo()">
          <button class="btn-primary" onclick="addTodo()">Add</button>
        </div>
        <ul>
          \(todosHTML.isEmpty ? "<li style='opacity:0.5;justify-content:center'>No todos yet!</li>" : todosHTML)
        </ul>
      </div>

      <div class="card">
        <h2>Statistics</h2>
        <div class="stats">
          <div class="stat">
            <div class="stat-value">\(state.counter)</div>
            <div class="stat-label">Counter</div>
          </div>
          <div class="stat">
            <div class="stat-value">\(state.todos.count)</div>
            <div class="stat-label">Todos</div>
          </div>
          <div class="stat">
            <div class="stat-value">\(state.theme == "dark" ? "Dark" : "Light")</div>
            <div class="stat-label">Theme</div>
          </div>
        </div>
      </div>
    </div>

    <script>
      async function invoke(command, args = {}) {
        const response = await fetch('ipc://localhost/' + command, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        return response.json();
      }

      async function increment() { await invoke('increment'); }
      async function decrement() { await invoke('decrement'); }
      async function toggleTheme() { await invoke('toggle_theme'); }

      async function addTodo() {
        const input = document.getElementById('newTodo');
        const text = input.value.trim();
        if (text) {
          await invoke('add_todo', { text });
          input.value = '';
        }
      }

      async function removeTodo(index) {
        await invoke('remove_todo', { index });
      }
    </script>
  </body>
  </html>
  """
}

func escapeHTML(_ string: String) -> String {
  string
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "'", with: "&#39;")
}

// MARK: - IPC Handler

func handleCommand(
  command: String,
  args: [String: Any],
  webview: VeloxRuntimeWry.Webview
) -> VeloxRuntimeWry.CustomProtocol.Response {
  switch command {
  case "increment":
    state.counter += 1
    refreshPage(webview)

  case "decrement":
    state.counter -= 1
    refreshPage(webview)

  case "toggle_theme":
    state.theme = state.theme == "dark" ? "light" : "dark"
    refreshPage(webview)

  case "add_todo":
    if let text = args["text"] as? String, !text.isEmpty {
      state.todos.append(text)
      refreshPage(webview)
    }

  case "remove_todo":
    if let index = args["index"] as? Int, index >= 0 && index < state.todos.count {
      state.todos.remove(at: index)
      refreshPage(webview)
    }

  default:
    return jsonResponse(["error": "Unknown command: \(command)"])
  }

  return jsonResponse(["ok": true])
}

func refreshPage(_ webview: VeloxRuntimeWry.Webview) {
  // Re-render by navigating to the same URL (triggers protocol handler)
  let html = renderHTML()
  let escaped = html
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "`", with: "\\`")
    .replacingOccurrences(of: "$", with: "\\$")
  webview.evaluate(script: "document.open(); document.write(`\(escaped)`); document.close();")
}

func jsonResponse(_ data: [String: Any]) -> VeloxRuntimeWry.CustomProtocol.Response {
  let jsonData = (try? JSONSerialization.data(withJSONObject: data)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 200,
    headers: ["Content-Type": "application/json"],
    body: jsonData
  )
}

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("DynamicHTML must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 700,
    height: 700,
    title: "Dynamic HTML - Swift Rendered"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  // We need to capture webview for the IPC handler, so create protocols after
  var webviewRef: VeloxRuntimeWry.Webview?

  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    guard let url = URL(string: request.url) else {
      return jsonResponse(["error": "Invalid URL"])
    }

    let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    var args: [String: Any] = [:]
    if !request.body.isEmpty,
       let json = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] {
      args = json
    }

    print("[IPC] \(command) \(args)")

    if let webview = webviewRef {
      return handleCommand(command: command, args: args, webview: webview)
    }
    return jsonResponse(["error": "Webview not ready"])
  }

  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(renderHTML().utf8)
    )
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [ipcProtocol, appProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }
  webviewRef = webview

  _ = window.setVisible(true)
  _ = window.focus()
  _ = webview.show()
  #if os(macOS)
  eventLoop.showApplication()
  #endif

  print("DynamicHTML running. All HTML is generated by Swift!")

  final class RunState: @unchecked Sendable {
    var shouldExit = false
  }
  let runState = RunState()

  while !runState.shouldExit {
    eventLoop.pump { event in
      switch event {
      case .windowCloseRequested, .userExit:
        runState.shouldExit = true
        return .exit
      default:
        return .wait
      }
    }
  }
}

main()
