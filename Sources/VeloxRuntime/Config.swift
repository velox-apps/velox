// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Root Configuration

/// Root configuration structure, loaded from `velox.json`.
/// Mirrors Tauri's `tauri.conf.json` structure.
public struct VeloxConfig: Codable, Sendable {
  /// JSON schema URL for IDE support
  public var schema: String?

  /// Human-readable product name
  public var productName: String?

  /// App version (semver)
  public var version: String?

  /// Unique app identifier (reverse domain notation)
  public var identifier: String

  /// Application configuration
  public var app: AppConfig

  /// Build configuration (optional)
  public var build: BuildConfig?

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case productName
    case version
    case identifier
    case app
    case build
  }

  public init(
    productName: String? = nil,
    version: String? = nil,
    identifier: String,
    app: AppConfig = AppConfig(),
    build: BuildConfig? = nil
  ) {
    self.productName = productName
    self.version = version
    self.identifier = identifier
    self.app = app
    self.build = build
  }
}

// MARK: - App Configuration

/// Application-level configuration
public struct AppConfig: Codable, Sendable {
  /// Window configurations
  public var windows: [WindowConfig]

  /// Security settings
  public var security: SecurityConfig?

  /// macOS-specific settings
  public var macOS: MacOSConfig?

  /// Whether to enable global Velox object in JS
  public var withGlobalVelox: Bool?

  public init(
    windows: [WindowConfig] = [],
    security: SecurityConfig? = nil,
    macOS: MacOSConfig? = nil,
    withGlobalVelox: Bool? = nil
  ) {
    self.windows = windows
    self.security = security
    self.macOS = macOS
    self.withGlobalVelox = withGlobalVelox
  }
}

// MARK: - Window Configuration

/// Configuration for a single window
public struct WindowConfig: Codable, Sendable {
  /// Unique window identifier
  public var label: String

  /// Whether to auto-create this window at startup
  public var create: Bool?

  /// URL to load (app://, https://, or file path)
  public var url: String?

  /// Window title
  public var title: String?

  /// Window width in logical pixels
  public var width: Double?

  /// Window height in logical pixels
  public var height: Double?

  /// Minimum window width
  public var minWidth: Double?

  /// Minimum window height
  public var minHeight: Double?

  /// Maximum window width
  public var maxWidth: Double?

  /// Maximum window height
  public var maxHeight: Double?

  /// X position (if not centered)
  public var x: Double?

  /// Y position (if not centered)
  public var y: Double?

  /// Whether to center the window on screen
  public var center: Bool?

  /// Whether the window is resizable
  public var resizable: Bool?

  /// Whether the window has decorations (title bar, etc.)
  public var decorations: Bool?

  /// Whether the window starts maximized
  public var maximized: Bool?

  /// Whether the window starts minimized
  public var minimized: Bool?

  /// Whether the window is visible at creation
  public var visible: Bool?

  /// Whether the window starts in fullscreen
  public var fullscreen: Bool?

  /// Whether the window is always on top
  public var alwaysOnTop: Bool?

  /// Whether the window is always on bottom
  public var alwaysOnBottom: Bool?

  /// Whether the window can be focused
  public var focusable: Bool?

  /// Whether the window should be focused at creation
  public var focus: Bool?

  /// Whether the window is transparent
  public var transparent: Bool?

  /// Whether the window can be maximized
  public var maximizable: Bool?

  /// Whether the window can be minimized
  public var minimizable: Bool?

  /// Whether the window can be closed
  public var closable: Bool?

  /// Whether to skip the taskbar
  public var skipTaskbar: Bool?

  /// Whether content is protected from capture
  public var contentProtected: Bool?

  /// Whether visible on all workspaces
  public var visibleOnAllWorkspaces: Bool?

  /// Window theme (light, dark, or system)
  public var theme: WindowTheme?

  /// Background color (hex string like "#RRGGBB" or "#RRGGBBAA")
  public var backgroundColor: String?

