// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Application State

/// Shared state accessible by commands
final class AppState: @unchecked Sendable {
  private let lock = NSLock()
  private var _counter: Int = 0
  private var _label: String = "Velox!"

  var counter: Int {
    lock.lock()
    defer { lock.unlock() }
    return _counter
  }

  var label: String {
    lock.lock()
    defer { lock.unlock() }
    return _label
  }

  func incrementCounter() -> Int {
    lock.lock()
    defer { lock.unlock() }
    _counter += 1
    return _counter
  }

  func setLabel(_ newLabel: String) {
    lock.lock()
    defer { lock.unlock() }
    _label = newLabel
  }
}

// MARK: - Command Handlers

/// Simple command that just prints and returns success
func simpleCommand(args: [String: Any]) -> [String: Any] {
  let argument = args["theArgument"] as? String ?? "(no argument)"
  print("[Command] simple_command: \(argument)")
  return ["result": "ok"]
}

/// Command that returns a value
func echoCommand(args: [String: Any]) -> [String: Any] {
  let argument = args["theArgument"] as? String ?? ""
  print("[Command] echo: \(argument)")
  return ["result": argument]
}

/// Command that can fail
func fallibleCommand(args: [String: Any]) -> [String: Any] {
  let argument = args["theArgument"] as? String ?? ""
  print("[Command] fallible_command: \(argument)")

  if argument.isEmpty {
    return ["error": "EmptyArgument", "message": "The argument cannot be empty"]
  }
  return ["result": argument.uppercased()]
}

/// Command that accesses shared state
func statefulCommand(args: [String: Any], state: AppState) -> [String: Any] {
  let argument = args["theArgument"] as? String
  print("[Command] stateful_command: \(argument ?? "nil") | state: counter=\(state.counter), label=\(state.label)")
  return ["result": ["argument": argument as Any, "counter": state.counter, "label": state.label]]
}

/// Command that modifies state
func incrementCommand(state: AppState) -> [String: Any] {
  let newValue = state.incrementCounter()
  print("[Command] increment: new value = \(newValue)")
  return ["result": newValue]
}

/// Command with complex argument structure
func personCommand(args: [String: Any]) -> [String: Any] {
  guard let person = args["person"] as? [String: Any],
        let name = person["name"] as? String,
        let age = person["age"] as? Int else {
    return ["error": "InvalidArgument", "message": "Expected person object with name and age"]
  }
  print("[Command] person_command: name=\(name), age=\(age)")
  return ["result": "Hello \(name), you are \(age) years old!"]
}

/// Command with array argument
func sumCommand(args: [String: Any]) -> [String: Any] {
  guard let numbers = args["numbers"] as? [Int] else {
    return ["error": "InvalidArgument", "message": "Expected numbers array"]
  }
  let sum = numbers.reduce(0, +)
  print("[Command] sum_command: \(numbers) = \(sum)")
  return ["result": sum]
}

/// Async-style command (simulated with delay)
func asyncCommand(args: [String: Any]) -> [String: Any] {
  let argument = args["theArgument"] as? String ?? ""
  print("[Command] async_command: starting with '\(argument)'")
  // In a real app, this would be async
  Thread.sleep(forTimeInterval: 0.1)
  print("[Command] async_command: completed")
  return ["result": "Processed: \(argument)"]
}

/// Command that returns raw data (simulating binary response)
func rawDataCommand() -> [String: Any] {
  let data = "This is raw data from the command handler"
  print("[Command] raw_data_command")
  return ["result": data, "type": "raw"]
}

// MARK: - IPC Router

