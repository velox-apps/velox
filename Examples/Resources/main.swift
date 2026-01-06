// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntimeWry

// MARK: - Resource Manager

/// Manages bundled resources with path resolution
struct ResourceManager {
  let basePath: String

  init() {
    // Find resources directory relative to executable
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    // Try several possible locations for resources
    let possiblePaths = [
      // Development: relative to executable in .build/debug
      (executableDir as NSString).appendingPathComponent("../../Examples/Resources/resources"),
      // Development: relative to current working directory
      "Examples/Resources/resources",
      // Bundled: in Resources directory (for app bundles)
      Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("resources") } ?? "",
      // Bundled: next to executable
      (executableDir as NSString).appendingPathComponent("resources")
    ]

    for path in possiblePaths {
      let expandedPath = (path as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: expandedPath) {
        basePath = expandedPath
        print("[Resources] Found resources at: \(basePath)")
        return
      }
    }

    // Fallback
    basePath = FileManager.default.currentDirectoryPath + "/Examples/Resources/resources"
    print("[Resources] Using fallback path: \(basePath)")
  }

  /// Resolve a resource path
  func resolve(_ relativePath: String) -> String {
    return (basePath as NSString).appendingPathComponent(relativePath)
  }

  /// Check if a resource exists
  func exists(_ relativePath: String) -> Bool {
    let fullPath = resolve(relativePath)
    return FileManager.default.fileExists(atPath: fullPath)
  }

  /// Read resource as string
  func readString(_ relativePath: String) -> String? {
    let fullPath = resolve(relativePath)
    return try? String(contentsOfFile: fullPath, encoding: .utf8)
  }

  /// Read resource as data
  func readData(_ relativePath: String) -> Data? {
    let fullPath = resolve(relativePath)
    return FileManager.default.contents(atPath: fullPath)
  }

  /// List all resources in a directory
  func list(_ directory: String = "") -> [String] {
    let fullPath = directory.isEmpty ? basePath : resolve(directory)
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: fullPath) else {
      return []
    }
    return contents.sorted()
  }

  /// Get file info
  func info(_ relativePath: String) -> [String: Any]? {
    let fullPath = resolve(relativePath)
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else {
      return nil
    }

    var info: [String: Any] = [
      "path": relativePath,
      "fullPath": fullPath,
      "exists": true
    ]

    if let size = attrs[.size] as? Int {
      info["size"] = size
    }
    if let modified = attrs[.modificationDate] as? Date {
      info["modified"] = ISO8601DateFormatter().string(from: modified)
    }
    if let type = attrs[.type] as? FileAttributeType {
      info["type"] = type == .typeDirectory ? "directory" : "file"
    }

    return info
  }
}

// MARK: - IPC Handler

