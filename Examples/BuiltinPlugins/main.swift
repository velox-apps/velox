// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// BuiltinPlugins - Demonstrates Velox built-in plugins
//
// This example shows how to use the pre-built plugins:
// - DialogPlugin: File dialogs and message boxes
// - ClipboardPlugin: System clipboard read/write
// - NotificationPlugin: Native notifications
// - ShellPlugin: Execute system commands
// - OSInfoPlugin: Operating system information
// - ProcessPlugin: Current process management
// - OpenerPlugin: Open files/URLs with external apps

import Foundation
import VeloxRuntime
import VeloxRuntimeWry
import VeloxPlugins

// MARK: - HTML Content

let html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Built-in Plugins Demo</title>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #eee;
      min-height: 100vh;
    }
    h1 { margin-top: 0; color: #fff; }
    h2 { color: #7dd3fc; margin-top: 24px; margin-bottom: 12px; font-size: 1.1rem; }
    .section {
      background: rgba(255,255,255,0.05);
      border-radius: 12px;
      padding: 16px;
      margin-bottom: 16px;
    }
    button {
      background: #3b82f6;
      color: white;
      border: none;
      padding: 8px 16px;
      border-radius: 6px;
      cursor: pointer;
      margin: 4px;
      font-size: 14px;
    }
    button:hover { background: #2563eb; }
    button:active { transform: scale(0.98); }
    .output {
      background: rgba(0,0,0,0.3);
      border-radius: 8px;
      padding: 12px;
      margin-top: 12px;
      font-family: "SF Mono", Monaco, monospace;
      font-size: 13px;
      max-height: 200px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    input[type="text"] {
      padding: 8px 12px;
      border: 1px solid #444;
      border-radius: 6px;
      background: rgba(0,0,0,0.3);
      color: #fff;
      font-size: 14px;
      width: 200px;
      margin: 4px;
    }
    .row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin: 8px 0; }
  </style>
</head>
<body>
  <h1>Built-in Plugins Demo</h1>

  <!-- Dialog Plugin -->
  <div class="section">
    <h2>Dialog Plugin</h2>
    <div class="row">
      <button onclick="openFile()">Open File</button>
      <button onclick="saveFile()">Save File</button>
      <button onclick="showMessage()">Message</button>
      <button onclick="showAsk()">Ask (Yes/No)</button>
      <button onclick="showConfirm()">Confirm (Ok/Cancel)</button>
    </div>
    <div id="dialog-output" class="output">Click a button to test dialog plugin...</div>
  </div>

  <!-- Clipboard Plugin -->
  <div class="section">
    <h2>Clipboard Plugin</h2>
    <div class="row">
      <input type="text" id="clipboard-text" placeholder="Text to copy..." value="Hello from Velox!">
      <button onclick="writeClipboard()">Copy to Clipboard</button>
      <button onclick="readClipboard()">Read Clipboard</button>
      <button onclick="clearClipboard()">Clear</button>
    </div>
    <div id="clipboard-output" class="output">Clipboard operations will show here...</div>
  </div>

  <!-- Notification Plugin -->
  <div class="section">
    <h2>Notification Plugin</h2>
    <div class="row">
      <input type="text" id="notif-title" placeholder="Title" value="Hello!">
      <input type="text" id="notif-body" placeholder="Body" value="This is a test notification">
      <button onclick="sendNotification()">Send Notification</button>
      <button onclick="checkPermission()">Check Permission</button>
      <button onclick="requestPermission()">Request Permission</button>
    </div>
    <div id="notif-output" class="output">Notification status will show here...</div>
  </div>

  <!-- Shell Plugin -->
  <div class="section">
    <h2>Shell Plugin</h2>
    <div class="row">
      <input type="text" id="shell-cmd" placeholder="Command" value="/bin/ls">
      <input type="text" id="shell-args" placeholder="Args (comma-separated)" value="-la,/tmp">
      <button onclick="executeCommand()">Execute</button>
    </div>
    <div id="shell-output" class="output">Command output will show here...</div>
  </div>

  <!-- OS Info Plugin -->
  <div class="section">
    <h2>OS Info Plugin</h2>
    <div class="row">
      <button onclick="getOSInfo()">Get All Info</button>
      <button onclick="getPlatform()">Platform</button>
      <button onclick="getArch()">Architecture</button>
      <button onclick="getHostname()">Hostname</button>
    </div>
    <div id="os-output" class="output">OS information will show here...</div>
  </div>

  <!-- Process Plugin -->
  <div class="section">
    <h2>Process Plugin</h2>
    <div class="row">
      <button onclick="getProcessInfo()">Get Process Info</button>
      <button onclick="getPid()">PID</button>
      <button onclick="getCwd()">Working Dir</button>
      <button onclick="getEnvAll()">All Env Vars</button>
    </div>
    <div id="process-output" class="output">Process information will show here...</div>
  </div>

  <!-- Opener Plugin -->
  <div class="section">
    <h2>Opener Plugin</h2>
    <div class="row">
      <input type="text" id="open-url" placeholder="URL" value="https://tauri.app">
      <button onclick="openUrl()">Open URL</button>
    </div>
    <div class="row">
      <input type="text" id="open-path" placeholder="Path" value="/Applications">
      <button onclick="openPath()">Open Path</button>
      <button onclick="revealPath()">Reveal in Finder</button>
    </div>
    <div id="opener-output" class="output">Opener operations will show here...</div>
  </div>

  <script>
    // Velox IPC invoke helper
    async function invoke(command, args = {}) {
      if (window.Velox && typeof window.Velox.invoke === 'function') {
        return window.Velox.invoke(command, args);
      }
      const response = await fetch(`ipc://localhost/${command}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(args)
      });
      if (!response.ok) {
        const error = await response.text();
        throw new Error(error || `Command failed: ${command}`);
      }
      const text = await response.text();
      if (!text) return null;
      const data = JSON.parse(text);
      return data ? data.result : null;
    }

    function log(elementId, message) {
      const el = document.getElementById(elementId);
      const time = new Date().toLocaleTimeString();
      el.textContent = `[${time}] ${typeof message === 'object' ? JSON.stringify(message, null, 2) : message}`;
    }

    // Dialog Plugin
    async function openFile() {
      try {
        const result = await invoke('plugin:dialog:open', {
          title: 'Select a file',
          multiple: true
        });
        log('dialog-output', `Selected: ${result ? result.join(', ') : 'cancelled'}`);
      } catch (e) { log('dialog-output', `Error: ${e}`); }
    }

    async function saveFile() {
      try {
        const result = await invoke('plugin:dialog:save', {
          title: 'Save file as',
          defaultName: 'untitled.txt'
        });
        log('dialog-output', `Save path: ${result || 'cancelled'}`);
      } catch (e) { log('dialog-output', `Error: ${e}`); }
    }

    async function showMessage() {
      try {
        await invoke('plugin:dialog:message', {
          title: 'Information',
          message: 'This is a message dialog!',
          kind: 'info'
        });
        log('dialog-output', 'Message dialog closed');
      } catch (e) { log('dialog-output', `Error: ${e}`); }
    }

    async function showAsk() {
      try {
        const result = await invoke('plugin:dialog:ask', {
          title: 'Question',
          message: 'Do you like Velox?',
          kind: 'info'
        });
        log('dialog-output', `Answer: ${result ? 'Yes!' : 'No'}`);
      } catch (e) { log('dialog-output', `Error: ${e}`); }
    }

    async function showConfirm() {
      try {
        const result = await invoke('plugin:dialog:confirm', {
          title: 'Confirm',
          message: 'Are you sure you want to continue?',
          kind: 'warning'
        });
        log('dialog-output', `Confirmed: ${result}`);
      } catch (e) { log('dialog-output', `Error: ${e}`); }
    }

    // Clipboard Plugin
    async function writeClipboard() {
      try {
        const text = document.getElementById('clipboard-text').value;
        await invoke('plugin:clipboard:writeText', { text });
        log('clipboard-output', `Copied to clipboard: "${text}"`);
      } catch (e) { log('clipboard-output', `Error: ${e}`); }
    }

    async function readClipboard() {
      try {
        const text = await invoke('plugin:clipboard:readText', {});
        log('clipboard-output', `Clipboard contents: "${text || '(empty)'}"`);
      } catch (e) { log('clipboard-output', `Error: ${e}`); }
    }

    async function clearClipboard() {
      try {
        await invoke('plugin:clipboard:clear', {});
        log('clipboard-output', 'Clipboard cleared');
      } catch (e) { log('clipboard-output', `Error: ${e}`); }
    }

    // Notification Plugin
    async function checkPermission() {
      try {
        const granted = await invoke('plugin:notification:isPermissionGranted', {});
        log('notif-output', `Permission granted: ${granted}`);
      } catch (e) { log('notif-output', `Error: ${e}`); }
    }

    async function requestPermission() {
      try {
        const granted = await invoke('plugin:notification:requestPermission', {});
        log('notif-output', `Permission ${granted ? 'granted' : 'denied'}`);
      } catch (e) { log('notif-output', `Error: ${e}`); }
    }

    async function sendNotification() {
      try {
        const title = document.getElementById('notif-title').value;
        const body = document.getElementById('notif-body').value;
        const success = await invoke('plugin:notification:sendNotification', { title, body });
        log('notif-output', success ? 'Notification sent!' : 'Failed to send notification');
      } catch (e) { log('notif-output', `Error: ${e}`); }
    }

    // Shell Plugin
    async function executeCommand() {
      try {
        const program = document.getElementById('shell-cmd').value;
        const argsStr = document.getElementById('shell-args').value;
        const args = argsStr ? argsStr.split(',').map(s => s.trim()) : [];
        const result = await invoke('plugin:shell:execute', { program, args });
        log('shell-output', `Exit code: ${result.code}\\n\\nSTDOUT:\\n${result.stdout}\\n\\nSTDERR:\\n${result.stderr}`);
      } catch (e) { log('shell-output', `Error: ${e}`); }
    }

    // OS Info Plugin
    async function getOSInfo() {
      try {
        const info = await invoke('plugin:os:info', {});
        log('os-output', info);
      } catch (e) { log('os-output', `Error: ${e}`); }
    }

    async function getPlatform() {
      try {
        const platform = await invoke('plugin:os:platform', {});
        log('os-output', `Platform: ${platform}`);
      } catch (e) { log('os-output', `Error: ${e}`); }
    }

    async function getArch() {
      try {
        const arch = await invoke('plugin:os:arch', {});
        log('os-output', `Architecture: ${arch}`);
      } catch (e) { log('os-output', `Error: ${e}`); }
    }

    async function getHostname() {
      try {
        const hostname = await invoke('plugin:os:hostname', {});
        log('os-output', `Hostname: ${hostname}`);
      } catch (e) { log('os-output', `Error: ${e}`); }
    }

    // Process Plugin
    async function getProcessInfo() {
      try {
        const [pid, cwd, execPath] = await Promise.all([
          invoke('plugin:process:pid', {}),
          invoke('plugin:process:cwd', {}),
          invoke('plugin:process:executablePath', {})
        ]);
        log('process-output', `PID: ${pid}\\nCWD: ${cwd}\\nExecutable: ${execPath}`);
      } catch (e) { log('process-output', `Error: ${e}`); }
    }

    async function getPid() {
      try {
        const pid = await invoke('plugin:process:pid', {});
        log('process-output', `PID: ${pid}`);
      } catch (e) { log('process-output', `Error: ${e}`); }
    }

    async function getCwd() {
      try {
        const cwd = await invoke('plugin:process:cwd', {});
        log('process-output', `Working Directory: ${cwd}`);
      } catch (e) { log('process-output', `Error: ${e}`); }
    }

    async function getEnvAll() {
      try {
        const env = await invoke('plugin:process:envAll', {});
        log('process-output', env);
      } catch (e) { log('process-output', `Error: ${e}`); }
    }

    // Opener Plugin
    async function openUrl() {
      try {
        const url = document.getElementById('open-url').value;
        const success = await invoke('plugin:opener:openUrl', { url });
        log('opener-output', success ? `Opened URL: ${url}` : 'Failed to open URL');
      } catch (e) { log('opener-output', `Error: ${e}`); }
    }

    async function openPath() {
      try {
        const path = document.getElementById('open-path').value;
        const success = await invoke('plugin:opener:openPath', { path });
        log('opener-output', success ? `Opened path: ${path}` : 'Failed to open path');
      } catch (e) { log('opener-output', `Error: ${e}`); }
    }

    async function revealPath() {
      try {
        const path = document.getElementById('open-path').value;
        const success = await invoke('plugin:opener:revealPath', { path });
        log('opener-output', success ? `Revealed in Finder: ${path}` : 'Failed to reveal path');
      } catch (e) { log('opener-output', `Error: ${e}`); }
    }
  </script>
</body>
</html>
"""

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("BuiltinPlugins example must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let builder: VeloxAppBuilder
  do {
    builder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("BuiltinPlugins failed to load velox.json: \(error)")
  }

  builder.plugins {
    DialogPlugin()
    ClipboardPlugin()
    NotificationPlugin()
    ShellPlugin()
    OSInfoPlugin()
    ProcessPlugin()
    OpenerPlugin()
  }

  // Register app:// protocol to serve HTML
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(html.utf8)
    )
  }

  print("[BuiltinPlugins] Building app...")

  print("[BuiltinPlugins] Application started")
  print("[BuiltinPlugins] Registered commands: \(builder.commandRegistry.commandNames.sorted().joined(separator: ", "))")

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
    fatalError("BuiltinPlugins failed to start: \(error)")
  }

  print("[BuiltinPlugins] Exiting")
}

main()