  /// User agent string for the webview
  public var userAgent: String?

  /// Whether dev tools are enabled
  public var devtools: Bool?

  /// Whether zoom hotkeys are enabled
  public var zoomHotkeysEnabled: Bool?

  /// Whether drag-drop is enabled
  public var dragDropEnabled: Bool?

  /// Whether this is a child webview with bounds
  public var isChild: Bool?

  /// Custom protocols to register for this window's webview
  public var customProtocols: [String]?

  public init(
    label: String,
    create: Bool? = true,
    url: String? = nil,
    title: String? = nil,
    width: Double? = 800,
    height: Double? = 600
  ) {
    self.label = label
    self.create = create
    self.url = url
    self.title = title
    self.width = width
    self.height = height
  }
}

/// Window theme options
public enum WindowTheme: String, Codable, Sendable {
  case light
  case dark
  case system
}

// MARK: - Security Configuration

/// Security settings for the application
public struct SecurityConfig: Codable, Sendable {
  /// Content Security Policy
  public var csp: String?

  /// Development-only CSP (overrides csp in dev mode)
  public var devCsp: String?

  /// Whether to freeze the prototype chain
  public var freezePrototype: Bool?

  public init(
    csp: String? = nil,
    devCsp: String? = nil,
    freezePrototype: Bool? = nil
  ) {
    self.csp = csp
    self.devCsp = devCsp
    self.freezePrototype = freezePrototype
  }
}

// MARK: - macOS Configuration

/// macOS-specific settings
public struct MacOSConfig: Codable, Sendable {
  /// Activation policy: regular, accessory, or prohibited
  public var activationPolicy: ActivationPolicy?

  /// Whether to use private APIs
  public var privateApi: Bool?

  public init(
    activationPolicy: ActivationPolicy? = nil,
    privateApi: Bool? = nil
  ) {
    self.activationPolicy = activationPolicy
    self.privateApi = privateApi
  }
}

/// macOS activation policy
public enum ActivationPolicy: String, Codable, Sendable {
  /// Regular app with dock icon
  case regular
  /// Accessory app (no dock icon, can have menu bar)
  case accessory
  /// Background app (no UI activation)
  case prohibited
}

// MARK: - Build Configuration

/// Build-time configuration
public struct BuildConfig: Codable, Sendable {
  /// Development server URL
  public var devUrl: String?

  /// Path to frontend distribution folder
  public var frontendDist: String?

  /// Command to run before dev
  public var beforeDevCommand: String?

  /// Command to run before build
  public var beforeBuildCommand: String?

  public init(
    devUrl: String? = nil,
    frontendDist: String? = nil,
    beforeDevCommand: String? = nil,
    beforeBuildCommand: String? = nil
  ) {
    self.devUrl = devUrl
    self.frontendDist = frontendDist
    self.beforeDevCommand = beforeDevCommand
    self.beforeBuildCommand = beforeBuildCommand
  }
}

// MARK: - Configuration Loading

