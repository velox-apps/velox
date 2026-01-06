// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

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

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let appBuilder: VeloxAppBuilder
  do {
    appBuilder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("MultiWindow failed to start: \(error)")
  }

  let eventManager = appBuilder.eventManager
  let allLabels = appBuilder.config.app.windows.map(\.label)

  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    let label = eventManager.resolveLabel(request.webviewIdentifier)
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent(for: label, allLabels: allLabels).utf8)
    )
  }

  print("Created \(allLabels.count) windows: \(allLabels.joined(separator: ", "))")

  do {
    try appBuilder
      .registerProtocol("app", handler: appHandler)
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("MultiWindow failed to start: \(error)")
  }
}

main()
