import Foundation
import VeloxRuntime

/// Loads environment variables from various sources
struct EnvLoader {
  /// Load environment variables from config and .env files
  /// Priority (highest to lowest):
  /// 1. System environment variables
  /// 2. velox.json build.env
  /// 3. .env.local
  /// 4. .env.[mode] (e.g., .env.development, .env.production)
  /// 5. .env
  static func load(config: VeloxConfig, mode: String = "development") -> [String: String] {
    var env: [String: String] = [:]

    // Start with base .env
    if let dotEnv = loadDotEnvFile(".env") {
      env.merge(dotEnv) { _, new in new }
    }

    // Load mode-specific .env
    let modeEnvFile = ".env.\(mode)"
    if let modeEnv = loadDotEnvFile(modeEnvFile) {
      env.merge(modeEnv) { _, new in new }
    }

    // Load .env.local (always takes precedence over mode)
    if let localEnv = loadDotEnvFile(".env.local") {
      env.merge(localEnv) { _, new in new }
    }

    // Load from velox.json config
    if let configEnv = config.build?.env {
      env.merge(configEnv) { _, new in new }
    }

    return env
  }

  /// Parse a .env file
  private static func loadDotEnvFile(_ filename: String) -> [String: String]? {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(filename)

    guard FileManager.default.fileExists(atPath: path.path),
          let content = try? String(contentsOf: path, encoding: .utf8) else {
      return nil
    }

    return parseDotEnv(content)
  }

  /// Parse .env file content
  static func parseDotEnv(_ content: String) -> [String: String] {
    var env: [String: String] = [:]

    let lines = content.components(separatedBy: .newlines)
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines and comments
      if trimmed.isEmpty || trimmed.hasPrefix("#") {
        continue
      }

      // Parse KEY=value
      guard let equalsIndex = trimmed.firstIndex(of: "=") else {
        continue
      }

      let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
      var value = String(trimmed[trimmed.index(after: equalsIndex)...])
        .trimmingCharacters(in: .whitespaces)

      // Remove surrounding quotes if present
      if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
         (value.hasPrefix("'") && value.hasSuffix("'")) {
        value = String(value.dropFirst().dropLast())
      }

      // Handle escape sequences in double-quoted strings
      if value.contains("\\") {
        value = value
          .replacingOccurrences(of: "\\n", with: "\n")
          .replacingOccurrences(of: "\\t", with: "\t")
          .replacingOccurrences(of: "\\\"", with: "\"")
          .replacingOccurrences(of: "\\\\", with: "\\")
      }

      if !key.isEmpty {
        env[key] = value
      }
    }

    return env
  }
}
