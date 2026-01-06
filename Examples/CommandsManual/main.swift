// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// CommandsManual - Demonstrates manual IPC command routing
// Uses switch statement and [String: Any] dictionaries (untyped)
// Compare with Commands (macro) and CommandsManualRegistry (DSL)

import Foundation
import VeloxRuntimeWry

// MARK: - Asset Bundle

struct AssetBundle {
  let basePath: String

  init() {
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    let possiblePaths = [
      "\(executableDir)/../../../Examples/CommandsManual/assets",
      "\(executableDir)/assets",
      "./Examples/CommandsManual/assets",
      "./assets"
    ]

    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: "\(path)/index.html") {
        self.basePath = path
        print("[CommandsManual] Assets found at: \(path)")
        return
      }
    }

    self.basePath = "./Examples/CommandsManual/assets"
    print("[CommandsManual] Using default assets path: \(basePath)")
  }

  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    var cleanPath = path
    if cleanPath.hasPrefix("/") { cleanPath = String(cleanPath.dropFirst()) }
    if cleanPath.isEmpty { cleanPath = "index.html" }

    let fullPath = "\(basePath)/\(cleanPath)"
    guard let data = FileManager.default.contents(atPath: fullPath) else {
      print("[CommandsManual] Asset not found: \(fullPath)")
      return nil
    }

    let ext = (cleanPath as NSString).pathExtension.lowercased()
    let mimeType: String
    switch ext {
    case "html": mimeType = "text/html"
    case "css": mimeType = "text/css"
    case "js": mimeType = "application/javascript"
    case "json": mimeType = "application/json"
    case "png": mimeType = "image/png"
    case "jpg", "jpeg": mimeType = "image/jpeg"
    case "svg": mimeType = "image/svg+xml"
    default: mimeType = "application/octet-stream"
    }
    return (data, mimeType)
  }
}

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

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("CommandsManual example must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()

  // Load assets from external files
  let assets = AssetBundle()

  // Initialize shared state
  let state = AppState()

  // IPC protocol for commands
  let ipcHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    handleInvoke(request: request, state: state)
  }

  // App protocol serves assets from external files
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    guard let url = URL(string: request.url),
          let asset = assets.loadAsset(path: url.path) else {
      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 404,
        headers: ["Content-Type": "text/plain"],
        body: Data("Not Found".utf8)
      )
    }
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": asset.mimeType],
      mimeType: asset.mimeType,
      body: asset.data
    )
  }

  do {
    let app = try VeloxAppBuilder(directory: exampleDir)
      .registerProtocol("ipc", handler: ipcHandler)
      .registerProtocol("app", handler: appHandler)

    try app.run { event in
      switch event {
      case .windowCloseRequested, .userExit:
        return .exit

      default:
        return .wait
      }
    }
  } catch {
    fatalError("CommandsManual failed to start: \(error)")
  }
}

main()