func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request, resources: ResourceManager) -> VeloxRuntimeWry.CustomProtocol.Response? {
  guard let url = URL(string: request.url) else {
    return errorResponse(error: "InvalidURL", message: "Invalid request URL")
  }

  let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

  var args: [String: Any] = [:]
  if !request.body.isEmpty,
     let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
    args = json
  }

  print("[IPC] Command: \(command)")

  switch command {
  case "resolve_resource":
    guard let path = args["path"] as? String else {
      return errorResponse(error: "MissingArgument", message: "path is required")
    }
    let resolved = resources.resolve(path)
    let exists = resources.exists(path)
    return jsonResponse(["result": ["path": resolved, "exists": exists]])

  case "read_resource":
    guard let path = args["path"] as? String else {
      return errorResponse(error: "MissingArgument", message: "path is required")
    }
    guard let content = resources.readString(path) else {
      return errorResponse(error: "NotFound", message: "Resource not found: \(path)")
    }
    return jsonResponse(["result": content])

  case "read_json":
    guard let path = args["path"] as? String else {
      return errorResponse(error: "MissingArgument", message: "path is required")
    }
    guard let data = resources.readData(path),
          let json = try? JSONSerialization.jsonObject(with: data) else {
      return errorResponse(error: "ParseError", message: "Failed to parse JSON: \(path)")
    }
    return jsonResponse(["result": json])

  case "list_resources":
    let directory = args["directory"] as? String ?? ""
    let files = resources.list(directory)
    return jsonResponse(["result": files])

  case "resource_info":
    guard let path = args["path"] as? String else {
      return errorResponse(error: "MissingArgument", message: "path is required")
    }
    guard let info = resources.info(path) else {
      return errorResponse(error: "NotFound", message: "Resource not found: \(path)")
    }
    return jsonResponse(["result": info])

  case "base_path":
    return jsonResponse(["result": resources.basePath])

  default:
    return errorResponse(error: "UnknownCommand", message: "Unknown command: \(command)")
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

func errorResponse(error: String, message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  let errorData: [String: Any] = ["error": error, "message": message]
  let jsonData = (try? JSONSerialization.data(withJSONObject: errorData)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 400,
    headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
    mimeType: "application/json",
    body: jsonData
  )
}

// MARK: - HTML Content

let htmlContent = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Velox Resources</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 900px;
        margin: 30px auto;
        padding: 20px;
      }
      h1 { color: #333; border-bottom: 2px solid #007AFF; padding-bottom: 10px; }
      h3 { color: #555; margin-top: 25px; }
      .info-box {
        background: #f5f5f7;
        border-radius: 8px;
        padding: 15px;
        margin: 15px 0;
        font-family: monospace;
        font-size: 13px;
      }
      .file-list {
        list-style: none;
        padding: 0;
      }
      .file-list li {
        padding: 8px 12px;
        margin: 4px 0;
        background: #e8f4fd;
        border-radius: 4px;
        cursor: pointer;
        transition: background 0.2s;
      }
      .file-list li:hover { background: #d0e8fa; }
      .content-box {
        background: #1e1e1e;
        color: #d4d4d4;
        border-radius: 8px;
        padding: 15px;
        margin: 15px 0;
        font-family: monospace;
        white-space: pre-wrap;
        overflow-x: auto;
        min-height: 100px;
      }
      button {
        padding: 10px 16px;
        margin: 5px;
        font-size: 14px;
        background-color: #007AFF;
        color: white;
        border: none;
        border-radius: 6px;
        cursor: pointer;
      }
      button:hover { background-color: #0056b3; }
      .path { color: #007AFF; }
      .size { color: #888; font-size: 12px; }
    </style>
  </head>
  <body>
    <h1>Velox Resources Example</h1>
    <p>This example demonstrates resource bundling and path resolution.</p>

    <h3>Resource Base Path</h3>
    <div class="info-box" id="basePath">Loading...</div>

    <h3>Available Resources</h3>
    <ul class="file-list" id="fileList">
      <li>Loading...</li>
    </ul>

    <h3>Resource Content</h3>
    <div>
      <button onclick="loadResource('sample.txt')">Load sample.txt</button>
      <button onclick="loadResource('config.json')">Load config.json</button>
      <button onclick="loadResource('data.csv')">Load data.csv</button>
    </div>
    <div class="content-box" id="content">Select a resource to view its content...</div>

    <h3>Resource Info</h3>
    <div class="info-box" id="resourceInfo">Click a resource above to see its info...</div>

    <script>
      async function invoke(command, args = {}) {
        if (window.Velox && typeof window.Velox.invoke === 'function') {
          try {
            const result = await window.Velox.invoke(command, args);
            return { result };
          } catch (e) {
            return {
              error: e && e.code ? e.code : 'Error',
              message: e && e.message ? e.message : String(e)
            };
          }
        }
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });
        return response.json();
      }

      async function init() {
        // Get base path
        const baseResult = await invoke('base_path');
        document.getElementById('basePath').textContent = baseResult.result || baseResult.error;

        // List resources
        const listResult = await invoke('list_resources');
        const fileList = document.getElementById('fileList');
        fileList.innerHTML = '';

        if (listResult.result) {
          for (const file of listResult.result) {
            const li = document.createElement('li');
            li.textContent = file;
            li.onclick = () => loadResource(file);
            fileList.appendChild(li);
          }
        } else {
          fileList.innerHTML = '<li>Error loading resources</li>';
        }
      }

      async function loadResource(path) {
        const contentEl = document.getElementById('content');
        const infoEl = document.getElementById('resourceInfo');

        contentEl.textContent = 'Loading...';

        // Get content
        const contentResult = await invoke('read_resource', { path });
        if (contentResult.result !== undefined) {
          contentEl.textContent = contentResult.result;
        } else {
          contentEl.textContent = `Error: ${contentResult.error}\\n${contentResult.message}`;
        }

        // Get info
        const infoResult = await invoke('resource_info', { path });
        if (infoResult.result) {
          const info = infoResult.result;
          infoEl.innerHTML = `
<strong>Path:</strong> <span class="path">${info.path}</span>
<strong>Full Path:</strong> ${info.fullPath}
<strong>Size:</strong> <span class="size">${info.size} bytes</span>
<strong>Type:</strong> ${info.type}
<strong>Modified:</strong> ${info.modified || 'N/A'}`;
        } else {
          infoEl.textContent = `Error: ${infoResult.error}`;
        }
      }

      // Initialize on load
      init();
      console.log('Velox Resources example loaded!');
    </script>
  </body>
</html>
"""

// MARK: - Application Entry Point

func main() {
  guard Thread.isMainThread else {
    fatalError("Resources example must run on the main thread")
  }

  // Initialize resource manager
  let resources = ResourceManager()

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let appBuilder: VeloxAppBuilder
  do {
    appBuilder = try VeloxAppBuilder(directory: exampleDir)
  } catch {
    fatalError("Resources failed to load velox.json: \(error)")
  }

  let ipcHandler: VeloxRuntimeWry.CustomProtocol.Handler = { request in
    handleInvoke(request: request, resources: resources)
  }

  let appHandler: VeloxRuntimeWry.CustomProtocol.Handler = { _ in
    VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      mimeType: "text/html",
      body: Data(htmlContent.utf8)
    )
  }

  do {
    try appBuilder
      .registerProtocol("ipc", handler: ipcHandler)
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
    fatalError("Resources failed to start: \(error)")
  }
}

main()
