// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Video Streaming Handler

/// Maximum bytes to send in one range response
let maxChunkSize: UInt64 = 1024 * 1024  // 1 MB

/// Handle video streaming with HTTP range request support
func handleStreamRequest(_ request: VeloxRuntimeWry.CustomProtocol.Request, videoPath: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  // Check if video file exists
  guard FileManager.default.fileExists(atPath: videoPath) else {
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 404,
      headers: ["Content-Type": "text/plain"],
      body: Data("Video file not found. Run the example from the velox directory.".utf8)
    )
  }

  guard let fileHandle = FileHandle(forReadingAtPath: videoPath) else {
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 500,
      headers: ["Content-Type": "text/plain"],
      body: Data("Failed to open video file".utf8)
    )
  }
  defer { try? fileHandle.close() }

  // Get file size
  let fileSize: UInt64
  do {
    let attrs = try FileManager.default.attributesOfItem(atPath: videoPath)
    fileSize = attrs[.size] as? UInt64 ?? 0
  } catch {
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 500,
      headers: ["Content-Type": "text/plain"],
      body: Data("Failed to get file size: \(error)".utf8)
    )
  }

  // Check for Range header
  if let rangeHeader = request.headers["Range"] ?? request.headers["range"] {
    return handleRangeRequest(fileHandle: fileHandle, fileSize: fileSize, rangeHeader: rangeHeader)
  }

  // No range header - return entire file (not recommended for large files)
  do {
    let data = try fileHandle.readToEnd() ?? Data()
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: [
        "Content-Type": "video/mp4",
        "Content-Length": "\(fileSize)",
        "Accept-Ranges": "bytes"
      ],
      mimeType: "video/mp4",
      body: data
    )
  } catch {
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 500,
      headers: ["Content-Type": "text/plain"],
      body: Data("Failed to read file: \(error)".utf8)
    )
  }
}

/// Parse and handle HTTP Range request
func handleRangeRequest(fileHandle: FileHandle, fileSize: UInt64, rangeHeader: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  // Parse "bytes=start-end" format
  guard rangeHeader.hasPrefix("bytes=") else {
    return rangeNotSatisfiable(fileSize: fileSize)
  }

  let rangeSpec = String(rangeHeader.dropFirst(6))
  let parts = rangeSpec.split(separator: "-", omittingEmptySubsequences: false)

  guard parts.count == 2 else {
    return rangeNotSatisfiable(fileSize: fileSize)
  }

  let startStr = String(parts[0])
  let endStr = String(parts[1])

  var start: UInt64
  var end: UInt64

  if startStr.isEmpty {
    // Suffix range: -500 means last 500 bytes
    guard let suffixLength = UInt64(endStr) else {
      return rangeNotSatisfiable(fileSize: fileSize)
    }
    start = fileSize > suffixLength ? fileSize - suffixLength : 0
    end = fileSize - 1
  } else if endStr.isEmpty {
    // Open-ended range: 500- means from 500 to end
    guard let s = UInt64(startStr) else {
      return rangeNotSatisfiable(fileSize: fileSize)
    }
    start = s
    end = fileSize - 1
  } else {
    // Full range: 500-999
    guard let s = UInt64(startStr), let e = UInt64(endStr) else {
      return rangeNotSatisfiable(fileSize: fileSize)
    }
    start = s
    end = e
  }

  // Validate range
  guard start < fileSize, end < fileSize, start <= end else {
    return rangeNotSatisfiable(fileSize: fileSize)
  }

  // Limit chunk size
  let maxEnd = min(end, start + maxChunkSize - 1)
  end = min(end, maxEnd)

  let length = end - start + 1

  // Read the requested range
  do {
    try fileHandle.seek(toOffset: start)
    let data = try fileHandle.read(upToCount: Int(length)) ?? Data()

    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 206,
      headers: [
        "Content-Type": "video/mp4",
        "Content-Length": "\(length)",
        "Content-Range": "bytes \(start)-\(end)/\(fileSize)",
        "Accept-Ranges": "bytes"
      ],
      mimeType: "video/mp4",
      body: data
    )
  } catch {
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 500,
      headers: ["Content-Type": "text/plain"],
      body: Data("Failed to read range: \(error)".utf8)
    )
  }
}

func rangeNotSatisfiable(fileSize: UInt64) -> VeloxRuntimeWry.CustomProtocol.Response {
  VeloxRuntimeWry.CustomProtocol.Response(
    status: 416,
    headers: [
      "Content-Type": "text/plain",
      "Content-Range": "bytes */\(fileSize)"
    ],
    body: Data("Range Not Satisfiable".utf8)
  )
}

// MARK: - HTML Content

func htmlContent(videoExists: Bool) -> String {
  if videoExists {
    return """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Velox Streaming Example</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            background: #000;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
          }
          video {
            max-width: 100%;
            max-height: 100vh;
          }
        </style>
      </head>
      <body>
        <video controls autoplay>
          <source src="stream://localhost/video.mp4" type="video/mp4" />
          Your browser does not support video playback.
        </video>
      </body>
    </html>
    """
  } else {
    return """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <title>Velox Streaming Example</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
          }
          h1 { color: #333; }
          .warning {
            background: #fff3cd;
            border: 1px solid #ffc107;
            color: #856404;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
          }
          code {
            background: #f5f5f5;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: "SF Mono", Monaco, monospace;
          }
          pre {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
          }
        </style>
      </head>
      <body>
        <h1>Streaming Example</h1>
        <div class="warning">
          <strong>Video file not found!</strong>
          <p>To run this example, you need to download a sample video file.</p>
        </div>
        <p>Run the following command to download a sample video:</p>
        <pre>curl -L -o streaming_example_test_video.mp4 \\
      "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"</pre>
        <p>Then run the example again from the <code>velox</code> directory.</p>
      </body>
    </html>
    """
  }
}

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("Streaming example must run on the main thread")
  }

  // Check for video file
  let videoPath = "streaming_example_test_video.mp4"
  let videoExists = FileManager.default.fileExists(atPath: videoPath)

  if !videoExists {
    print("Video file not found: \(videoPath)")
    print("Download it with:")
    print("  curl -L -o streaming_example_test_video.mp4 \\")
    print("    \"http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4\"")
    print("")
    print("Showing instructions in the app...")
  }

  guard let eventLoop = VeloxRuntimeWry.EventLoop() else {
    fatalError("Failed to create event loop")
  }

  #if os(macOS)
  eventLoop.setActivationPolicy(.regular)
  #endif

  // Stream protocol for video
  let streamProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "stream") { request in
    handleStreamRequest(request, videoPath: videoPath)
  }

  // App protocol for HTML
  let appProtocol = VeloxRuntimeWry.CustomProtocol(scheme: "app") { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent(videoExists: videoExists).utf8)
    )
  }

  let windowConfig = VeloxRuntimeWry.WindowConfiguration(
    width: 854,
    height: 480,
    title: "Velox Streaming Example"
  )

  guard let window = eventLoop.makeWindow(configuration: windowConfig) else {
    fatalError("Failed to create window")
  }

  let webviewConfig = VeloxRuntimeWry.WebviewConfiguration(
    url: "app://localhost/",
    customProtocols: [appProtocol, streamProtocol]
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

  if videoExists {
    print("Streaming video: \(videoPath)")
  }

  // Run event loop using run_return pattern
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
