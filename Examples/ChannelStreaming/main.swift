// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// ChannelStreaming - Demonstrates the Channel API for streaming data
//
// This example shows how to:
// - Create channels on the frontend
// - Pass channels to backend commands
// - Stream progress updates back to the frontend
// - Handle different event types (started, progress, finished, error)

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Progress Events

/// Events sent through the progress channel
enum TaskEvent: Codable, Sendable {
  case started(name: String, steps: Int)
  case progress(step: Int, message: String)
  case finished(result: String)
  case error(message: String)

  enum CodingKeys: String, CodingKey {
    case event, data
  }

  enum EventType: String, Codable {
    case started, progress, finished, error
  }

  // Data structs for each event type
  struct StartedData: Codable { let name: String; let steps: Int }
  struct ProgressData: Codable { let step: Int; let message: String }
  struct FinishedData: Codable { let result: String }
  struct ErrorData: Codable { let message: String }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .started(let name, let steps):
      try container.encode(EventType.started, forKey: .event)
      try container.encode(StartedData(name: name, steps: steps), forKey: .data)
    case .progress(let step, let message):
      try container.encode(EventType.progress, forKey: .event)
      try container.encode(ProgressData(step: step, message: message), forKey: .data)
    case .finished(let result):
      try container.encode(EventType.finished, forKey: .event)
      try container.encode(FinishedData(result: result), forKey: .data)
    case .error(let message):
      try container.encode(EventType.error, forKey: .event)
      try container.encode(ErrorData(message: message), forKey: .data)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let eventType = try container.decode(EventType.self, forKey: .event)
    switch eventType {
    case .started:
      let data = try container.decode(StartedData.self, forKey: .data)
      self = .started(name: data.name, steps: data.steps)
    case .progress:
      let data = try container.decode(ProgressData.self, forKey: .data)
      self = .progress(step: data.step, message: data.message)
    case .finished:
      let data = try container.decode(FinishedData.self, forKey: .data)
      self = .finished(result: data.result)
    case .error:
      let data = try container.decode(ErrorData.self, forKey: .data)
      self = .error(message: data.message)
    }
  }
}

// MARK: - HTML Content

