// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime
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

// MARK: - Channel Streaming Events

/// Events sent through the download progress channel
enum SimulatedDownloadEvent: Codable, Sendable {
  case started(totalBytes: Int)
  case progress(bytesReceived: Int, totalBytes: Int)
  case finished
  case error(String)

  enum CodingKeys: String, CodingKey {
    case event, data
  }

  enum EventType: String, Codable {
    case started, progress, finished, error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let eventType = try container.decode(EventType.self, forKey: .event)
    switch eventType {
    case .started:
      var dataContainer = try container.nestedContainer(keyedBy: StartedKeys.self, forKey: .data)
      let totalBytes = try dataContainer.decode(Int.self, forKey: .totalBytes)
      self = .started(totalBytes: totalBytes)
    case .progress:
      var dataContainer = try container.nestedContainer(keyedBy: ProgressKeys.self, forKey: .data)
      let bytesReceived = try dataContainer.decode(Int.self, forKey: .bytesReceived)
      let totalBytes = try dataContainer.decode(Int.self, forKey: .totalBytes)
      self = .progress(bytesReceived: bytesReceived, totalBytes: totalBytes)
    case .finished:
      self = .finished
    case .error:
      var dataContainer = try container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .data)
      let message = try dataContainer.decode(String.self, forKey: .message)
      self = .error(message)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .started(let totalBytes):
      try container.encode(EventType.started, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: StartedKeys.self, forKey: .data)
      try dataContainer.encode(totalBytes, forKey: .totalBytes)
    case .progress(let bytesReceived, let totalBytes):
      try container.encode(EventType.progress, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: ProgressKeys.self, forKey: .data)
      try dataContainer.encode(bytesReceived, forKey: .bytesReceived)
      try dataContainer.encode(totalBytes, forKey: .totalBytes)
    case .finished:
      try container.encode(EventType.finished, forKey: .event)
    case .error(let message):
      try container.encode(EventType.error, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .data)
      try dataContainer.encode(message, forKey: .message)
    }
  }

  private enum StartedKeys: String, CodingKey { case totalBytes }
  private enum ProgressKeys: String, CodingKey { case bytesReceived, totalBytes }
  private enum ErrorKeys: String, CodingKey { case message }
}

// MARK: - HTML Content