public extension VeloxConfig {
  /// Configuration loading errors
  enum LoadError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String, Error)
    case mergeError(String)

    public var errorDescription: String? {
      switch self {
      case .fileNotFound(let path):
        return "Configuration file not found: \(path)"
      case .parseError(let path, let error):
        return "Failed to parse \(path): \(error.localizedDescription)"
      case .mergeError(let message):
        return "Failed to merge configuration: \(message)"
      }
    }
  }

  /// Load configuration from a directory.
  /// Looks for `velox.json` and merges platform-specific overrides.
  /// Falls back to checking Bundle.main.resourcePath for app bundles.
  ///
  /// - Parameter directory: Directory containing velox.json (defaults to current directory)
  /// - Returns: Merged configuration
  static func load(from directory: URL? = nil) throws -> VeloxConfig {
    // Build list of directories to search
    var searchDirs: [URL] = []

    if let directory = directory {
      searchDirs.append(directory)
    } else {
      // Check current directory first
      searchDirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

      // Then check bundle resources (for app bundles)
      if let resourcePath = Bundle.main.resourcePath {
        searchDirs.append(URL(fileURLWithPath: resourcePath))
      }
    }

    // Find velox.json in one of the search directories
    var dir: URL?
    var baseConfigURL: URL?

    for searchDir in searchDirs {
      let configURL = searchDir.appendingPathComponent("velox.json")
      if FileManager.default.fileExists(atPath: configURL.path) {
        dir = searchDir
        baseConfigURL = configURL
        break
      }
    }

    guard let dir = dir, let baseConfigURL = baseConfigURL else {
      let searchedPaths = searchDirs.map { $0.appendingPathComponent("velox.json").path }
      throw LoadError.fileNotFound(searchedPaths.joined(separator: ", "))
    }

    let baseData = try Data(contentsOf: baseConfigURL)
    var config = try JSONDecoder().decode(VeloxConfig.self, from: baseData)

    // Try to load platform-specific override
    let platformSuffix = currentPlatformSuffix()
    let platformConfigURL = dir.appendingPathComponent("velox.\(platformSuffix).json")

    if FileManager.default.fileExists(atPath: platformConfigURL.path) {
      let platformData = try Data(contentsOf: platformConfigURL)
      config = try merge(base: config, with: platformData)
    }

    return config
  }

  /// Load configuration from a specific file path
  static func load(from path: String) throws -> VeloxConfig {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      throw LoadError.fileNotFound(path)
    }

    let data = try Data(contentsOf: url)
    do {
      return try JSONDecoder().decode(VeloxConfig.self, from: data)
    } catch {
      throw LoadError.parseError(path, error)
    }
  }

  /// Get the platform suffix for the current OS
  private static func currentPlatformSuffix() -> String {
    #if os(macOS)
    return "macos"
    #elseif os(iOS)
    return "ios"
    #elseif os(Linux)
    return "linux"
    #elseif os(Windows)
    return "windows"
    #else
    return "unknown"
    #endif
  }

  /// Merge base config with platform-specific JSON data (RFC 7396 JSON Merge Patch)
  private static func merge(base: VeloxConfig, with patchData: Data) throws -> VeloxConfig {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // Convert base to JSON
    let baseData = try encoder.encode(base)
    guard var baseJSON = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
      throw LoadError.mergeError("Base config is not a valid JSON object")
    }

    // Parse patch
    guard let patchJSON = try JSONSerialization.jsonObject(with: patchData) as? [String: Any] else {
      throw LoadError.mergeError("Patch config is not a valid JSON object")
    }

    // Apply merge patch
    baseJSON = mergeJSON(base: baseJSON, patch: patchJSON)

    // Convert back to Config
    let mergedData = try JSONSerialization.data(withJSONObject: baseJSON)
    return try decoder.decode(VeloxConfig.self, from: mergedData)
  }

  /// RFC 7396 JSON Merge Patch implementation
  private static func mergeJSON(base: [String: Any], patch: [String: Any]) -> [String: Any] {
    var result = base

    for (key, patchValue) in patch {
      if let patchDict = patchValue as? [String: Any] {
        if let baseDict = result[key] as? [String: Any] {
          // Recursively merge objects
          result[key] = mergeJSON(base: baseDict, patch: patchDict)
        } else {
          // Replace with patch object
          result[key] = patchValue
        }
      } else if patchValue is NSNull {
        // RFC 7396: null removes the key
        result.removeValue(forKey: key)
      } else {
        // Replace with patch value
        result[key] = patchValue
      }
    }

    return result
  }
}

// MARK: - Convenience Extensions

public extension WindowConfig {
  /// Whether this window should be created at startup
  var shouldCreate: Bool {
    create ?? true
  }

  /// Effective window title
  var effectiveTitle: String {
    title ?? label
  }

  /// Effective window width
  var effectiveWidth: Double {
    width ?? 800
  }

  /// Effective window height
  var effectiveHeight: Double {
    height ?? 600
  }
}
