// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// MultiWebView - Demonstrates multiple child webviews in a single window
// Creates 4 child webviews in a 2x2 grid, loading different content:
// - Top-left: Local app content
// - Top-right: GitHub Tauri repo
// - Bottom-left: Tauri website
// - Bottom-right: Tauri Twitter/X

import Foundation
import VeloxRuntimeWry

// MARK: - Local App HTML Content

let localAppHTML = """
<!doctype html>
<html>
<head>
  <style>
    body {
      margin: 0; padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      height: calc(100vh - 40px);
      color: white;
    }
    h1 { font-size: 24px; margin: 0 0 10px 0; }
    p { font-size: 14px; opacity: 0.9; margin: 0 0 20px 0; }
    button {
      padding: 10px 20px;
      border: none; border-radius: 8px;
      background: rgba(255,255,255,0.2);
      color: white; font-size: 14px; cursor: pointer;
    }
    button:hover { background: rgba(255,255,255,0.3); }
  </style>
</head>
<body>
  <h1>Velox MultiWebView</h1>
  <p>Local app content in child webview</p>
  <button onclick="alert('Hello from Velox!')">Say Hello</button>
</body>
</html>
"""

// URLs for the 4 panels (matching Tauri's multiwebview example)
let panelURLs = [
  "app://localhost/",                          // Local app content
  "https://github.com/tauri-apps/tauri",       // GitHub
  "https://tauri.app",                         // Tauri website
  "https://x.com/ArnaudKappa"                      // Twitter/X (updated URL)
]

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("MultiWebView must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()

  // App protocol - serves local HTML content
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(localAppHTML.utf8)
    )
  }

  // Create 4 child webviews in a 2x2 grid
  var webviews: [VeloxRuntimeWry.Webview] = []
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app", handler: appHandler)
  let panelWidth: Double = 400
  let panelHeight: Double = 300

  do {
    let app = try VeloxAppBuilder(directory: exampleDir)
      .registerProtocol("app", handler: appHandler)
      .onWindowCreated("main") { window, _ in
        webviews.removeAll(keepingCapacity: true)

        for row in 0..<2 {
          for col in 0..<2 {
            let index = row * 2 + col
            let x = Double(col) * panelWidth
            let y = Double(row) * panelHeight

            // Only the first panel (local app) needs custom protocols
            let protocols = index == 0 ? [appProtocol] : []

            let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
              url: panelURLs[index],
              customProtocols: protocols,
              isChild: true,
              x: x,
              y: y,
              width: panelWidth,
              height: panelHeight
            )

            if let webview = window.makeWebview(configuration: webviewConfig) {
              webviews.append(webview)
              _ = webview.show()
              print("Created webview \(index + 1): \(panelURLs[index])")
            } else {
              print("Failed to create webview \(index + 1)")
            }
          }
        }

        print("Created \(webviews.count) child webviews. Press Cmd+Q to exit.")
      }

    // Run event loop using run_return pattern
    try app.run { event in
      switch event {
      case .windowCloseRequested, .userExit:
        return .exit

      case .windowResized(_, let size):
        // Resize child webviews proportionally
        let newPanelWidth = size.width / 2
        let newPanelHeight = size.height / 2
        for (index, webview) in webviews.enumerated() {
          let row = index / 2
          let col = index % 2
          webview.setBounds(
            x: Double(col) * newPanelWidth,
            y: Double(row) * newPanelHeight,
            width: newPanelWidth,
            height: newPanelHeight
          )
        }
        return .wait

      default:
        return .wait
      }
    }
  } catch {
    fatalError("MultiWebView failed to start: \(error)")
  }
}

main()