func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request, state: AppState) -> VeloxRuntimeWry.CustomProtocol.Response? {
  guard let url = URL(string: request.url) else {
    return errorResponse(error: "InvalidURL", message: "Invalid request URL")
  }

  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  var args: [String: Any] = [:]
  if !request.body.isEmpty,
     let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
    args = json
  }

  print("[IPC] Received command: \(command)")

  let response: [String: Any]
  switch command {
  case "simple_command":
    response = simpleCommand(args: args)
  case "echo":
    response = echoCommand(args: args)
  case "fallible_command":
    response = fallibleCommand(args: args)
  case "stateful_command":
    response = statefulCommand(args: args, state: state)
  case "increment":
    response = incrementCommand(state: state)
  case "person_command":
    response = personCommand(args: args)
  case "sum_command":
    response = sumCommand(args: args)
  case "async_command":
    response = asyncCommand(args: args)
  case "raw_data_command":
    response = rawDataCommand()
  default:
    return errorResponse(error: "UnknownCommand", message: "Unknown command: \(command)")
  }

  return jsonResponse(response)
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
    <title>Velox Commands</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 800px;
        margin: 30px auto;
        padding: 20px;
      }
      h1 { color: #333; border-bottom: 2px solid #007AFF; padding-bottom: 10px; }
      h3 { color: #555; margin-top: 25px; }
      .response-box {
        background: #f5f5f7;
        border-radius: 8px;
        padding: 15px;
        margin: 15px 0;
        font-family: monospace;
        white-space: pre-wrap;
        word-break: break-all;
      }
      .success { border-left: 4px solid #34c759; }
      .error { border-left: 4px solid #ff3b30; }
      button {
        padding: 10px 16px;
        margin: 5px;
        font-size: 14px;
        background-color: #007AFF;
        color: white;
        border: none;
        border-radius: 6px;
        cursor: pointer;
        transition: background-color 0.2s;
      }
      button:hover { background-color: #0056b3; }
      .button-group { margin: 10px 0; }
      #response { min-height: 60px; }
    </style>
  </head>
  <body>
    <h1>Velox Commands</h1>
    <p>This example demonstrates various IPC command patterns in Swift.</p>

    <div class="response-box" id="response">Click a button to run a command...</div>

    <h3>Simple Commands</h3>
    <div class="button-group">
      <button onclick="runCommand('simple_command', {theArgument: 'Hello!'})">Simple Command</button>
      <button onclick="runCommand('echo', {theArgument: 'Echo this!'})">Echo</button>
    </div>

    <h3>Fallible Commands (Result)</h3>
    <div class="button-group">
      <button onclick="runCommand('fallible_command', {theArgument: 'valid'})">Fallible (Valid)</button>
      <button onclick="runCommand('fallible_command', {theArgument: ''})">Fallible (Empty - Error)</button>
    </div>

    <h3>Stateful Commands</h3>
    <div class="button-group">
      <button onclick="runCommand('stateful_command', {theArgument: 'test'})">Read State</button>
      <button onclick="runCommand('increment', {})">Increment Counter</button>
    </div>

    <h3>Complex Arguments</h3>
    <div class="button-group">
      <button onclick="runCommand('person_command', {person: {name: 'Ferris', age: 6}})">Person Struct</button>
      <button onclick="runCommand('sum_command', {numbers: [1, 2, 3, 4, 5]})">Sum Array</button>
    </div>

    <h3>Async-style Commands</h3>
    <div class="button-group">
      <button onclick="runCommand('async_command', {theArgument: 'async data'})">Async Command</button>
      <button onclick="runCommand('raw_data_command', {})">Raw Data</button>
    </div>

    <h3>Error Handling</h3>
    <div class="button-group">
      <button onclick="runCommand('unknown_command', {})">Unknown Command</button>
      <button onclick="runCommand('person_command', {person: 'invalid'})">Invalid Arguments</button>
    </div>

    <script>
      async function invoke(command, args = {}) {
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        return response.json();
      }

      async function runCommand(command, args) {
        const responseEl = document.getElementById('response');
        responseEl.className = 'response-box';
        responseEl.textContent = `Calling ${command}...`;

        try {
          const result = await invoke(command, args);
          if (result.error) {
            responseEl.className = 'response-box error';
            responseEl.textContent = `Error: ${result.error}\\n${result.message || ''}`;
          } else {
            responseEl.className = 'response-box success';
            responseEl.textContent = `Command: ${command}\\nResult: ${JSON.stringify(result.result, null, 2)}`;
          }
        } catch (err) {
          responseEl.className = 'response-box error';
          responseEl.textContent = `Fetch Error: ${err.message}`;
        }
      }

      console.log('Velox Commands example loaded!');
    </script>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("Commands example must run on the main thread")
  }

  // Initialize shared state
  let state = AppState()

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // IPC protocol for commands
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    handleInvoke(request: request, state: state)
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

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 900,
    height: 700,
    title: "Velox Commands Example"
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

  // Run event loop
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
