// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Security Script Generator

/// Generates JavaScript security scripts for webview initialization.
///
/// This generator produces JavaScript code that should be injected into webviews
/// before any other scripts run. It handles:
/// - Prototype freezing to prevent prototype pollution attacks
/// - Channel API injection for backend-to-frontend streaming
/// - Async invoke helper for deferred command responses
///
/// Example:
/// ```swift
/// let script = SecurityScriptGenerator.generateInitScript(
///   config: securityConfig,
///   includeChannelAPI: true
/// )
/// webview.evaluate(script: script)
/// ```
public enum SecurityScriptGenerator {

  /// Generate all security initialization scripts based on configuration.
  ///
  /// - Parameters:
  ///   - config: Security configuration (optional)
  ///   - includeChannelAPI: Whether to include the Channel API script (default: true)
  /// - Returns: Combined JavaScript code to inject into the webview
  public static func generateInitScript(config: SecurityConfig?, includeChannelAPI: Bool = true) -> String {
    var scripts: [String] = []

    // Freeze prototype if enabled (must run first)
    if config?.freezePrototype == true {
      scripts.append(freezePrototypeScript)
    }

    // Include Channel API for streaming
    if includeChannelAPI {
      scripts.append(channelFrontendScript)
    }

    // Include async invoke helper
    scripts.append(VeloxInvokeBridge.initScript)

    return scripts.joined(separator: "\n")
  }

  /// Script to freeze Object.prototype to prevent prototype pollution attacks.
  /// Must run before any other JavaScript.
  public static let freezePrototypeScript = """
    (function() {
      // Freeze Object.prototype to prevent prototype pollution
      if (Object.freeze) {
        Object.freeze(Object.prototype);
        Object.freeze(Array.prototype);
        Object.freeze(Function.prototype);
        Object.freeze(String.prototype);
        Object.freeze(Number.prototype);
        Object.freeze(Boolean.prototype);
        Object.freeze(Date.prototype);
        Object.freeze(RegExp.prototype);
        Object.freeze(Error.prototype);

        // Freeze common constructor prototypes
        if (typeof Map !== 'undefined') Object.freeze(Map.prototype);
        if (typeof Set !== 'undefined') Object.freeze(Set.prototype);
        if (typeof WeakMap !== 'undefined') Object.freeze(WeakMap.prototype);
        if (typeof WeakSet !== 'undefined') Object.freeze(WeakSet.prototype);
        if (typeof Promise !== 'undefined') Object.freeze(Promise.prototype);
        if (typeof Symbol !== 'undefined') Object.freeze(Symbol.prototype);

        // Freeze ArrayBuffer and typed arrays
        if (typeof ArrayBuffer !== 'undefined') Object.freeze(ArrayBuffer.prototype);
        if (typeof Int8Array !== 'undefined') Object.freeze(Int8Array.prototype);
        if (typeof Uint8Array !== 'undefined') Object.freeze(Uint8Array.prototype);
        if (typeof Int16Array !== 'undefined') Object.freeze(Int16Array.prototype);
        if (typeof Uint16Array !== 'undefined') Object.freeze(Uint16Array.prototype);
        if (typeof Int32Array !== 'undefined') Object.freeze(Int32Array.prototype);
        if (typeof Uint32Array !== 'undefined') Object.freeze(Uint32Array.prototype);
        if (typeof Float32Array !== 'undefined') Object.freeze(Float32Array.prototype);
        if (typeof Float64Array !== 'undefined') Object.freeze(Float64Array.prototype);
        if (typeof BigInt64Array !== 'undefined') Object.freeze(BigInt64Array.prototype);
        if (typeof BigUint64Array !== 'undefined') Object.freeze(BigUint64Array.prototype);
        if (typeof DataView !== 'undefined') Object.freeze(DataView.prototype);
      }
    })();
    """
}

// MARK: - CSP Builder

/// A builder for constructing Content-Security-Policy (CSP) headers.
///
/// CSP headers control what resources a webpage can load, helping prevent XSS attacks.
/// This builder provides a programmatic way to construct CSP strings.
///
/// Example:
/// ```swift
/// var csp = CSPBuilder()
/// csp.set(directive: "default-src", sources: ["'self'"])
/// csp.add(source: "https://api.example.com", to: "connect-src")
/// let header = csp.build()  // "connect-src https://api.example.com; default-src 'self'"
///
/// // Or use the default CSP for Velox apps
/// let defaultCSP = CSPBuilder.defaultCSP.build()
/// ```
public struct CSPBuilder {
  private var directives: [String: [String]] = [:]

  /// Create an empty CSP builder
  public init() {}

  /// Initialize from a CSPConfig, parsing its directives.
  ///
  /// - Parameter config: A CSPConfig (string or directives object)
  public init(from config: CSPConfig) {
    switch config {
    case .string(let value):
      // Parse string into directives
      for part in value.split(separator: ";") {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        let components = trimmed.split(separator: " ", maxSplits: 1)
        if components.count >= 1 {
          let directive = String(components[0])
          let sources = components.count > 1
            ? String(components[1]).split(separator: " ").map(String.init)
            : []
          directives[directive] = sources
        }
      }
    case .directives(let dict):
      for (key, value) in dict {
        switch value {
        case .single(let s):
          directives[key] = s.split(separator: " ").map(String.init)
        case .multiple(let arr):
          directives[key] = arr
        }
      }
    }
  }

