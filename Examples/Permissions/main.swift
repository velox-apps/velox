// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// Permissions - Demonstrates the capability/permission system
// Shows two windows with different access levels:
// - "main" window: Full access to all commands
// - "limited" window: Restricted to only "greet" command

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Response Types

struct GreetResponse: Codable, Sendable {
  let message: String
}

struct SecretResponse: Codable, Sendable {
  let secret: String
  let accessedFrom: String
}

struct FileReadResponse: Codable, Sendable {
  let path: String
  let size: Int
  let allowed: Bool
}

struct SensitiveDataResponse: Codable, Sendable {
  let data: String
  let classification: String
}

// MARK: - HTML Content

func mainWindowHTML() -> String {
  """
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <title>Main Window - Full Access</title>
    <style>
      body { font-family: -apple-system, system-ui, sans-serif; padding: 20px; max-width: 600px; margin: 0 auto; }
      h1 { color: #1a1a1a; border-bottom: 2px solid #007AFF; padding-bottom: 10px; }
      h2 { color: #333; margin-top: 30px; }
      .access-level { background: #e8f5e9; color: #2e7d32; padding: 10px 15px; border-radius: 8px; margin-bottom: 20px; }
      button { background: #007AFF; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; margin: 5px; }
      button:hover { background: #0056b3; }
      .result { margin: 15px 0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; }
      .success { background: #e8f5e9; border: 1px solid #4caf50; }
      .error { background: #ffebee; border: 1px solid #f44336; color: #c62828; }
      .info { background: #e3f2fd; border: 1px solid #2196f3; }
      .commands { display: flex; flex-wrap: wrap; gap: 5px; margin: 15px 0; }
    </style>
  </head>
  <body>
    <h1>Main Window</h1>
    <div class="access-level">Access Level: FULL</div>

    <p>This window has full access via the "main-full-access" capability.</p>

    <h2>Available Commands</h2>
    <div class="commands">
      <button onclick="testGreet()">greet</button>
      <button onclick="testSecret()">get_secret</button>
      <button onclick="testSensitive()">get_sensitive_data</button>
      <button onclick="testReadAllowed()">read_file (allowed path)</button>
      <button onclick="testReadDenied()">read_file (denied path)</button>
    </div>

    <div id="result" class="result info">Click a button to test a command...</div>

    <script>
      async function invoke(cmd, args = {}) {
        const body = JSON.stringify(args);
        const response = await fetch(`ipc://localhost/${cmd}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: body
        });
        const data = await response.json();
        return { ok: response.ok, data };
      }

      function showResult(ok, data) {
        const el = document.getElementById('result');
        el.textContent = JSON.stringify(data, null, 2);
        el.className = 'result ' + (ok ? 'success' : 'error');
      }

      async function testGreet() {
        const { ok, data } = await invoke('greet', { name: 'Main Window User' });
        showResult(ok, data);
      }

      async function testSecret() {
        const { ok, data } = await invoke('get_secret');
        showResult(ok, data);
      }

      async function testSensitive() {
        const { ok, data } = await invoke('get_sensitive_data');
        showResult(ok, data);
      }

      async function testReadAllowed() {
        const { ok, data } = await invoke('read_file', { path: '/tmp/test.txt' });
        showResult(ok, data);
      }

      async function testReadDenied() {
        const { ok, data } = await invoke('read_file', { path: '/etc/passwd' });
        showResult(ok, data);
      }
    </script>
  </body>
  </html>
  """
}

