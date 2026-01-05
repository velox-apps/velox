// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - HTML Content

let splashscreenHTML = """
<!DOCTYPE html>
<html>
  <head>
    <title>Splashscreen</title>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        width: 100vw;
        height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      }
      .splash-content {
        text-align: center;
        color: white;
      }
      .logo {
        font-size: 72px;
        margin-bottom: 20px;
      }
      h1 {
        font-size: 28px;
        font-weight: 300;
        margin-bottom: 15px;
      }
      .loader {
        width: 50px;
        height: 50px;
        border: 3px solid rgba(255,255,255,0.3);
        border-top-color: white;
        border-radius: 50%;
        animation: spin 1s linear infinite;
        margin: 0 auto;
      }
      @keyframes spin {
        to { transform: rotate(360deg); }
      }
    </style>
  </head>
  <body>
    <div class="splash-content">
      <div class="logo">V</div>
      <h1>Loading Velox...</h1>
      <div class="loader"></div>
    </div>
  </body>
</html>
"""

func mainWindowHTML(shouldCloseSplash: Bool) -> String {
  let script = shouldCloseSplash ? """
      <script>
        // Close splashscreen after 2 seconds
        setTimeout(() => {
          fetch('ipc://localhost/close_splashscreen', { method: 'POST' });
        }, 2000);
      </script>
  """ : ""

  return """
  <!DOCTYPE html>
  <html>
    <head>
      <title>Velox Main Window</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          max-width: 600px;
          margin: 50px auto;
          padding: 20px;
          text-align: center;
        }
        h1 { color: #333; margin-bottom: 20px; }
        .success {
          background: #d4edda;
          border: 1px solid #c3e6cb;
          color: #155724;
          padding: 20px;
          border-radius: 8px;
          margin: 20px 0;
        }
        p { color: #666; line-height: 1.6; }
      </style>
    </head>
    <body>
      <h1>Welcome to Velox!</h1>
      <div class="success">
        <strong>Application loaded successfully!</strong>
        <p>The splashscreen has been dismissed and the main window is now visible.</p>
      </div>
      <p>This example demonstrates how to show a splashscreen while the application loads, then transition to the main window.</p>
      \(script)
    </body>
  </html>
  """
}

// MARK: - Window Manager

final class SplashWindowManager: @unchecked Sendable {
  var splashWindow: VeloxRuntimeWry.Window?
  var splashWebview: VeloxRuntimeWry.Webview?
  var mainWindow: VeloxRuntimeWry.Window?
  var mainWebview: VeloxRuntimeWry.Webview?
  var splashClosed = false
  private let lock = NSLock()

  func closeSplashscreen() {
    lock.lock()
    defer { lock.unlock() }

    if splashClosed { return }
    splashClosed = true

    // Hide splashscreen
    _ = splashWindow?.setVisible(false)

    // Show main window
    _ = mainWindow?.setVisible(true)
    _ = mainWindow?.focus()
    _ = mainWebview?.show()
  }
}

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("Splashscreen example must run on the main thread")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  let windowManager = SplashWindowManager()

  // IPC protocol for close_splashscreen command
  let ipcProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "ipc") { request in
    guard let url = URL(string: request.url) else { return nil }
    let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    if command == "close_splashscreen" {
      DispatchQueue.main.async {
        windowManager.closeSplashscreen()
      }
      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 200,
        headers: ["Content-Type": "application/json"],
        body: Data("{\"ok\":true}".utf8)
      )
    }
    return nil
  }

  // Window configurations
  let windowConfigs: [(label: String, title: String, width: UInt32, height: UInt32, isSplash: Bool)] = [
    ("Splash", "Loading...", 400, 200, true),
    ("Main", "Velox", 800, 600, false)
  ]

  // Create ALL windows first (before any webviews)
  var windows: [(label: String, window: VeloxRuntimeWry.Window, isSplash: Bool)] = []
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
    windows.append((label: config.label, window: window, isSplash: config.isSplash))
  }

  // Now create webviews for each window
  for (label, window, isSplash) in windows {
    let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
      let html = isSplash ? splashscreenHTML : mainWindowHTML(shouldCloseSplash: true)
      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 200,
        headers: ["Content-Type": "text/html; charset=utf-8"],
        mimeType: "text/html",
        body: Data(html.utf8)
      )
    }

    let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
      url: "app://localhost/",
      customProtocols: isSplash ? [appProtocol] : [ipcProtocol, appProtocol]
    )

    guard let webview = window.makeWebview(configuration: webviewConfig) else {
      print("Failed to create webview for window: \(label)")
      continue
    }

    if isSplash {
      windowManager.splashWindow = window
      windowManager.splashWebview = webview
    } else {
      windowManager.mainWindow = window
      windowManager.mainWebview = webview
    }
  }

  print("Splashscreen example started - will transition to main window in 2 seconds")

  // Show splashscreen, hide main window initially
  if let splashWindow = windowManager.splashWindow,
     let splashWebview = windowManager.splashWebview {
    _ = splashWindow.setVisible(true)
    _ = splashWebview.show()
    _ = splashWindow.focus()
  }

  if let mainWindow = windowManager.mainWindow {
    _ = mainWindow.setVisible(false)
  }

  #if os(macOS)
  eventLoop.showApplication()
  #endif

  // Run event loop using run_return pattern
  eventLoop.run { event in
    switch event {
    case .windowCloseRequested, .userExit:
      return .exit

    default:
      return .wait
    }
  }
}

main()
