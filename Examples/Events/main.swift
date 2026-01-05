// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// Events - Demonstrates the Velox event system
// - Backend emitting events to frontend
// - Frontend emitting events to backend
// - Listening and unlistening

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - HTML Content

let html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Velox Events Demo</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      color: white;
    }
    h1 { margin-bottom: 20px; }
    .container { max-width: 800px; margin: 0 auto; }
    .section {
      background: rgba(255,255,255,0.15);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 20px;
      backdrop-filter: blur(10px);
    }
    .section h2 { margin-bottom: 15px; font-size: 18px; }
    button {
      background: white;
      color: #764ba2;
      border: none;
      padding: 10px 20px;
      border-radius: 8px;
      cursor: pointer;
      font-weight: 600;
      margin-right: 10px;
      margin-bottom: 10px;
      transition: transform 0.1s, box-shadow 0.1s;
    }
    button:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.2); }
    button:active { transform: translateY(0); }
    button.danger { background: #ff6b6b; color: white; }
    .log {
      background: rgba(0,0,0,0.3);
      border-radius: 8px;
      padding: 15px;
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 13px;
      max-height: 200px;
      overflow-y: auto;
    }
    .log-entry { padding: 5px 0; border-bottom: 1px solid rgba(255,255,255,0.1); }
    .log-entry:last-child { border-bottom: none; }
    .log-entry .time { color: rgba(255,255,255,0.5); margin-right: 10px; }
    .log-entry .event-name { color: #ffd93d; font-weight: bold; }
    .log-entry .direction { color: #6bcb77; }
    .counter { font-size: 48px; font-weight: bold; text-align: center; margin: 20px 0; }
    .status { display: flex; gap: 10px; flex-wrap: wrap; }
    .status-item {
      background: rgba(255,255,255,0.2);
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 14px;
    }
    .status-item.active { background: #6bcb77; color: #1a1a2e; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Velox Events Demo</h1>

    <div class="section">
      <h2>Backend Counter (Updated via Events)</h2>
      <div class="counter" id="counter">0</div>
      <p style="text-align: center; opacity: 0.7;">
        The counter is updated by events from Swift every second
      </p>
    </div>

    <div class="section">
      <h2>Send Events to Backend</h2>
      <button onclick="sendPing()">Send Ping</button>
      <button onclick="sendCustomEvent()">Send Custom Data</button>
      <button onclick="requestCounter()">Request Counter Value</button>
    </div>

    <div class="section">
      <h2>Event Listeners</h2>
      <div class="status" id="listener-status">
        <span class="status-item active" id="status-counter">counter-update: Active</span>
        <span class="status-item active" id="status-pong">pong: Active</span>
        <span class="status-item active" id="status-response">backend-response: Active</span>
      </div>
      <div style="margin-top: 15px;">
        <button onclick="toggleCounterListener()">Toggle Counter Listener</button>
        <button class="danger" onclick="removeAllListeners()">Remove All Listeners</button>
      </div>
    </div>

    <div class="section">
      <h2>Event Log</h2>
      <div class="log" id="log"></div>
      <button style="margin-top: 10px;" onclick="clearLog()">Clear Log</button>
    </div>
  </div>

  <script>
    let counterListenerId = null;
    let pongListenerId = null;
    let responseListenerId = null;

    function log(direction, eventName, payload) {
      const logEl = document.getElementById('log');
      const time = new Date().toLocaleTimeString();
      const entry = document.createElement('div');
      entry.className = 'log-entry';
      entry.innerHTML = `
        <span class="time">${time}</span>
        <span class="direction">[${direction}]</span>
        <span class="event-name">${eventName}</span>
        ${payload ? ': ' + JSON.stringify(payload) : ''}
      `;
      logEl.insertBefore(entry, logEl.firstChild);
    }

    function clearLog() {
      document.getElementById('log').innerHTML = '';
    }

    // Setup event listeners
    function setupListeners() {
      // Listen for counter updates from backend
      counterListenerId = Velox.event.listen('counter-update', (event) => {
        document.getElementById('counter').textContent = event.payload.value;
        log('IN', 'counter-update', event.payload);
      });

      // Listen for pong responses
      pongListenerId = Velox.event.listen('pong', (event) => {
        log('IN', 'pong', event.payload);
      });

      // Listen for backend responses
      responseListenerId = Velox.event.listen('backend-response', (event) => {
        log('IN', 'backend-response', event.payload);
      });

      log('SETUP', 'Listeners initialized');
    }

    // Send a ping to the backend
    async function sendPing() {
      log('OUT', 'ping', { timestamp: Date.now() });
      await Velox.event.emit('ping', { timestamp: Date.now() });
    }

    // Send custom data to backend
    async function sendCustomEvent() {
      const data = {
        message: 'Hello from JavaScript!',
        random: Math.floor(Math.random() * 100),
        nested: { a: 1, b: 2 }
      };
      log('OUT', 'custom-event', data);
      await Velox.event.emit('custom-event', data);
    }

    // Request current counter value
    async function requestCounter() {
      log('OUT', 'request-counter', null);
      await Velox.event.emit('request-counter', {});
    }

    // Toggle counter listener
    function toggleCounterListener() {
      const statusEl = document.getElementById('status-counter');
      if (counterListenerId) {
        Velox.event.unlisten(counterListenerId);
        counterListenerId = null;
        statusEl.classList.remove('active');
        statusEl.textContent = 'counter-update: Inactive';
        log('SETUP', 'Counter listener removed');
      } else {
        counterListenerId = Velox.event.listen('counter-update', (event) => {
          document.getElementById('counter').textContent = event.payload.value;
          log('IN', 'counter-update', event.payload);
        });
        statusEl.classList.add('active');
        statusEl.textContent = 'counter-update: Active';
        log('SETUP', 'Counter listener added');
      }
    }

    // Remove all listeners
    function removeAllListeners() {
      if (counterListenerId) Velox.event.unlisten(counterListenerId);
      if (pongListenerId) Velox.event.unlisten(pongListenerId);
      if (responseListenerId) Velox.event.unlisten(responseListenerId);

      counterListenerId = null;
      pongListenerId = null;
      responseListenerId = null;

      document.querySelectorAll('.status-item').forEach(el => {
        el.classList.remove('active');
        el.textContent = el.textContent.replace('Active', 'Inactive');
      });

      log('SETUP', 'All listeners removed');
    }

    // Initialize
    setupListeners();
    log('SETUP', 'Application started');
  </script>
</body>
</html>
"""

// MARK: - Event Payloads

struct CounterPayload: Codable, Sendable {
  let value: Int
}

struct PongPayload: Codable, Sendable {
  let response: String
  let received: String
}

struct BackendResponsePayload: Codable, Sendable {
  let message: String
  let value: Int?
  let originalPayload: String?

  init(message: String, value: Int? = nil, originalPayload: String? = nil) {
    self.message = message
    self.value = value
    self.originalPayload = originalPayload
  }
}

// MARK: - Application State

final class AppState: @unchecked Sendable {
  var counter: Int = 0
  let lock = NSLock()

  func incrementCounter() -> Int {
    lock.lock()
    defer { lock.unlock() }
    counter += 1
    return counter
  }

  func getCounter() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return counter
  }
}

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("Events must run on the main thread")
  }

  let state = AppState()
  let eventManager = VeloxEventManager()

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  // Create app protocol for serving HTML
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html"],
      body: Data(html.utf8)
    )
  }

  // Create IPC protocol that includes event handling
  let ipcHandler = createEventIPCHandler(manager: eventManager)
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    ipcHandler(request)
  }

  // Setup backend event listeners
  eventManager.listen("ping") { event in
    print("[Backend] Received ping: \(event.payloadJSON)")
    // Send pong response
    do {
      try eventManager.emit("pong", payload: PongPayload(response: "pong!", received: event.payloadJSON))
    } catch {
      print("[Backend] Failed to emit pong: \(error)")
    }
  }

  eventManager.listen("custom-event") { event in
    print("[Backend] Received custom event: \(event.payloadJSON)")
    do {
      try eventManager.emit("backend-response", payload: BackendResponsePayload(
        message: "Backend received your custom event!",
        originalPayload: event.payloadJSON
      ))
    } catch {
      print("[Backend] Failed to emit response: \(error)")
    }
  }

  eventManager.listen("request-counter") { _ in
    let value = state.getCounter()
    print("[Backend] Counter requested, sending value: \(value)")
    do {
      try eventManager.emit("backend-response", payload: BackendResponsePayload(
        message: "Current counter value",
        value: value
      ))
    } catch {
      print("[Backend] Failed to emit counter response: \(error)")
    }
  }

  // Create window
  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 800,
    height: 700,
    title: "Velox Events Demo"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [appProtocol, ipcProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }

  // Register webview with event manager
  eventManager.register(webview: webview, label: "main")

  webview.show()
  window.setVisible(true)

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  eventLoop.showApplication()
  #endif

  print("[App] Events demo started")
  print("[App] Backend will emit counter updates every second")

  // Emit counter updates every second.
  let counterTimer = Timer(timeInterval: 1.0, repeats: true) { _ in
    let value = state.incrementCounter()
    do {
      try eventManager.emit("counter-update", payload: CounterPayload(value: value))
    } catch {
      print("[Backend] Failed to emit counter update: \(error)")
    }
  }
  RunLoop.main.add(counterTimer, forMode: .common)

  eventLoop.run { event in
    switch event {
    case .windowCloseRequested, .userExit:
      counterTimer.invalidate()
      return .exit
    default:
      return .wait
    }
  }

  print("[App] Events demo exiting")
}

main()
