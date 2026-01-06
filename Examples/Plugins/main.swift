// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// Plugins - Demonstrates the Velox plugin system
// Shows how to create plugins with:
// - Command registration
// - State management
// - JavaScript injection
// - Navigation validation
// - Event handling

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Example Plugin State

/// State managed by the analytics plugin
final class AnalyticsState: @unchecked Sendable {
  private let lock = NSLock()
  private var _pageViews: Int = 0
  private var _events: [(name: String, timestamp: Date)] = []

  var pageViews: Int {
    lock.lock()
    defer { lock.unlock() }
    return _pageViews
  }

  func trackPageView() {
    lock.lock()
    defer { lock.unlock() }
    _pageViews += 1
  }

  func trackEvent(_ name: String) {
    lock.lock()
    defer { lock.unlock() }
    _events.append((name: name, timestamp: Date()))
  }

  var recentEvents: [(name: String, timestamp: Date)] {
    lock.lock()
    defer { lock.unlock() }
    return Array(_events.suffix(10))
  }
}

// MARK: - Analytics Plugin

/// A simple analytics plugin that tracks page views and custom events
final class AnalyticsPlugin: VeloxPlugin {
  let name = "com.velox.analytics"

  func setup(context: PluginSetupContext) throws {
    print("[AnalyticsPlugin] Setting up...")

    // Register plugin state
    context.manage(plugin: name, state: AnalyticsState())

    // Register plugin commands
    let commands = context.commands(for: name)

    // Track custom event
    commands.register("track", args: TrackEventArgs.self, returning: TrackResponse.self) { [name] args, ctx in
      let state: AnalyticsState = ctx.stateContainer.require(plugin: name)
      state.trackEvent(args.event)
      print("[AnalyticsPlugin] Tracked event: \(args.event)")
      return TrackResponse(success: true, message: "Event tracked: \(args.event)")
    }

    // Get stats
    commands.register("stats", returning: StatsResponse.self) { [name] ctx in
      let state: AnalyticsState = ctx.stateContainer.require(plugin: name)
      return StatsResponse(
        pageViews: state.pageViews,
        recentEvents: state.recentEvents.map { $0.name }
      )
    }

    // Listen for page_view events from frontend
    context.eventListener.listen("page_view") { event in
      print("[AnalyticsPlugin] Received page_view event: \(event.name)")
    }

    print("[AnalyticsPlugin] Setup complete - registered commands: track, stats")
  }

  func onNavigation(request: NavigationRequest) -> NavigationDecision {
    // Track navigation
    print("[AnalyticsPlugin] Navigation to: \(request.url.absoluteString)")

    // Example: Block navigation to specific domains
    if request.url.host?.contains("blocked.example.com") == true {
      print("[AnalyticsPlugin] Blocked navigation to: \(request.url)")
      return .deny
    }

    return .allow
  }

  func onWebviewReady(context: WebviewReadyContext) -> String? {
    print("[AnalyticsPlugin] Webview ready: \(context.label)")

    // Inject analytics API
    return """
      window.Analytics = {
        track: function(event, data) {
          return Velox.invoke('plugin:com.velox.analytics:track', { event: event, data: data || {} });
        },
        getStats: function() {
          return Velox.invoke('plugin:com.velox.analytics:stats', {});
        }
      };
      console.log('[Analytics] Plugin initialized for webview: \(context.label)');
      """
  }

  func onEvent(_ event: String) {
    // Could track specific events here
  }

  func onDrop() {
    print("[AnalyticsPlugin] Shutting down...")
  }
}

// MARK: - Logger Plugin

/// A simple logging plugin
final class LoggerPlugin: VeloxPlugin {
  let name = "com.velox.logger"

  func setup(context: PluginSetupContext) throws {
    print("[LoggerPlugin] Setting up...")

    context.commands(for: name)
      .register("log", args: LogArgs.self, returning: LogResponse.self) { args, _ in
        let prefix = "[\(args.level.uppercased())]"
        print("\(prefix) \(args.message)")
        return LogResponse(logged: true)
      }

    print("[LoggerPlugin] Setup complete")
  }

  func onWebviewReady(context: WebviewReadyContext) -> String? {
    return """
      window.Logger = {
        log: function(level, message) {
          return Velox.invoke('plugin:com.velox.logger:log', { level: level, message: message });
        },
        info: function(message) { return this.log('info', message); },
        warn: function(message) { return this.log('warn', message); },
        error: function(message) { return this.log('error', message); }
      };
      console.log('[Logger] Plugin initialized');
      """
  }
}

// MARK: - Command Args/Response Types

struct TrackEventArgs: Codable, Sendable {
  let event: String
  let data: [String: String]?
}

struct TrackResponse: Codable, Sendable {
  let success: Bool
  let message: String
}

struct StatsResponse: Codable, Sendable {
  let pageViews: Int
  let recentEvents: [String]
}

struct LogArgs: Codable, Sendable {
  let level: String
  let message: String
}

struct LogResponse: Codable, Sendable {
  let logged: Bool
}

// MARK: - HTML Content