func htmlContent(videoExists: Bool) -> String {
  // Common styles and channel demo section
  let channelDemoSection = """
    <div class="channel-demo">
      <h2>Channel Streaming Demo</h2>
      <p>Click the button to start a simulated download with progress updates via Channel streaming.</p>
      <button id="startDownload" onclick="startChannelDownload()">Start Simulated Download</button>
      <div id="progressContainer" style="display: none;">
        <div class="progress-bar">
          <div id="progressFill" class="progress-fill"></div>
        </div>
        <div id="progressText">0%</div>
      </div>
      <div id="downloadLog" class="log"></div>
    </div>
    <script>
      async function invoke(cmd, args = {}) {
        if (window.Velox && typeof window.Velox.invoke === 'function') {
          try {
            const result = await window.Velox.invoke(cmd, args);
            return { result };
          } catch (e) {
            return {
              error: e && e.code ? e.code : 'Error',
              message: e && e.message ? e.message : String(e)
            };
          }
        }
        const body = JSON.stringify(args);
        const response = await fetch('ipc://localhost/' + cmd, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: body
        });
        return response.json();
      }

      function startChannelDownload() {
        const btn = document.getElementById('startDownload');
        const container = document.getElementById('progressContainer');
        const fill = document.getElementById('progressFill');
        const text = document.getElementById('progressText');
        const log = document.getElementById('downloadLog');

        btn.disabled = true;
        container.style.display = 'block';
        log.innerHTML = '';

        // Create a new channel for progress updates
        const channel = new VeloxChannel();

        channel.onmessage = (msg) => {
          console.log('Channel message:', msg);

          switch (msg.event) {
            case 'started':
              log.innerHTML += '<div>Download started: ' + msg.data.totalBytes + ' bytes</div>';
              break;
            case 'progress':
              const percent = Math.round((msg.data.bytesReceived / msg.data.totalBytes) * 100);
              fill.style.width = percent + '%';
              text.textContent = percent + '% (' + msg.data.bytesReceived + '/' + msg.data.totalBytes + ')';
              break;
            case 'finished':
              log.innerHTML += '<div class="success">Download complete!</div>';
              btn.disabled = false;
              break;
            case 'error':
              log.innerHTML += '<div class="error">Error: ' + msg.data.message + '</div>';
              btn.disabled = false;
              break;
          }
        };

        channel.onclose = () => {
          console.log('Channel closed');
        };

        // Invoke the command with the channel
        invoke('simulate_download', { onProgress: channel }).then(result => {
          console.log('Command returned:', result);
        }).catch(err => {
          console.error('Command error:', err);
          btn.disabled = false;
        });
      }
    </script>
    """

  let channelStyles = """
    .channel-demo {
      background: #1a1a2e;
      padding: 20px;
      border-radius: 8px;
      margin: 20px;
      color: #eee;
    }
    .channel-demo h2 { margin-bottom: 10px; color: #fff; }
    .channel-demo p { margin-bottom: 15px; color: #aaa; }
    .channel-demo button {
      background: #4c6ef5;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 16px;
    }
    .channel-demo button:hover { background: #3b5bdb; }
    .channel-demo button:disabled { background: #666; cursor: not-allowed; }
    .progress-bar {
      width: 100%;
      height: 20px;
      background: #333;
      border-radius: 10px;
      overflow: hidden;
      margin: 15px 0;
    }
    .progress-fill {
      height: 100%;
      background: linear-gradient(90deg, #4c6ef5, #748ffc);
      width: 0%;
      transition: width 0.2s ease;
    }
    #progressText { text-align: center; color: #aaa; }
    .log { margin-top: 15px; font-family: monospace; font-size: 12px; }
    .log div { padding: 4px 0; border-bottom: 1px solid #333; }
    .log .success { color: #51cf66; }
    .log .error { color: #ff6b6b; }
    """

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
            background: #0f0f1a;
            min-height: 100vh;
            padding: 20px;
          }
          .video-container {
            display: flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 20px;
          }
          video {
            max-width: 100%;
            max-height: 60vh;
            border-radius: 8px;
          }
          h1 {
            color: #fff;
            text-align: center;
            margin-bottom: 20px;
          }
          \(channelStyles)
        </style>
      </head>
      <body>
        <h1>Velox Streaming Example</h1>
        <div class="video-container">
          <video controls autoplay>
            <source src="stream://localhost/video.mp4" type="video/mp4" />
            Your browser does not support video playback.
          </video>
        </div>
        \(channelDemoSection)
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
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0f0f1a;
            color: #eee;
            min-height: 100vh;
            padding: 20px;
          }
          .container { max-width: 700px; margin: 0 auto; }
          h1 { color: #fff; margin-bottom: 20px; }
          .warning {
            background: #3d2e00;
            border: 1px solid #ffc107;
            color: #ffd43b;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
          }
          code {
            background: #2d2d3d;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: "SF Mono", Monaco, monospace;
          }
          pre {
            background: #1a1a2e;
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
            color: #aaa;
          }
          \(channelStyles)
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Velox Streaming Example</h1>
          <div class="warning">
            <strong>Video file not found!</strong>
            <p>To run this example with video, download a sample video file.</p>
          </div>
          <p>Run the following command to download a sample video:</p>
          <pre>curl -L -o streaming_example_test_video.mp4 \\
      "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"</pre>
          <p style="margin-top: 15px;">Then run the example again from the <code>velox</code> directory.</p>
        </div>
        \(channelDemoSection)
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

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let appBuilder: VeloxAppBuilder
  do {
    appBuilder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("Streaming failed to load velox.json: \(error)")
  }

  let streamHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    handleStreamRequest(request, videoPath: videoPath)
  }

  // Command registry with simulated download command
  let registry = CommandRegistry()
  registry.register("simulate_download") { ctx -> CommandResult in
    // Get the channel from arguments
    guard let channel: Channel<SimulatedDownloadEvent> = ctx.channel("onProgress") else {
      return .err(code: "MissingChannel", message: "Missing onProgress channel")
    }

    // Simulate a download in a background task
    let totalBytes = 10_000_000  // 10 MB simulated
    let chunkSize = 500_000  // 500 KB chunks

    Task.detached {
      // Send started event
      channel.send(.started(totalBytes: totalBytes))

      // Simulate downloading chunks
      var bytesReceived = 0
      while bytesReceived < totalBytes {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        bytesReceived = min(bytesReceived + chunkSize, totalBytes)
        channel.send(.progress(bytesReceived: bytesReceived, totalBytes: totalBytes))
      }

      // Send finished event
      channel.send(.finished)
      channel.close()
    }

    return .ok
  }
  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    let html = htmlContent(videoExists: videoExists)
    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(html.utf8)
    )
  }

  if videoExists {
    print("Streaming video: \(videoPath)")
  }

  do {
    try appBuilder
      .registerProtocol("stream", handler: streamHandler)
      .registerProtocol("app", handler: appHandler)
      .registerCommands(registry)
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("Streaming failed to start: \(error)")
  }
}

main()