  /// Add a source to a directive without removing existing sources.
  ///
  /// - Parameters:
  ///   - source: The source to add (e.g., "'self'", "https://api.example.com")
  ///   - directive: The CSP directive name (e.g., "script-src", "connect-src")
  public mutating func add(source: String, to directive: String) {
    var sources = directives[directive] ?? []
    if !sources.contains(source) {
      sources.append(source)
    }
    directives[directive] = sources
  }

  /// Set sources for a directive, replacing any existing sources.
  ///
  /// - Parameters:
  ///   - directive: The CSP directive name
  ///   - sources: Array of sources to set
  public mutating func set(directive: String, sources: [String]) {
    directives[directive] = sources
  }

  /// Get the current sources for a directive.
  ///
  /// - Parameter directive: The CSP directive name
  /// - Returns: Array of sources, or empty array if directive not set
  public func get(directive: String) -> [String] {
    directives[directive] ?? []
  }

  /// Build the CSP header string from all configured directives.
  ///
  /// - Returns: A semicolon-separated CSP header value
  public func build() -> String {
    directives.map { directive, sources in
      if sources.isEmpty {
        return directive
      }
      return "\(directive) \(sources.joined(separator: " "))"
    }.sorted().joined(separator: "; ")
  }

  /// Default CSP configuration for Velox applications.
  ///
  /// Includes sensible defaults for app://, asset://, and ipc:// protocols
  /// commonly used in Velox apps.
  public static var defaultCSP: CSPBuilder {
    var builder = CSPBuilder()
    builder.set(directive: "default-src", sources: ["'self'", "app:", "asset:"])
    builder.set(directive: "script-src", sources: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "app:", "asset:"])
    builder.set(directive: "style-src", sources: ["'self'", "'unsafe-inline'", "app:", "asset:"])
    builder.set(directive: "img-src", sources: ["'self'", "app:", "asset:", "blob:", "data:"])
    builder.set(directive: "connect-src", sources: ["'self'", "ipc:", "http://ipc.localhost", "app:", "asset:"])
    builder.set(directive: "font-src", sources: ["'self'", "app:", "asset:", "data:"])
    builder.set(directive: "media-src", sources: ["'self'", "app:", "asset:", "blob:"])
    return builder
  }
}

// MARK: - Asset Path Validator

/// Validates file system paths against configured scope patterns.
///
/// The validator uses glob patterns to determine which paths are accessible
/// through the asset:// protocol. This prevents unauthorized file access.
///
/// Example:
/// ```swift
/// let validator = AssetPathValidator(scope: [
///   "/tmp/*",           // Allow all files in /tmp
///   "$HOME/Documents/*" // Allow user's documents
/// ])
///
/// validator.isAllowed("/tmp/file.txt")     // true
/// validator.isAllowed("/etc/passwd")       // false
/// ```
///
/// Supported patterns:
/// - `*` matches any characters within a path segment
/// - `?` matches a single character
/// - `$HOME` and `~` expand to the user's home directory
/// - `$APPDATA` expands to the app's data directory
public struct AssetPathValidator {
  private let patterns: [String]

  /// Create a validator with the given scope patterns.
  ///
  /// - Parameter scope: Array of glob patterns defining allowed paths
  public init(scope: [String]) {
    self.patterns = scope
  }

  /// Check if a path is allowed by the configured scope.
  ///
  /// - Parameter path: The file path to validate
  /// - Returns: true if the path matches at least one scope pattern
  public func isAllowed(_ path: String) -> Bool {
    if patterns.isEmpty {
      return false
    }

    let normalizedPath = normalizePath(path)

    for pattern in patterns {
      if matchGlob(pattern: pattern, path: normalizedPath) {
        return true
      }
    }

    return false
  }

  /// Normalize a path for comparison
  private func normalizePath(_ path: String) -> String {
    // Expand ~ to home directory
    var result = path
    if result.hasPrefix("~") {
      result = (result as NSString).expandingTildeInPath
    }

    // Resolve to absolute path
    if !result.hasPrefix("/") {
      result = "/" + result
    }

    // Remove trailing slash
    if result.hasSuffix("/") && result.count > 1 {
      result = String(result.dropLast())
    }

    return result
  }

  /// Simple glob pattern matching
  private func matchGlob(pattern: String, path: String) -> Bool {
    // Expand environment variables in pattern
    var expandedPattern = pattern

    // Common variable replacements
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    expandedPattern = expandedPattern.replacingOccurrences(of: "$HOME", with: homeDir)
    expandedPattern = expandedPattern.replacingOccurrences(of: "~", with: homeDir)

    #if os(macOS)
    let appData = homeDir + "/Library/Application Support"
    expandedPattern = expandedPattern.replacingOccurrences(of: "$APPDATA", with: appData)
    #endif

    // Convert glob to regex
    var regex = "^"
    for char in expandedPattern {
      switch char {
      case "*":
        regex += ".*"
      case "?":
        regex += "."
      case ".":
        regex += "\\."
      case "/":
        regex += "/"
      default:
        regex += String(char)
      }
    }
    regex += "$"

    // Test match
    guard let re = try? NSRegularExpression(pattern: regex) else {
      return false
    }

    let range = NSRange(path.startIndex..., in: path)
    return re.firstMatch(in: path, range: range) != nil
  }
}
