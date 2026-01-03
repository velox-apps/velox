// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// CommandsManualRegistry - Demonstrates the type-safe command system with DSL
// - Typed arguments with automatic JSON decoding
// - State injection via CommandContext
// - Result builder DSL for command registration
// - Error handling with CommandError
// Compare with CommandsManual (switch) and Commands (macro)

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Asset Bundle

struct AssetBundle {
  let basePath: String

  init() {
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    let possiblePaths = [
      "\(executableDir)/../../../Examples/CommandsManualRegistry/assets",
      "\(executableDir)/assets",
      "./Examples/CommandsManualRegistry/assets",
      "./assets"
    ]

    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: "\(path)/index.html") {
        self.basePath = path
        print("[CommandsManualRegistry] Assets found at: \(path)")
        return
      }
    }

    self.basePath = "./Examples/CommandsManualRegistry/assets"
    print("[CommandsManualRegistry] Using default assets path: \(basePath)")
  }

  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    var cleanPath = path
    if cleanPath.hasPrefix("/") { cleanPath = String(cleanPath.dropFirst()) }
    if cleanPath.isEmpty { cleanPath = "index.html" }

    let fullPath = "\(basePath)/\(cleanPath)"
    guard let data = FileManager.default.contents(atPath: fullPath) else {
      print("[CommandsManualRegistry] Asset not found: \(fullPath)")
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

// MARK: - Typed Arguments

/// Arguments for the greet command
struct GreetArgs: Codable, Sendable {
  let name: String
}

/// Arguments for the add command
struct AddArgs: Codable, Sendable {
  let a: Int
  let b: Int
}

/// Arguments for the person command
struct PersonArgs: Codable, Sendable {
  let person: Person
}

struct Person: Codable, Sendable {
  let name: String
  let age: Int
  let email: String?
}

/// Arguments for the divide command (can fail)
struct DivideArgs: Codable, Sendable {
  let numerator: Double
  let denominator: Double
}

// MARK: - Response Types

struct GreetResponse: Codable, Sendable {
  let message: String
}

struct MathResponse: Codable, Sendable {
  let result: Double
}

struct PersonResponse: Codable, Sendable {
  let greeting: String
  let isAdult: Bool
}

struct CounterResponse: Codable, Sendable {
  let value: Int
  let label: String
}

struct PingResponse: Codable, Sendable {
  let pong: Bool
  let timestamp: TimeInterval
}

// MARK: - Application State

final class AppState: @unchecked Sendable {
  private let lock = NSLock()
  private var _counter: Int = 0
  private var _label: String = "Counter"

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

  func increment() -> Int {
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

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("CommandsManualRegistry example must run on the main thread")
  }

  // Load assets from external files
  let assets = AssetBundle()

  // Create state container with app state
  let stateContainer = StateContainer()
    .manage(AppState())

  // Create command registry using the DSL
  let registry = commands {
    // Simple command with typed args and return type
    command("greet", args: GreetArgs.self, returning: GreetResponse.self) { args, _ in
      GreetResponse(message: "Hello, \(args.name)! Welcome to Velox Commands2.")
    }

    // Math command with multiple args
    command("add", args: AddArgs.self, returning: MathResponse.self) { args, _ in
      MathResponse(result: Double(args.a + args.b))
    }

    // Fallible command - division by zero throws
    command("divide", args: DivideArgs.self, returning: MathResponse.self) { args, _ in
      guard args.denominator != 0 else {
        throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
      }
      return MathResponse(result: args.numerator / args.denominator)
    }

    // Complex nested argument
    command("person", args: PersonArgs.self, returning: PersonResponse.self) { args, _ in
      let person = args.person
      let greeting = "Hello \(person.name)! You are \(person.age) years old."
      return PersonResponse(greeting: greeting, isAdult: person.age >= 18)
    }

    // Command that uses managed state
    command("increment", returning: CounterResponse.self) { context in
      let state: AppState = context.requireState()
      let newValue = state.increment()
      return CounterResponse(value: newValue, label: state.label)
    }

    command("get_counter", returning: CounterResponse.self) { context in
      let state: AppState = context.requireState()
      return CounterResponse(value: state.counter, label: state.label)
    }

    // Simple ping command
    command("ping", returning: PingResponse.self) { _ in
      PingResponse(pong: true, timestamp: Date().timeIntervalSince1970)
    }
  }

  print("[CommandsManualRegistry] Registered commands: \(registry.commandNames.sorted().joined(separator: ", "))")

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // Create IPC handler from registry
  let ipcHandler = createCommandHandler(registry: registry, stateContainer: stateContainer)
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc", handler: ipcHandler)

  // App protocol serves assets from external files
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { request in
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

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 900,
    height: 700,
    title: "Velox Commands (Registry DSL)"
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

  print("[CommandsManualRegistry] Application started")

  // Event loop
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

  print("[CommandsManualRegistry] Exiting")
}

main()
