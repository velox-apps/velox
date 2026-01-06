import ArgumentParser
import Darwin
import Foundation
import Logging

struct InitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Initialize Velox in an existing project"
  )

  @Option(name: .long, help: "App identifier (e.g., com.example.myapp)")
  var identifier: String?

  @Option(name: .long, help: "Product name")
  var name: String?

  @Flag(name: .shortAndLong, help: "Overwrite existing files")
  var force: Bool = false

  @Flag(name: .shortAndLong, help: "Enable verbose logging")
  var verbose: Bool = false

  func run() async throws {
    configureLogger(verbose: verbose)
    logger.info("Velox Init")
    logger.info("==========")

    let currentDir = FileManager.default.currentDirectoryPath
    let dirName = URL(fileURLWithPath: currentDir).lastPathComponent

    // Derive defaults from directory name
    let productName = name ?? dirName
    let appIdentifier = identifier ?? "com.example.\(sanitizeIdentifier(dirName))"

    // Check for existing velox.json
    let veloxJsonPath = "\(currentDir)/velox.json"
    if FileManager.default.fileExists(atPath: veloxJsonPath) && !force {
      throw ValidationError(
        "velox.json already exists. Use --force to overwrite."
      )
    }

    // Create velox.json
    logger.info("[init] Creating velox.json...")
    let veloxJson = createVeloxJson(
      productName: productName,
      identifier: appIdentifier
    )
    try veloxJson.write(toFile: veloxJsonPath, atomically: true, encoding: .utf8)

    // Check if Package.swift exists
    let packageSwiftPath = "\(currentDir)/Package.swift"
    let hasPackageSwift = FileManager.default.fileExists(atPath: packageSwiftPath)

    if !hasPackageSwift {
      // Create a new Swift package
      logger.info("[init] Creating Package.swift...")
      let packageSwift = createPackageSwift(productName: productName)
      try packageSwift.write(toFile: packageSwiftPath, atomically: true, encoding: .utf8)

      // Create Sources directory and main.swift
      let sourcesDir = "\(currentDir)/Sources/\(sanitizeModuleName(productName))"
      try FileManager.default.createDirectory(
        atPath: sourcesDir,
        withIntermediateDirectories: true
      )

      let mainSwiftPath = "\(sourcesDir)/main.swift"
      if !FileManager.default.fileExists(atPath: mainSwiftPath) || force {
        logger.info("[init] Creating main.swift...")
        let mainSwift = createMainSwift(productName: productName)
        try mainSwift.write(toFile: mainSwiftPath, atomically: true, encoding: .utf8)
      }

      // Create assets directory
      let assetsDir = "\(currentDir)/assets"
      if !FileManager.default.fileExists(atPath: assetsDir) {
        try FileManager.default.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
        logger.info("[init] Created assets/ directory")

        // Create basic index.html
        let indexHtml = createIndexHtml(productName: productName)
        try indexHtml.write(toFile: "\(assetsDir)/index.html", atomically: true, encoding: .utf8)
        logger.info("[init] Created assets/index.html")
      }
    } else {
      logger.info("[init] Package.swift already exists - updating dependencies may be needed")
      logger.info("[init] Add Velox dependency to your Package.swift:")
      logger.info("       .package(url: \"https://github.com/aspect-build/aspect-cli.git\", from: \"5.0.0\")")
    }

    logger.info("")
    logger.info("[done] Velox initialized!")
    logger.info("")
    logger.info("Next steps:")
    logger.info("  1. Run 'swift build' to build the project")
    logger.info("  2. Run 'velox dev' to start development")
    logger.info("  3. Run 'velox build --bundle' to create an app bundle")
  }

  private func sanitizeIdentifier(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics
    return name
      .unicodeScalars
      .filter { allowed.contains($0) || $0 == "." || $0 == "-" }
      .map { String($0) }
      .joined()
      .lowercased()
  }

  private func sanitizeModuleName(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics
    var result = name
      .unicodeScalars
      .filter { allowed.contains($0) || $0 == "_" }
      .map { String($0) }
      .joined()

    // Ensure it starts with a letter
    if let first = result.first, first.isNumber {
      result = "_" + result
    }

    return result.isEmpty ? "App" : result
  }

  private func createVeloxJson(productName: String, identifier: String) -> String {
    return """
      {
        "$schema": "https://velox.dev/schema/velox.schema.json",
        "productName": "\(productName)",
        "version": "1.0.0",
        "identifier": "\(identifier)",
        "app": {
          "windows": [
            {
              "label": "main",
              "title": "\(productName)",
              "width": 800,
              "height": 600,
              "url": "app://localhost/",
              "create": true,
              "visible": true,
              "focus": true,
              "resizable": true,
              "decorations": true,
              "customProtocols": ["app", "ipc"]
            }
          ],
          "macOS": {
            "activationPolicy": "regular"
          }
        },
        "build": {
          "frontendDist": "assets"
        }
      }
      """
  }

  private func createPackageSwift(productName: String) -> String {
    let moduleName = sanitizeModuleName(productName)
    return """
      // swift-tools-version: 5.9
      import PackageDescription

      let package = Package(
        name: "\(moduleName)",
        platforms: [
          .macOS(.v13)
        ],
        dependencies: [
          .package(url: "https://github.com/aspect-build/aspect-cli.git", from: "5.0.0")
        ],
        targets: [
          .executableTarget(
            name: "\(moduleName)",
            dependencies: [
              .product(name: "VeloxRuntime", package: "aspect-cli"),
              .product(name: "VeloxRuntimeWry", package: "aspect-cli")
            ]
          )
        ]
      )
      """
  }

  private func createMainSwift(productName: String) -> String {
    return """
      import Foundation
      import VeloxRuntime
      import VeloxRuntimeWry

      // MARK: - Dev Server Proxy

      /// Proxies requests to a dev server (e.g., Vite) when VELOX_DEV_URL is set
      struct DevServerProxy {
        let baseURL: URL

        init?(devUrl: String) {
          guard let url = URL(string: devUrl) else { return nil }
          self.baseURL = url
        }

        func fetch(path: String) -> (data: Data, mimeType: String, status: Int)? {
          var normalizedPath = path
          if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
          }
          if normalizedPath == "/" {
            normalizedPath = "/index.html"
          }

          guard let requestURL = URL(string: normalizedPath, relativeTo: baseURL) else {
            return nil
          }

          var request = URLRequest(url: requestURL)
          request.timeoutInterval = 5

          let semaphore = DispatchSemaphore(value: 0)
          var result: (data: Data, mimeType: String, status: Int)?

          let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
              return
            }

            let mimeType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            result = (data, mimeType.components(separatedBy: ";").first ?? mimeType, httpResponse.statusCode)
          }
          task.resume()
          semaphore.wait()

          return result
        }
      }

      // MARK: - Asset Bundle

      struct AssetBundle {
        let basePath: String

        init() {
          // Try to find assets relative to current directory or bundle
          let possiblePaths = [
            "assets",
            Bundle.main.resourcePath.map { $0 + "/assets" } ?? ""
          ]

          for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
              basePath = path
              return
            }
          }

          basePath = "assets"
        }

        func mimeType(for path: String) -> String {
          let ext = (path as NSString).pathExtension.lowercased()
          switch ext {
          case "html", "htm": return "text/html"
          case "css": return "text/css"
          case "js": return "application/javascript"
          case "json": return "application/json"
          case "png": return "image/png"
          case "jpg", "jpeg": return "image/jpeg"
          case "svg": return "image/svg+xml"
          default: return "application/octet-stream"
          }
        }

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
            return nil
          }

          return (data, mimeType(for: normalizedPath))
        }
      }

      // MARK: - IPC Handler

      func handleInvoke(request: VeloxRuntimeWry.CustomProtocol.Request) -> VeloxRuntimeWry.CustomProtocol.Response? {
        guard let url = URL(string: request.url) else {
          return jsonError("Invalid URL")
        }

        let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch command {
        case "greet":
          var args: [String: Any] = [:]
          if !request.body.isEmpty,
             let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
            args = json
          }
          let name = args["name"] as? String ?? "World"
          return jsonResponse(["message": "Hello, \\(name)!"])

        default:
          return jsonError("Unknown command: \\(command)")
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

      func jsonError(_ message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
        let error: [String: Any] = ["error": message]
        let jsonData = (try? JSONSerialization.data(withJSONObject: error)) ?? Data()
        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 400,
          headers: ["Content-Type": "application/json", "Access-Control-Allow-Origin": "*"],
          mimeType: "application/json",
          body: jsonData
        )
      }

      // MARK: - Main

      func main() {
        guard Thread.isMainThread else {
          fatalError("Must run on main thread")
        }

        // Load configuration
        let config: VeloxConfig
        do {
          config = try VeloxConfig.load()
        } catch {
          fatalError("Failed to load velox.json: \\(error)")
        }

        // Check for dev server proxy mode
        let devProxy: DevServerProxy?
        if let devUrl = ProcessInfo.processInfo.environment["VELOX_DEV_URL"] {
          devProxy = DevServerProxy(devUrl: devUrl)
          if devProxy != nil {
            print("[velox] Dev server proxy enabled: \\(devUrl)")
          }
        } else {
          devProxy = nil
        }

        // Initialize assets for production mode
        let assets = AssetBundle()

        // Build app
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

            // In dev mode, proxy to dev server
            if let proxy = devProxy {
              if let result = proxy.fetch(path: url.path) {
                return VeloxRuntimeWry.CustomProtocol.Response(
                  status: result.status,
                  headers: ["Content-Type": result.mimeType, "Access-Control-Allow-Origin": "*"],
                  mimeType: result.mimeType,
                  body: result.data
                )
              }
              // Dev server request failed, return error
              return VeloxRuntimeWry.CustomProtocol.Response(
                status: 502,
                headers: ["Content-Type": "text/plain"],
                body: Data("Failed to proxy: \\(url.path)".utf8)
              )
            }

            // Production mode: serve from local assets
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
                body: Data("Not found: \\(url.path)".utf8)
            )
          }

        do {
          try appBuilder.run { event in
            switch event {
            case .windowCloseRequested, .userExit:
              return .exit
            default:
              return .wait
            }
          }
        } catch {
          fatalError("Failed to start app: \\(error)")
        }
      }

      main()
      """
  }

  private func createIndexHtml(productName: String) -> String {
    return """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(productName)</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
          }
          h1 { font-size: 3rem; margin-bottom: 1rem; }
          p { font-size: 1.2rem; opacity: 0.9; }
          button {
            margin-top: 2rem;
            padding: 0.75rem 2rem;
            font-size: 1rem;
            border: none;
            border-radius: 8px;
            background: white;
            color: #764ba2;
            cursor: pointer;
            transition: transform 0.2s;
          }
          button:hover { transform: scale(1.05); }
          #message { margin-top: 1rem; font-size: 1.1rem; }
        </style>
      </head>
      <body>
        <h1>\(productName)</h1>
        <p>Built with Velox</p>
        <button onclick="greet()">Say Hello</button>
        <p id="message"></p>

        <script>
          async function greet() {
            try {
              const response = await fetch('ipc://localhost/greet', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: 'Velox' })
              });
              const data = await response.json();
              document.getElementById('message').textContent = data.message;
            } catch (error) {
              document.getElementById('message').textContent = 'Error: ' + error.message;
            }
          }
        </script>
      </body>
      </html>
      """
  }
}
