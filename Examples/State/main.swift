// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Application State

/// Thread-safe counter state
final class Counter: @unchecked Sendable {
  private var value: Int = 0
  private let lock = NSLock()

  func get() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }

  func decrement() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value -= 1
    return value
  }

  func reset() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value = 0
    return value
  }
}

// MARK: - Command Handler

/// Global counter for state management
let globalCounter = Counter()

/// Parse invoke request and route to command handlers
func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request) -> VeloxRuntimeWry.CustomProtocol.Response? {
  guard let url = URL(string: request.url) else {
    return errorResponse(message: "Invalid URL")
  }

  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  switch command {
  case "get":
    return jsonResponse(["result": globalCounter.get()])

  case "increment":
    return jsonResponse(["result": globalCounter.increment()])

  case "decrement":
    return jsonResponse(["result": globalCounter.decrement()])

  case "reset":
    return jsonResponse(["result": globalCounter.reset()])

  default:
    return errorResponse(message: "Unknown command: \(command)")
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

let htmlContent = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Velox State Example</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 400px;
        margin: 50px auto;
        padding: 20px;
        text-align: center;
      }
      h3 {
        color: #333;
        font-size: 24px;
      }
      #counter {
        font-size: 48px;
        font-weight: bold;
        color: #007AFF;
      }
      .buttons {
        margin: 30px 0;
        display: flex;
        gap: 10px;
        justify-content: center;
      }
      button {
        padding: 12px 24px;
        font-size: 16px;
        border: none;
        border-radius: 8px;
        cursor: pointer;
        transition: transform 0.1s;
      }
      button:active {
        transform: scale(0.95);
      }
      #increment-btn {
        background-color: #34C759;
        color: white;
      }
      #decrement-btn {
        background-color: #FF3B30;
        color: white;
      }
      #reset-btn {
        background-color: #8E8E93;
        color: white;
      }
      p {
        color: #666;
        font-size: 14px;
      }
    </style>
  </head>
  <body>
    <h3>Counter: <span id="counter">0</span></h3>
    <div class="buttons">
      <button id="increment-btn">+</button>
      <button id="decrement-btn">-</button>
      <button id="reset-btn">Reset</button>
    </div>
    <p>State persists while the app is running.</p>

    <script>
      async function invoke(command, args = {}) {
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        const data = await response.json();
        if (data.error) throw new Error(data.error);
        return data.result;
      }

      const counterEl = document.querySelector('#counter');
      const incrementBtn = document.querySelector('#increment-btn');
      const decrementBtn = document.querySelector('#decrement-btn');
      const resetBtn = document.querySelector('#reset-btn');

      // Load initial state
      document.addEventListener('DOMContentLoaded', async () => {
        counterEl.textContent = await invoke('get');
      });

      incrementBtn.addEventListener('click', async () => {
        counterEl.textContent = await invoke('increment');
      });

      decrementBtn.addEventListener('click', async () => {
        counterEl.textContent = await invoke('decrement');
      });

      resetBtn.addEventListener('click', async () => {
        counterEl.textContent = await invoke('reset');
      });
    </script>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("State example must run on the main thread")
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
    width: 400,
    height: 300,
    title: "Velox State Example"
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
