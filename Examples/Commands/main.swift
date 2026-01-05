// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// Commands - Demonstrates the @VeloxCommand macro
// Compare this to Commands2 to see how macros simplify command definitions
// Uses external assets (HTML, CSS, JS) instead of inline HTML

import Foundation
import VeloxMacros
import VeloxRuntimeWry

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

// MARK: - Asset Bundle

struct AssetBundle {
  let basePath: String

  init() {
    // Find assets directory relative to executable
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    // Try different possible locations
    let possiblePaths = [
      "\(executableDir)/../../../Examples/Commands/assets",
      "\(executableDir)/assets",
      "./Examples/Commands/assets",
      "./assets"
    ]

    for path in possiblePaths {
      let indexPath = "\(path)/index.html"
      if FileManager.default.fileExists(atPath: indexPath) {
        self.basePath = path
        print("[Commands] Assets found at: \(path)")
        return
      }
    }

    // Fallback to current directory
    self.basePath = "./Examples/Commands/assets"
    print("[Commands] Using default assets path: \(basePath)")
  }

  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    var cleanPath = path
    if cleanPath.hasPrefix("/") {
      cleanPath = String(cleanPath.dropFirst())
    }
    if cleanPath.isEmpty {
      cleanPath = "index.html"
    }

    let fullPath = "\(basePath)/\(cleanPath)"

    guard let data = FileManager.default.contents(atPath: fullPath) else {
      print("[Commands] Asset not found: \(fullPath)")
      return nil
    }

    let mimeType = mimeTypeForPath(cleanPath)
    return (data, mimeType)
  }

  private func mimeTypeForPath(_ path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "html": return "text/html"
    case "css": return "text/css"
    case "js": return "application/javascript"
    case "json": return "application/json"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "svg": return "image/svg+xml"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    default: return "application/octet-stream"
    }
  }
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

struct AlertResponse: Codable, Sendable {
  let shown: Bool
}

struct BinaryInfo: Codable, Sendable {
  let size: Int
  let mimeType: String
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
}

// MARK: - Commands using @VeloxCommand macro

/// Container for all commands - required because peer macros can't introduce
/// arbitrary names at global scope
enum Commands {
  /// Greet a user by name
  @VeloxCommand
  static func greet(name: String) -> GreetResponse {
    GreetResponse(message: "Hello, \(name)! Welcome to Velox Commands.")
  }

  /// Add two numbers
  @VeloxCommand
  static func add(a: Int, b: Int) -> MathResponse {
    MathResponse(result: Double(a + b))
  }

  /// Divide two numbers (can throw)
  @VeloxCommand
  static func divide(numerator: Double, denominator: Double) throws -> MathResponse {
    guard denominator != 0 else {
      throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
    }
    return MathResponse(result: numerator / denominator)
  }

  /// Greet a person with their details
  @VeloxCommand
  static func person(name: String, age: Int, email: String?) -> PersonResponse {
    let greeting = "Hello \(name)! You are \(age) years old."
    return PersonResponse(greeting: greeting, isAdult: age >= 18)
  }

  /// Increment the counter (uses state)
  @VeloxCommand
  static func increment(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    let newValue = state.increment()
    return CounterResponse(value: newValue, label: state.label)
  }

  /// Get current counter value (uses state)
  @VeloxCommand("get_counter")
  static func getCounter(context: CommandContext) -> CounterResponse {
    let state: AppState = context.requireState()
    return CounterResponse(value: state.counter, label: state.label)
  }

  /// Simple ping command
  @VeloxCommand
  static func ping() -> PingResponse {
    PingResponse(pong: true, timestamp: Date().timeIntervalSince1970)
  }

  /// Demonstrate WebviewWindow injection - execute JavaScript in the webview
  @VeloxCommand("show_alert")
  static func showAlert(message: String, context: CommandContext) -> AlertResponse {
    guard let webview = context.webview else {
      return AlertResponse(shown: false)
    }

    // Escape the message for safe JavaScript injection
    let escaped = message
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: "\\n")

    // Execute JavaScript in the webview to update the UI
    let script = """
      (function() {
        var el = document.getElementById('alert-result');
        if (el) {
          el.textContent = 'Message from Swift: \(escaped)';
          el.className = 'result success';
        }
      })();
      """
    webview.evaluate(script: script)
    return AlertResponse(shown: true)
  }
}

// MARK: - Main

func main() {
  guard Thread.isMainThread else {
    fatalError("Commands must run on the main thread")
  }

  // Load assets from external files
  let assets = AssetBundle()

  // Create state container with app state
  let stateContainer = StateContainer()
    .manage(AppState())

  // Create event manager for webview injection
  let eventManager = VeloxEventManager()

  // Create command registry using macro-generated command definitions
  // Notice how clean this is compared to Commands2!
  let registry = commands {
    Commands.greetCommand       // Generated by @VeloxCommand on greet()
    Commands.addCommand         // Generated by @VeloxCommand on add()
    Commands.divideCommand      // Generated by @VeloxCommand on divide()
    Commands.personCommand      // Generated by @VeloxCommand on person()
    Commands.incrementCommand   // Generated by @VeloxCommand on increment()
    Commands.getCounterCommand  // Generated by @VeloxCommand("get_counter") on getCounter()
    Commands.pingCommand        // Generated by @VeloxCommand on ping()
    Commands.showAlertCommand   // Generated by @VeloxCommand("show_alert") on showAlert()

    // Binary response test - returns a red PNG image using CoreGraphics
    binaryCommand("get_image", mimeType: "image/png") { _ in
      // Create a 50x50 red image
      let width = 50
      let height = 50
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

      guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
      ) else {
        throw CommandError(code: "ImageError", message: "Failed to create graphics context")
      }

      // Fill with red
      context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))

      guard let cgImage = context.makeImage() else {
        throw CommandError(code: "ImageError", message: "Failed to create image")
      }

      // Encode to PNG
      let data = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CommandError(code: "ImageError", message: "Failed to create image destination")
      }
      CGImageDestinationAddImage(destination, cgImage, nil)
      CGImageDestinationFinalize(destination)

      return data as Data
    }
  }

  print("[Commands] Registered commands: \(registry.commandNames.sorted().joined(separator: ", "))")

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // Create IPC handler from registry (with event manager for webview injection)
  let ipcHandler = createCommandHandler(
    registry: registry,
    stateContainer: stateContainer,
    eventManager: eventManager
  )
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc", handler: ipcHandler)

  // Serve assets from external files
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { request in
    guard let url = URL(string: request.url) else {
      return notFoundResponse()
    }

    guard let asset = assets.loadAsset(path: url.path) else {
      return notFoundResponse()
    }

    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": asset.mimeType],
      body: asset.data
    )
  }

  @Sendable func notFoundResponse() -> VeloxRuntimeWry.CustomProtocol.Response {
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 404,
      headers: ["Content-Type": "text/plain"],
      body: Data("Not Found".utf8)
    )
  }

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 700,
    height: 700,
    title: "Velox Commands Demo (@VeloxCommand)"
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

  // Register webview with event manager for webview injection
  // Note: The label must match the webviewIdentifier from Wry (currently "1" for the first webview)
  eventManager.register(webview: webview, label: "1")

  webview.show()
  window.setVisible(true)

  #if os(macOS)
  eventLoop.showApplication()
  #endif

  print("[Commands] Application started")

  // Event loop
  eventLoop.run { event in
    switch event {
    case .windowCloseRequested, .userExit:
      return .exit
    default:
      return .wait
    }
  }

  print("[Commands] Exiting")
}

main()
