// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// State - Demonstrates Velox state management using StateContainer
// State is registered with manage() and accessed via state<T>()

import Foundation
import VeloxRuntime
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

/// Additional state to demonstrate multiple managed states
final class AppInfo: @unchecked Sendable {
  let name: String
  let version: String

  init(name: String, version: String) {
    self.name = name
    self.version = version
  }
}

// MARK: - Command Handler

/// Creates an IPC handler with access to managed state
func createIPCHandler(stateContainer: StateContainer) -> VeloxRuntimeWry.CustomProtocol.Handler {
  return { request in
    guard let url = URL(string: request.url) else {
      return errorResponse(message: "Invalid URL")
    }

    let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    // Access state from the container - this is similar to Tauri's State<T>
    guard let counter: Counter = stateContainer.get() else {
      return errorResponse(message: "Counter state not initialized")
    }

    switch command {
    case "get":
      return jsonResponse(["result": counter.get()])

    case "increment":
      return jsonResponse(["result": counter.increment()])

    case "decrement":
      return jsonResponse(["result": counter.decrement()])

    case "reset":
      return jsonResponse(["result": counter.reset()])

    case "info":
      // Access another state type
      if let appInfo: AppInfo = stateContainer.get() {
        return jsonResponse([
          "name": appInfo.name,
          "version": appInfo.version,
          "counter": counter.get()
        ])
      }
      return jsonResponse(["counter": counter.get()])

    default:
      return errorResponse(message: "Unknown command: \(command)")
    }
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
      .info {
        margin-top: 20px;
        padding: 15px;
        background: #f5f5f7;
        border-radius: 8px;
        text-align: left;
      }
      .info h4 {
        margin: 0 0 10px 0;
        color: #333;
      }
      .info p {
        margin: 5px 0;
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
    <p>State is managed via StateContainer</p>

    <div class="info" id="info" style="display: none;">
      <h4>App Info (from managed state)</h4>
      <p>Name: <span id="app-name">-</span></p>
      <p>Version: <span id="app-version">-</span></p>
    </div>

    <script>
      async function invoke(command, args = {}) {
        if (window.Velox && typeof window.Velox.invoke === 'function') {
          const result = await window.Velox.invoke(command, args);
          return { result };
        }
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        const data = await response.json();
        if (data.error) throw new Error(data.error);
        return data;
      }

      const counterEl = document.querySelector('#counter');
      const incrementBtn = document.querySelector('#increment-btn');
      const decrementBtn = document.querySelector('#decrement-btn');
      const resetBtn = document.querySelector('#reset-btn');
      const infoEl = document.querySelector('#info');
      const appNameEl = document.querySelector('#app-name');
      const appVersionEl = document.querySelector('#app-version');

      // Load initial state and app info
      document.addEventListener('DOMContentLoaded', async () => {
        const data = await invoke('get');
        counterEl.textContent = data.result;

        // Load app info from managed state
        const info = await invoke('info');
        if (info.name) {
          appNameEl.textContent = info.name;
          appVersionEl.textContent = info.version;
          infoEl.style.display = 'block';
        }
      });

      incrementBtn.addEventListener('click', async () => {
        const data = await invoke('increment');
        counterEl.textContent = data.result;
      });

      decrementBtn.addEventListener('click', async () => {
        const data = await invoke('decrement');
        counterEl.textContent = data.result;
      });

      resetBtn.addEventListener('click', async () => {
        const data = await invoke('reset');
        counterEl.textContent = data.result;
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

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let appBuilder: VeloxAppBuilder
  do {
    appBuilder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("State failed to load velox.json: \(error)")
  }

  appBuilder
    .manage(Counter())
    .manage(AppInfo(name: "Velox State Demo", version: "1.0.0"))

  print("[State] Registered Counter and AppInfo in StateContainer")

  let ipcHandler = createIPCHandler(stateContainer: appBuilder.stateContainer)
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent.utf8)
    )
  }

  print("[State] Application started")

  do {
    try appBuilder
      .registerProtocol("ipc", handler: ipcHandler)
      .registerProtocol("app", handler: appHandler)
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("State failed to start: \(error)")
  }

  print("[State] Application exiting")
}

main()
