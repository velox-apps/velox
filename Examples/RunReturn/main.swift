// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - HTML Content

let htmlContent = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Run Return Example</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 500px;
        margin: 50px auto;
        padding: 20px;
        text-align: center;
      }
      h1 {
        color: #333;
      }
      .info {
        background: #e3f2fd;
        border: 1px solid #90caf9;
        color: #1565c0;
        padding: 20px;
        border-radius: 8px;
        margin: 20px 0;
        text-align: left;
      }
      code {
        background: #f5f5f5;
        padding: 2px 6px;
        border-radius: 4px;
        font-family: "SF Mono", Monaco, monospace;
      }
      p {
        color: #666;
        line-height: 1.6;
      }
    </style>
  </head>
  <body>
    <h1>Run Return Example</h1>

    <div class="info">
      <strong>About this example:</strong>
      <p>This demonstrates that the event loop can return control to the caller after the window is closed.</p>
      <p>Close this window and check the terminal - you'll see a message printed <strong>after</strong> the event loop exits.</p>
    </div>

    <p>Unlike a typical app that terminates when the window closes, this pattern allows cleanup code or post-processing to run.</p>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  print("=== Run Return Example ===")
  print("Starting application...")
  print("")

  guard Thread.isMainThread else {
    fatalError("RunReturn example must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent.utf8)
    )
  }

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 600,
    height: 400,
    title: "Run Return Example"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [appProtocol]
  )

  guard let webview = window.makeWebview(configuration: webviewConfig) else {
    fatalError("Failed to create webview")
  }

  final class AppState: @unchecked Sendable {
    var activated = false
  }
  let state = AppState()

  // Record start time
  let startTime = Date()

  print("Event loop starting. Close the window to continue...")
  print("")

  // Show window and activate app
  _ = window.setVisible(true)
  _ = window.focus()
  _ = webview.show()
  #if os(macOS)
  eventLoop.showApplication()
  #endif

  // Run the event loop using run_return pattern - will exit when window closes
  while !state.activated {
    eventLoop.pump { event in
      switch event {
      case .windowCloseRequested, .userExit:
        state.activated = true
        return .exit

      default:
        return .wait
      }
    }
  }

  // This code runs AFTER the event loop exits!
  let endTime = Date()
  let duration = endTime.timeIntervalSince(startTime)

  print("")
  print("=== Event loop has exited! ===")
  print("")
  print("I run after exit!")
  print("")
  print("Statistics:")
  print("  - Window was open for: \(String(format: "%.1f", duration)) seconds")
  print("  - Exit time: \(endTime)")
  print("")
  print("This demonstrates the 'run_return' pattern where code continues")
  print("executing after the event loop finishes.")
  print("")
}

main()