func limitedWindowHTML() -> String {
  """
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <title>Limited Window - Restricted Access</title>
    <style>
      body { font-family: -apple-system, system-ui, sans-serif; padding: 20px; max-width: 600px; margin: 0 auto; }
      h1 { color: #1a1a1a; border-bottom: 2px solid #ff9800; padding-bottom: 10px; }
      h2 { color: #333; margin-top: 30px; }
      .access-level { background: #fff3e0; color: #e65100; padding: 10px 15px; border-radius: 8px; margin-bottom: 20px; }
      button { background: #ff9800; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; margin: 5px; }
      button:hover { background: #f57c00; }
      button.denied { background: #9e9e9e; }
      .result { margin: 15px 0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; }
      .success { background: #e8f5e9; border: 1px solid #4caf50; }
      .error { background: #ffebee; border: 1px solid #f44336; color: #c62828; }
      .info { background: #e3f2fd; border: 1px solid #2196f3; }
      .commands { display: flex; flex-wrap: wrap; gap: 5px; margin: 15px 0; }
      .note { background: #fff8e1; padding: 15px; border-radius: 8px; margin: 20px 0; }
    </style>
  </head>
  <body>
    <h1>Limited Window</h1>
    <div class="access-level">Access Level: LIMITED</div>

    <p>This window only has access to the "greet" command via the "limited-access" capability.</p>

    <div class="note">
      <strong>Note:</strong> Commands other than "greet" will return PermissionDenied errors.
    </div>

    <h2>Test Commands</h2>
    <div class="commands">
      <button onclick="testGreet()">greet (allowed)</button>
      <button class="denied" onclick="testSecret()">get_secret (denied)</button>
      <button class="denied" onclick="testSensitive()">get_sensitive_data (denied)</button>
      <button class="denied" onclick="testRead()">read_file (denied)</button>
    </div>

    <div id="result" class="result info">Click a button to test a command...</div>

    <script>
      async function invoke(cmd, args = {}) {
        const body = JSON.stringify(args);
        const response = await fetch(`ipc://localhost/${cmd}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: body
        });
        const data = await response.json();
        return { ok: response.ok, data };
      }

      function showResult(ok, data) {
        const el = document.getElementById('result');
        el.textContent = JSON.stringify(data, null, 2);
        el.className = 'result ' + (ok ? 'success' : 'error');
      }

      async function testGreet() {
        const { ok, data } = await invoke('greet', { name: 'Limited Window User' });
        showResult(ok, data);
      }

      async function testSecret() {
        const { ok, data } = await invoke('get_secret');
        showResult(ok, data);
      }

      async function testSensitive() {
        const { ok, data } = await invoke('get_sensitive_data');
        showResult(ok, data);
      }

      async function testRead() {
        const { ok, data } = await invoke('read_file', { path: '/tmp/test.txt' });
        showResult(ok, data);
      }
    </script>
  </body>
  </html>
  """
}

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("Permissions example must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let appBuilder: VeloxAppBuilder
  do {
    appBuilder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("Permissions failed to load velox.json: \(error)")
  }

  print("[Permissions] Registered capabilities: \(appBuilder.permissionManager.capabilityIdentifiers)")
  print("[Permissions] Registered permissions: \(appBuilder.permissionManager.permissionIdentifiers)")

  // Create command registry
  let registry = appBuilder.commandRegistry

  registry.register("greet", returning: GreetResponse.self) { ctx in
    let args = ctx.decodeArgs()
    let name = args["name"] as? String ?? "World"
    return GreetResponse(message: "Hello, \(name)!")
  }

  registry.register("get_secret", returning: SecretResponse.self) { ctx in
    SecretResponse(
      secret: "TOP_SECRET_VALUE_12345",
      accessedFrom: ctx.webviewId
    )
  }

  registry.register("get_sensitive_data", returning: SensitiveDataResponse.self) { _ in
    SensitiveDataResponse(
      data: "Sensitive internal data...",
      classification: "CONFIDENTIAL"
    )
  }

  registry.register("read_file", returning: FileReadResponse.self) { ctx in
    let args = ctx.decodeArgs()
    let path = args["path"] as? String ?? "/unknown"
    // In a real app, you'd actually read the file here
    // The permission manager already validated the path scope
    return FileReadResponse(
      path: path,
      size: 1024,
      allowed: true
    )
  }

  print("[Permissions] Registered commands: \(registry.commandNames.sorted())")

  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    let label = appBuilder.eventManager.resolveLabel(request.webviewIdentifier)
    let html = label == "limited" ? limitedWindowHTML() : mainWindowHTML()
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(html.utf8)
    )
  }

  print("[Permissions] Application started with two windows")
  print("[Permissions] - Main window: Full access to all commands")
  print("[Permissions] - Limited window: Access only to 'greet' command")

  do {
    try appBuilder
      .registerProtocol("app", handler: appHandler)
      .registerCommands(registry)
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("Permissions failed to start: \(error)")
  }

  print("[Permissions] Exiting")
}

main()