let htmlContent = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Channel Streaming Example</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      min-height: 100vh;
      padding: 40px 20px;
      color: #fff;
    }
    .container {
      max-width: 600px;
      margin: 0 auto;
    }
    h1 {
      text-align: center;
      margin-bottom: 10px;
      font-size: 2em;
    }
    .subtitle {
      text-align: center;
      color: #888;
      margin-bottom: 40px;
    }
    .card {
      background: rgba(255,255,255,0.05);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 20px;
      border: 1px solid rgba(255,255,255,0.1);
    }
    .card h2 {
      font-size: 1.2em;
      margin-bottom: 15px;
      color: #7c8aff;
    }
    .card p {
      color: #aaa;
      margin-bottom: 15px;
      line-height: 1.5;
    }
    button {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 16px;
      font-weight: 500;
      transition: transform 0.2s, box-shadow 0.2s;
      width: 100%;
    }
    button:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 20px rgba(102, 126, 234, 0.4);
    }
    button:disabled {
      background: #444;
      cursor: not-allowed;
      transform: none;
      box-shadow: none;
    }
    .progress-container {
      margin: 20px 0;
      display: none;
    }
    .progress-bar {
      width: 100%;
      height: 8px;
      background: rgba(255,255,255,0.1);
      border-radius: 4px;
      overflow: hidden;
    }
    .progress-fill {
      height: 100%;
      background: linear-gradient(90deg, #667eea, #764ba2);
      width: 0%;
      transition: width 0.3s ease;
    }
    .progress-text {
      text-align: center;
      margin-top: 10px;
      color: #888;
      font-size: 14px;
    }
    .log {
      background: rgba(0,0,0,0.3);
      border-radius: 8px;
      padding: 15px;
      margin-top: 15px;
      max-height: 200px;
      overflow-y: auto;
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 12px;
    }
    .log-entry {
      padding: 4px 0;
      border-bottom: 1px solid rgba(255,255,255,0.05);
    }
    .log-entry:last-child {
      border-bottom: none;
    }
    .log-entry.started { color: #7c8aff; }
    .log-entry.progress { color: #aaa; }
    .log-entry.finished { color: #51cf66; }
    .log-entry.error { color: #ff6b6b; }
    .timestamp {
      color: #666;
      margin-right: 8px;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>Channel Streaming</h1>
    <p class="subtitle">Velox IPC Channel API Demo</p>

    <div class="card">
      <h2>Simulated File Processing</h2>
      <p>Click the button to simulate a multi-step file processing task.
         Progress updates are streamed from the backend via a Channel.</p>
      <button id="processBtn" onclick="startProcessing()">Start Processing</button>
      <div class="progress-container" id="progressContainer">
        <div class="progress-bar">
          <div class="progress-fill" id="progressFill"></div>
        </div>
        <div class="progress-text" id="progressText">Initializing...</div>
      </div>
      <div class="log" id="log"></div>
    </div>

    <div class="card">
      <h2>Data Stream</h2>
      <p>Start a continuous data stream that sends values until stopped.</p>
      <button id="streamBtn" onclick="toggleStream()">Start Stream</button>
      <div class="log" id="streamLog"></div>
    </div>
  </div>

  <script>
    // Helper to invoke backend commands
    async function invoke(cmd, args = {}) {
      const response = await fetch('ipc://localhost/' + cmd, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(args)
      });
      return response.json();
    }

    // Format timestamp
    function timestamp() {
      return new Date().toLocaleTimeString('en-US', { hour12: false });
    }

    // Add log entry
    function addLog(logId, message, type = 'progress') {
      const log = document.getElementById(logId);
      const entry = document.createElement('div');
      entry.className = 'log-entry ' + type;
      entry.innerHTML = '<span class="timestamp">' + timestamp() + '</span>' + message;
      log.appendChild(entry);
      log.scrollTop = log.scrollHeight;
    }

    // Simulated file processing with progress channel
    async function startProcessing() {
      const btn = document.getElementById('processBtn');
      const container = document.getElementById('progressContainer');
      const fill = document.getElementById('progressFill');
      const text = document.getElementById('progressText');
      const log = document.getElementById('log');

      btn.disabled = true;
      container.style.display = 'block';
      log.innerHTML = '';
      fill.style.width = '0%';

      // Create a channel for progress updates
      const channel = new VeloxChannel();
      let totalSteps = 0;

      channel.onmessage = (msg) => {
        switch (msg.event) {
          case 'started':
            totalSteps = msg.data.steps;
            addLog('log', 'Started: ' + msg.data.name + ' (' + totalSteps + ' steps)', 'started');
            break;
          case 'progress':
            const percent = Math.round((msg.data.step / totalSteps) * 100);
            fill.style.width = percent + '%';
            text.textContent = msg.data.message + ' (' + percent + '%)';
            addLog('log', 'Step ' + msg.data.step + ': ' + msg.data.message, 'progress');
            break;
          case 'finished':
            fill.style.width = '100%';
            text.textContent = 'Complete!';
            addLog('log', 'Finished: ' + msg.data.result, 'finished');
            btn.disabled = false;
            break;
          case 'error':
            addLog('log', 'Error: ' + msg.data.message, 'error');
            btn.disabled = false;
            break;
        }
      };

      channel.onclose = () => {
        console.log('Processing channel closed');
      };

      // Start the processing task
      await invoke('process_files', { onProgress: channel });
    }

    // Continuous data stream
    let streamChannel = null;

    function toggleStream() {
      const btn = document.getElementById('streamBtn');
      const log = document.getElementById('streamLog');

      if (streamChannel) {
        // Stop the stream
        invoke('stop_stream', { channelId: streamChannel.id });
        streamChannel = null;
        btn.textContent = 'Start Stream';
        addLog('streamLog', 'Stream stopped', 'finished');
      } else {
        // Start the stream
        log.innerHTML = '';
        streamChannel = new VeloxChannel();

        streamChannel.onmessage = (msg) => {
          if (msg.event === 'data') {
            addLog('streamLog', 'Value: ' + msg.data.value + ' (seq: ' + msg.data.sequence + ')', 'progress');
          } else if (msg.event === 'end') {
            addLog('streamLog', 'Stream ended', 'finished');
            streamChannel = null;
            btn.textContent = 'Start Stream';
          }
        };

        btn.textContent = 'Stop Stream';
        addLog('streamLog', 'Stream started', 'started');
        invoke('start_stream', { onData: streamChannel });
      }
    }
  </script>
</body>
</html>
"""

// MARK: - Application

func main() {
  guard Thread.isMainThread else {
    fatalError("Must run on main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // Event manager for webview handles
  let eventManager = VeloxEventManager()

  // Track active streams
  final class StreamState: @unchecked Sendable {
    var activeStreams: [String: Bool] = [:]
    let lock = NSLock()

    func start(_ id: String) {
      lock.lock()
      activeStreams[id] = true
      lock.unlock()
    }

    func stop(_ id: String) {
      lock.lock()
      activeStreams[id] = false
      lock.unlock()
    }

    func isActive(_ id: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return activeStreams[id] ?? false
    }
  }
  let streamState = StreamState()

  // Command registry
  let registry = CommandRegistry()

  // Process files command - simulates multi-step file processing
  registry.register("process_files") { ctx -> CommandResult in
    guard let channel: Channel<TaskEvent> = ctx.channel("onProgress") else {
      return .err(code: "MissingChannel", message: "Missing onProgress channel")
    }

    let steps = ["Scanning files", "Analyzing content", "Processing data", "Optimizing output", "Finalizing"]

    Task.detached {
      channel.send(.started(name: "File Processing", steps: steps.count))

      for (index, step) in steps.enumerated() {
        // Simulate work
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        channel.send(.progress(step: index + 1, message: step))
      }

      try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
      channel.send(.finished(result: "Processed 42 files successfully"))
      channel.close()
    }

    return .ok
  }

  // Start stream command - continuous data stream
  registry.register("start_stream") { ctx -> CommandResult in
    guard let channel: Channel<StreamEvent<[String: Int]>> = ctx.channel("onData") else {
      return .err(code: "MissingChannel", message: "Missing onData channel")
    }

    let channelId = channel.id
    streamState.start(channelId)

    Task.detached {
      var sequence = 0
      while streamState.isActive(channelId) {
        sequence += 1
        let value = Int.random(in: 1...100)
        channel.send(.data(["value": value, "sequence": sequence]))
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
      }
      channel.send(.end)
      channel.close()
    }

    return .ok
  }

  // Stop stream command
  registry.register("stop_stream") { ctx -> CommandResult in
    let args = ctx.decodeArgs()
    if let channelId = args["channelId"] as? String {
      streamState.stop(channelId)
    }
    return .ok
  }

  // IPC handler
  let ipcHandler = createCommandHandler(registry: registry, eventManager: eventManager)
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc", handler: ipcHandler)

  // App protocol with injected channel API
  let securityScript = SecurityScriptGenerator.generateInitScript(config: nil)
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    let html = htmlContent.replacingOccurrences(
      of: "</head>",
      with: "<script>\(securityScript)</script></head>"
    )
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(html.utf8)
    )
  }

  // Create window
  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 700,
    height: 700,
    title: "Channel Streaming Example"
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

  eventManager.register(webview: webview, label: "main")

  window.setVisible(true)
  window.focus()
  webview.show()

  #if os(macOS)
  eventLoop.showApplication()
  #endif

  print("[ChannelStreaming] Running - demonstrates Channel API for streaming data")

  // Event loop
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
