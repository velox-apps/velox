// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Window Management

/// Tracks all windows in the application
final class WindowManager: @unchecked Sendable {
  private var windows: [String: VeloxRuntimeWry.Window] = [:]
  private var webviews: [String: VeloxRuntimeWry.Webview] = [:]
  private let lock = NSLock()

  func add(label: String, window: VeloxRuntimeWry.Window, webview: VeloxRuntimeWry.Webview) {
    lock.lock()
    windows[label] = window
    webviews[label] = webview
    lock.unlock()
  }

  func remove(label: String) {
    lock.lock()
    windows.removeValue(forKey: label)
    webviews.removeValue(forKey: label)
    lock.unlock()
  }

  func labels() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(windows.keys)
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return windows.count
  }

  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return windows.isEmpty
  }

  func showAll() {
    lock.lock()
    let allWindows = Array(windows.values)
    let allWebviews = Array(webviews.values)
    lock.unlock()

    for window in allWindows {
      _ = window.setVisible(true)
    }
    for webview in allWebviews {
      _ = webview.show()
    }
  }
}

// MARK: - HTML Content Generator

func htmlContent(for label: String, allLabels: [String]) -> String {
  let otherWindows = allLabels.filter { $0 != label }
    .map { "<li>\($0)</li>" }
    .joined(separator: "\n          ")

  return """
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Velox - \(label)</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          max-width: 500px;
          margin: 30px auto;
          padding: 20px;
        }
        h1 {
          color: #333;
          border-bottom: 2px solid #007AFF;
          padding-bottom: 10px;
        }
        .window-label {
          color: #007AFF;
        }
        .info-box {
          background: #f5f5f7;
          border-radius: 8px;
          padding: 15px;
          margin: 20px 0;
        }
        ul {
          margin: 10px 0;
          padding-left: 20px;
        }
        li {
          margin: 5px 0;
          color: #666;
        }
        p {
          color: #666;
          line-height: 1.6;
        }
      </style>
    </head>
    <body>
      <h1>Window: <span class="window-label">\(label)</span></h1>

      <div class="info-box">
        <strong>This is window "\(label)"</strong>
        <p>This example demonstrates multiple windows running simultaneously in Velox.</p>
      </div>

      <h3>Other Windows:</h3>
      <ul>
        \(otherWindows.isEmpty ? "<li>No other windows</li>" : otherWindows)
      </ul>

      <p>Each window runs independently with its own webview. Close any window to remove it from the application.</p>
    </body>
  </html>
  """
}

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("MultiWindow example must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let windowManager = WindowManager()

  // Window configurations matching tauri.conf.json
  let windowConfigs: [(label: String, title: String, width: UInt32, height: UInt32)] = [
    ("Main", "Velox - Main", 800, 600),
    ("Secondary", "Velox - Secondary", 600, 400),
    ("Third", "Velox - Third", 500, 350)
  ]

  let allLabels = windowConfigs.map { $0.label }

  // Create ALL windows first (before any webviews)
  var windows: [(label: String, window: VeloxRuntimeWry.Window)] = []
  for config in windowConfigs {
    let windowConfig = VeloxRuntimeWry.WindowConfiguration(
      width: config.width,
      height: config.height,
      title: config.title
    )

    guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
      print("Failed to create window: \(config.label)")
      continue
    }
    windows.append((label: config.label, window: window))
  }

  // Now create webviews for each window
  for (label, window) in windows {
    let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
      VeloxRuntimeWry.CustomProtocol.Response(
        status: 200,
        headers: ["Content-Type": "text/html; charset=utf-8"],
        mimeType: "text/html",
        body: Data(htmlContent(for: label, allLabels: allLabels).utf8)
      )
    }

    let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
      url: "app://localhost/",
      customProtocols: [appProtocol]
    )

    guard let webview = window.makeWebview(configuration: webviewConfig) else {
      print("Failed to create webview for window: \(label)")
      continue
    }

    windowManager.add(label: label, window: window, webview: webview)
  }

  print("Created \(windowManager.count) windows: \(windowManager.labels().joined(separator: ", "))")

  // Show all windows and activate app
  windowManager.showAll()
  #if os(macOS)
  eventLoop.showApplication()
  #endif

  // Run event loop using run_return pattern
  eventLoop.run { event in
    switch event {
    case .windowCloseRequested:
      // For simplicity, exit when any window closes
      // A more sophisticated version would track which window closed
      return .exit

    case .userExit:
      return .exit

    default:
      return .wait
    }
  }
}

main()
