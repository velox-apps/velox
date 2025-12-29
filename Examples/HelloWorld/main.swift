// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Command Handler

/// Handles the "greet" command from the webview
func greet(name: String) -> String {
  "Hello \(name), You have been greeted from Swift!"
}

/// Parse invoke request and route to command handlers
func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request) -> VeloxRuntimeWry.CustomProtocol.Response? {
  // Parse the URL to get the command: ipc://localhost/<command>
  guard let url = URL(string: request.url) else {
    return errorResponse(message: "Invalid URL")
  }

  // Extract command from path (e.g., "/greet" -> "greet")
  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  // Parse JSON body for arguments
  var args: [String: Any] = [:]
  if !request.body.isEmpty,
     let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
    args = json
  }

  // Route to command handler
  switch command {
  case "greet":
    let name = args["name"] as? String ?? "World"
    let result = greet(name: name)
    return jsonResponse(["result": result])

  default:
    return errorResponse(message: "Unknown command: \(command)")
  }
}

/// Create a JSON success response
func jsonResponse(_ data: [String: Any]) -> VeloxRuntimeWry.CustomProtocol.Response {
  let jsonData = (try? JSONSerialization.data(withJSONObject: data)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 200,
    headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
    mimeType: "application/json",
    body: jsonData
  )
}

/// Create a JSON error response
func errorResponse(message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  let error: [String: Any] = ["error": message]
  let jsonData = (try? JSONSerialization.data(withJSONObject: error)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 400,
    headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
    mimeType: "application/json",
    body: jsonData
  )
}

// MARK: - HTML Content

/// The frontend HTML with embedded JavaScript
let htmlContent = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Welcome to Velox!</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 600px;
        margin: 50px auto;
        padding: 20px;
        text-align: center;
      }
      h1 {
        color: #333;
      }
      form {
        margin: 20px 0;
      }
      input {
        padding: 10px;
        font-size: 16px;
        border: 1px solid #ccc;
        border-radius: 4px;
        margin-right: 10px;
      }
      button {
        padding: 10px 20px;
        font-size: 16px;
        background-color: #007AFF;
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
      }
      button:hover {
        background-color: #0056b3;
      }
      #message {
        margin-top: 20px;
        padding: 15px;
        background-color: #f0f0f0;
        border-radius: 4px;
        min-height: 20px;
      }
    </style>
  </head>
  <body>
    <h1>Welcome to Velox!</h1>

    <form id="form">
      <input id="name" placeholder="Enter a name..." />
      <button type="submit">Greet</button>
    </form>

    <p id="message"></p>

    <script>
      // Velox IPC: invoke commands via custom protocol
      async function invoke(command, args = {}) {
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        const data = await response.json();
        if (data.error) {
          throw new Error(data.error);
        }
        return data.result;
      }

      const form = document.querySelector('#form');
      const nameEl = document.querySelector('#name');
      const messageEl = document.querySelector('#message');

      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        try {
          const name = nameEl.value || 'World';
          const message = await invoke('greet', { name });
          messageEl.textContent = message;
        } catch (err) {
          messageEl.textContent = 'Error: ' + err.message;
        }
      });
    </script>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("HelloWorld must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    handleInvoke(request: request)
  }

  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent.utf8)
    )
  }

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 800,
    height: 600,
    title: "Welcome to Velox!"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [ipcProtocol, appProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }

  // Show window and activate app
  _ = window.setVisible(true)
  _ = window.focus()
  _ = webview.show()
  #if os(macOS)
  eventLoop.showApplication()
  #endif

  // Run event loop using run_return pattern
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

      default:
        return .wait
      }
    }
  }
}

main()