let html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Velox Plugins Demo</title>
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
    .badge {
      display: inline-block;
      background: #4fc3f7;
      color: #1a1a2e;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 12px;
      margin-left: 10px;
    }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
    .card {
      background: rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 20px;
    }
    .card h2 { font-size: 16px; margin-bottom: 15px; color: #4fc3f7; }
    button {
      background: #4fc3f7;
      border: none;
      padding: 10px 20px;
      border-radius: 8px;
      color: #1a1a2e;
      font-weight: 600;
      cursor: pointer;
      margin-right: 10px;
      margin-bottom: 10px;
    }
    button:hover { background: #81d4fa; }
    button.secondary { background: rgba(255,255,255,0.2); color: white; }
    .result {
      margin-top: 15px;
      padding: 10px;
      background: rgba(0,0,0,0.2);
      border-radius: 8px;
      font-family: monospace;
      font-size: 14px;
      white-space: pre-wrap;
    }
    .result.success { border-left: 3px solid #81c784; }
    .result.error { border-left: 3px solid #e57373; }
    input {
      width: 100%;
      padding: 10px;
      border-radius: 8px;
      border: 1px solid rgba(255,255,255,0.2);
      background: rgba(255,255,255,0.1);
      color: white;
      margin-bottom: 10px;
    }
    input::placeholder { color: rgba(255,255,255,0.4); }
  </style>
</head>
<body>
  <h1>Plugins Demo<span class="badge">VeloxPlugin</span></h1>
  <p class="subtitle">Demonstrating the plugin system</p>

  <div class="grid">
    <div class="card">
      <h2>Analytics Plugin</h2>
      <input type="text" id="event-name" placeholder="Event name" value="button_click">
      <button onclick="trackEvent()">Track Event</button>
      <button onclick="getStats()" class="secondary">Get Stats</button>
      <div class="result" id="analytics-result">-</div>
    </div>

    <div class="card">
      <h2>Logger Plugin</h2>
      <input type="text" id="log-message" placeholder="Log message" value="Hello from the frontend!">
      <div>
        <button onclick="logMessage('info')">Info</button>
        <button onclick="logMessage('warn')">Warn</button>
        <button onclick="logMessage('error')">Error</button>
      </div>
      <div class="result" id="logger-result">-</div>
    </div>

    <div class="card">
      <h2>Plugin Commands</h2>
      <p style="color: rgba(255,255,255,0.6); font-size: 14px; margin-bottom: 15px;">
        Plugin commands are namespaced:<br>
        <code>plugin:com.velox.analytics:track</code>
      </p>
      <button onclick="listPlugins()">Show Registered Plugins</button>
      <div class="result" id="plugins-result">-</div>
    </div>
  </div>

  <script>
    // Velox global object for IPC communication
    window.Velox = window.Velox || {};
    if (typeof window.Velox.invoke !== 'function') {
      window.Velox.invoke = async function(command, args = {}) {
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        const text = await response.text();
        if (!response.ok) {
          let message = `Command failed: ${command}`;
          try {
            const err = JSON.parse(text);
            if (err && err.message) message = err.message;
          } catch (_) {}
          throw new Error(message);
        }
        if (!text) return null;
        const data = JSON.parse(text);
        return data ? data.result : null;
      };
    }
  </script>

  <script>
    async function trackEvent() {
      const name = document.getElementById('event-name').value;
      try {
        const result = await window.Analytics.track(name);
        showResult('analytics-result', result, 'success');
      } catch (e) {
        showResult('analytics-result', e, 'error');
      }
    }

    async function getStats() {
      try {
        const result = await window.Analytics.getStats();
        showResult('analytics-result', result, 'success');
      } catch (e) {
        showResult('analytics-result', e, 'error');
      }
    }

    async function logMessage(level) {
      const message = document.getElementById('log-message').value;
      try {
        const result = await window.Logger.log(level, message);
        showResult('logger-result', result, 'success');
      } catch (e) {
        showResult('logger-result', e, 'error');
      }
    }

    function listPlugins() {
      const plugins = [
        'com.velox.analytics - Analytics tracking',
        'com.velox.logger - Logging utilities'
      ];
      showResult('plugins-result', { plugins: plugins }, 'success');
    }

    function showResult(id, data, type) {
      const el = document.getElementById(id);
      el.textContent = JSON.stringify(data, null, 2);
      el.className = 'result ' + type;
    }

    // Log that plugins are ready
    if (window.Logger) {
      window.Logger.info('Plugins demo loaded');
    }
  </script>
</body>
</html>
"""

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("Plugins example must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let builder: VeloxAppBuilder
  do {
    builder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("Plugins failed to load velox.json: \(error)")
  }

  builder.plugins {
    AnalyticsPlugin()
    LoggerPlugin()
  }

  // Register app:// protocol to serve HTML
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html"],
      body: Data(html.utf8)
    )
  }

  print("[Plugins] Building app...")

  print("[Plugins] Application started")
  print("[Plugins] Registered commands: \(builder.commandRegistry.commandNames.sorted().joined(separator: ", "))")

  do {
    try builder
      .registerProtocol("app", handler: appHandler)
      .registerCommands(builder.commandRegistry)
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("Plugins failed to start: \(error)")
  }

  print("[Plugins] Exiting")
}

main()
