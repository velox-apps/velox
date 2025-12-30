// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// HelloWorld2 - Demonstrates config-driven app with bundled assets
// Configuration is loaded from velox.json

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Asset Bundle

/// Serves bundled assets from the assets directory
struct AssetBundle {
  let basePath: String

  init(frontendDist: String? = nil) {
    // Find assets directory relative to executable or config
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent
    let configuredPath = frontendDist ?? "assets"

    // Try several possible locations for assets
    let possiblePaths = [
      // Development: relative to executable in .build/debug
      (executableDir as NSString).appendingPathComponent("../../Examples/HelloWorld2/\(configuredPath)"),
      // Development: relative to current working directory
      "Examples/HelloWorld2/\(configuredPath)",
      // Bundled: in Resources directory (for app bundles)
      Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent(configuredPath) } ?? "",
      // Bundled: next to executable
      (executableDir as NSString).appendingPathComponent(configuredPath)
    ]

    for path in possiblePaths {
      let expandedPath = (path as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: expandedPath) {
        basePath = expandedPath
        print("[Assets] Found assets at: \(basePath)")
        return
      }
    }

    // Fallback to current directory
    basePath = FileManager.default.currentDirectoryPath + "/Examples/HelloWorld2/\(configuredPath)"
    print("[Assets] Using fallback path: \(basePath)")
  }

  /// Get MIME type for file extension
  func mimeType(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js": return "application/javascript"
    case "json": return "application/json"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "ico": return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    default: return "application/octet-stream"
    }
  }

  /// Load asset from bundle
  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    var normalizedPath = path
    if normalizedPath.hasPrefix("/") {
      normalizedPath = String(normalizedPath.dropFirst())
    }
    if normalizedPath.isEmpty {
      normalizedPath = "index.html"
    }

    let fullPath = (basePath as NSString).appendingPathComponent(normalizedPath)

    guard let data = FileManager.default.contents(atPath: fullPath) else {
      print("[Assets] File not found: \(fullPath)")
      return nil
    }

    let mime = mimeType(for: normalizedPath)
    print("[Assets] Serving: \(normalizedPath) (\(mime), \(data.count) bytes)")
    return (data, mime)
  }
}

// MARK: - Command Handler

func greet(name: String) -> String {
  "Hello \(name), You have been greeted from Swift!"
}

func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request) -> VeloxRuntimeWry.CustomProtocol.Response? {
  guard let url = URL(string: request.url) else {
    return errorResponse(message: "Invalid URL")
  }

  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  var args: [String: Any] = [:]
  if !request.body.isEmpty,
     let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
    args = json
  }

  switch command {
  case "greet":
    let name = args["name"] as? String ?? "World"
    let result = greet(name: name)
    return jsonResponse(["result": result])

  default:
    return errorResponse(message: "Unknown command: \(command)")
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

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("HelloWorld2 must run on the main thread")
  }

  // Load configuration from velox.json
  let config: VeloxConfig
  do {
    // Try loading from Examples/HelloWorld2 directory
    let exampleDir = URL(fileURLWithPath: "Examples/HelloWorld2")
    config = try VeloxConfig.load(from: exampleDir)
    print("[Config] Loaded: \(config.productName ?? "Unknown") v\(config.version ?? "?")")
  } catch {
    print("[Config] Failed to load velox.json: \(error)")
    print("[Config] Using default configuration")
    config = VeloxConfig(
      productName: "HelloWorld2",
      version: "1.0.0",
      identifier: "com.velox.helloworld2",
      app: AppConfig(windows: [
        WindowConfig(
          label: "main",
          url: "app://localhost/",
          title: "Welcome to Velox! (Bundled Assets)",
          width: 800,
          height: 600
        )
      ])
    )
  }

  // Initialize asset bundle using frontendDist from config
  let assets = AssetBundle(frontendDist: config.build?.frontendDist)

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  // Build app using VeloxAppBuilder
  let appBuilder = VeloxAppBuilder(config: config)
    .registerProtocol("ipc") { request in
      handleInvoke(request: request)
    }
    .registerProtocol("app") { request in
      guard let url = URL(string: request.url) else {
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 400,
          headers: ["Content-Type": "text/plain"],
          body: Data("Invalid URL".utf8)
        )
      }

      if let asset = assets.loadAsset(path: url.path) {
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 200,
          headers: ["Content-Type": asset.mimeType],
          mimeType: asset.mimeType,
          body: asset.data
        )
      }

      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 404,
        headers: ["Content-Type": "text/plain"],
        body: Data("Asset not found: \(url.path)".utf8)
      )
    }

  let windows = appBuilder.build(eventLoop: eventLoop)

  guard !windows.isEmpty else {
    fatalError("No windows were created")
  }

  #if os(macOS)
  eventLoop.showApplication()
  #endif

  print("[App] Created \(windows.count) window(s)")

  // Run event loop
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
