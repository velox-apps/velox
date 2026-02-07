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

  /// Bundle configuration (optional)
  public var bundle: BundleConfig?

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case productName
    case version
    case identifier
    case app
    case build
    case bundle
  }

  public init(
    productName: String? = nil,
    version: String? = nil,
    identifier: String,
    app: AppConfig = AppConfig(),
    build: BuildConfig? = nil,
    bundle: BundleConfig? = nil
  ) {
    self.productName = productName
    self.version = version
    self.identifier = identifier
    self.app = app
    self.build = build
    self.bundle = bundle
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
  /// Content Security Policy (string or object with directives)
  public var csp: CSPConfig?

  /// Development-only CSP (overrides csp in dev mode)
  public var devCsp: CSPConfig?

  /// Whether to freeze the prototype chain when using custom protocols.
  /// Helps protect against prototype pollution attacks.
  public var freezePrototype: Bool?

  /// Asset protocol configuration for serving local files
  public var assetProtocol: AssetProtocolConfig?

  /// Security pattern: brownfield (default) or isolation
  public var pattern: PatternConfig?

  /// Custom HTTP headers to inject into responses
  public var headers: [String: String]?

  /// Disables Tauri-injected CSP sources.
  /// Can be `true` to disable all modifications, or a list of directive names to disable selectively.
  public var dangerousDisableAssetCspModification: CSPModificationConfig?

  /// Capabilities configuration - groups of permissions targeting specific windows
  public var capabilities: [CapabilityConfig]?

  /// Permission definitions with scopes for fine-grained access control
  public var permissions: [String: PermissionConfig]?

  /// Default policy for app commands (default: allow)
  public var defaultAppCommandPolicy: DefaultPolicy?

  /// Default policy for plugin commands (default: deny)
  public var defaultPluginCommandPolicy: DefaultPolicy?

  public init(
    csp: CSPConfig? = nil,
    devCsp: CSPConfig? = nil,
    freezePrototype: Bool? = nil,
    assetProtocol: AssetProtocolConfig? = nil,
    pattern: PatternConfig? = nil,
    headers: [String: String]? = nil,
    dangerousDisableAssetCspModification: CSPModificationConfig? = nil,
    capabilities: [CapabilityConfig]? = nil,
    permissions: [String: PermissionConfig]? = nil,
    defaultAppCommandPolicy: DefaultPolicy? = nil,
    defaultPluginCommandPolicy: DefaultPolicy? = nil
  ) {
    self.csp = csp
    self.devCsp = devCsp
    self.freezePrototype = freezePrototype
    self.assetProtocol = assetProtocol
    self.pattern = pattern
    self.headers = headers
    self.dangerousDisableAssetCspModification = dangerousDisableAssetCspModification
    self.capabilities = capabilities
    self.permissions = permissions
    self.defaultAppCommandPolicy = defaultAppCommandPolicy
    self.defaultPluginCommandPolicy = defaultPluginCommandPolicy
  }
}

// MARK: - CSP Configuration

/// Content Security Policy configuration for controlling resource loading.
///
/// CSP helps prevent XSS attacks by specifying which sources are allowed for scripts,
/// styles, images, and other resources.
///
/// Can be configured as a simple string:
/// ```json
/// { "csp": "default-src 'self'; script-src 'self' 'unsafe-inline'" }
/// ```
///
/// Or as an object with individual directives:
/// ```json
/// {
///   "csp": {
///     "default-src": "'self'",
///     "script-src": ["'self'", "'unsafe-inline'", "https://cdn.example.com"]
///   }
/// }
/// ```
public enum CSPConfig: Codable, Sendable, Equatable {
  /// Simple CSP string (e.g., "default-src 'self'; script-src 'unsafe-inline'")
  case string(String)

  /// Object with individual CSP directives for more granular control
  case directives([String: CSPDirectiveValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
    } else {
      let directives = try container.decode([String: CSPDirectiveValue].self)
      self = .directives(directives)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .directives(let directives):
      try container.encode(directives)
    }
  }

  /// Build the CSP header string
  public func buildHeaderValue() -> String {
    switch self {
    case .string(let value):
      return value
    case .directives(let directives):
      return directives.map { key, value in
        "\(key) \(value.joined())"
      }.joined(separator: "; ")
    }
  }
}

/// Value for a single CSP directive, supporting both string and array formats.
///
/// In JSON configuration, directive values can be:
/// - A single string: `"'self' 'unsafe-inline'"`
/// - An array of sources: `["'self'", "'unsafe-inline'", "https://cdn.example.com"]`
public enum CSPDirectiveValue: Codable, Sendable, Equatable {
  /// Single space-separated string of sources
  case single(String)
  /// Array of individual source values
  case multiple([String])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let stringValue = try? container.decode(String.self) {
      self = .single(stringValue)
    } else {
      let arrayValue = try container.decode([String].self)
      self = .multiple(arrayValue)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .single(let value):
      try container.encode(value)
    case .multiple(let values):
      try container.encode(values)
    }
  }

  /// Join values into a space-separated string
  public func joined() -> String {
    switch self {
    case .single(let value):
      return value
    case .multiple(let values):
      return values.joined(separator: " ")
    }
  }
}

// MARK: - Asset Protocol Configuration

/// Configuration for the asset:// protocol used to serve local files.
///
/// The asset protocol allows your app to load files from the local filesystem
/// through the webview. For security, you must explicitly enable it and define
/// which paths are accessible.
///
/// Example configuration:
/// ```json
/// {
///   "assetProtocol": {
///     "enable": true,
///     "scope": ["/tmp/*", "$HOME/Documents/*", "$APPDATA/*"]
///   }
/// }
/// ```
///
/// Supported scope patterns:
/// - `*` matches any characters within a path segment
/// - `$HOME` or `~` expands to the user's home directory
/// - `$APPDATA` expands to the application data directory
public struct AssetProtocolConfig: Codable, Sendable, Equatable {
  /// Whether the asset protocol is enabled (default: false)
  public var enable: Bool?

  /// Allowed paths/patterns for asset access (glob patterns supported)
  public var scope: [String]?

  /// Create an asset protocol configuration.
  ///
  /// - Parameters:
  ///   - enable: Whether to enable the asset:// protocol
  ///   - scope: Array of glob patterns defining accessible paths
  public init(enable: Bool? = nil, scope: [String]? = nil) {
    self.enable = enable
    self.scope = scope
  }

  /// Whether asset protocol is enabled (defaults to false if not set)
  public var isEnabled: Bool {
    enable ?? false
  }
}

// MARK: - Pattern Configuration

/// Security pattern configuration controlling how IPC is handled.
///
/// Velox supports two security patterns:
///
/// **Brownfield** (default): Standard webview with direct IPC access. Suitable for
/// apps where you control all the frontend code.
/// ```json
/// { "pattern": { "use": "brownfield" } }
/// ```
///
/// **Isolation**: All IPC goes through an isolated iframe that validates and sanitizes
/// messages. Provides stronger security for apps loading untrusted content.
/// ```json
/// {
///   "pattern": {
///     "use": "isolation",
///     "options": { "dir": "./isolation" }
///   }
/// }
/// ```
public enum PatternConfig: Codable, Sendable, Equatable {
  /// Brownfield pattern - standard webview with direct IPC (default)
  case brownfield

  /// Isolation pattern - sandboxed iframe intercepts and validates all IPC
  case isolation(IsolationConfig)

  enum CodingKeys: String, CodingKey {
    case use
    case options
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let use = try container.decode(String.self, forKey: .use)

    switch use {
    case "brownfield":
      self = .brownfield
    case "isolation":
      let options = try container.decode(IsolationConfig.self, forKey: .options)
      self = .isolation(options)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .use,
        in: container,
        debugDescription: "Unknown pattern: \(use). Expected 'brownfield' or 'isolation'."
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .brownfield:
      try container.encode("brownfield", forKey: .use)
    case .isolation(let config):
      try container.encode("isolation", forKey: .use)
      try container.encode(config, forKey: .options)
    }
  }
}

/// Configuration for the isolation security pattern.
///
/// When isolation is enabled, an iframe loads from the specified directory
/// and intercepts all IPC messages, providing an additional security layer.
public struct IsolationConfig: Codable, Sendable, Equatable {
  /// Directory containing the isolation application (HTML/JS files)
  public var dir: String

  /// Create an isolation configuration.
  ///
  /// - Parameter dir: Path to the directory containing isolation app files
  public init(dir: String) {
    self.dir = dir
  }
}

// MARK: - CSP Modification Configuration

/// Configuration for disabling automatic CSP source injection.
///
/// By default, Velox adds necessary sources to your CSP (like `app:` and `ipc:` protocols).
/// Use this setting to disable those modifications if you need full control over CSP.
///
/// Disable all modifications:
/// ```json
/// { "dangerousDisableAssetCspModification": true }
/// ```
///
/// Disable specific directives only:
/// ```json
/// { "dangerousDisableAssetCspModification": ["script-src", "connect-src"] }
/// ```
///
/// - Warning: Disabling CSP modifications may break app functionality if you don't
///   manually include the required protocol sources.
public enum CSPModificationConfig: Codable, Sendable, Equatable {
  /// Disable all automatic CSP modifications
  case all

  /// Disable modifications only for specific CSP directives
  case directives([String])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let boolValue = try? container.decode(Bool.self) {
      self = boolValue ? .all : .directives([])
    } else {
      let directives = try container.decode([String].self)
      self = .directives(directives)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .all:
      try container.encode(true)
    case .directives(let directives):
      if directives.isEmpty {
        try container.encode(false)
      } else {
        try container.encode(directives)
      }
    }
  }

  /// Check if modifications for a specific directive should be disabled
  public func shouldDisable(directive: String) -> Bool {
    switch self {
    case .all:
      return true
    case .directives(let disabled):
      return disabled.contains(directive)
    }
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

  /// Command to run before bundle creation
  public var beforeBundleCommand: String?

  /// Environment variables to inject
  public var env: [String: String]?

  public init(
    devUrl: String? = nil,
    frontendDist: String? = nil,
    beforeDevCommand: String? = nil,
    beforeBuildCommand: String? = nil,
    beforeBundleCommand: String? = nil,
    env: [String: String]? = nil
  ) {
    self.devUrl = devUrl
    self.frontendDist = frontendDist
    self.beforeDevCommand = beforeDevCommand
    self.beforeBuildCommand = beforeBuildCommand
    self.beforeBundleCommand = beforeBundleCommand
    self.env = env
  }
}

// MARK: - Bundle Configuration

/// Bundle configuration for packaging apps
public struct BundleConfig: Codable, Sendable {
  /// Whether bundling is enabled
  public var active: Bool?

  /// Bundle targets (e.g., app, dmg)
  public var targets: [BundleTarget]?

  /// Publisher name for the bundle metadata
  public var publisher: String?

  /// Bundle icon path(s)
  public var icon: BundleIcon?

  /// Additional resources to copy into the bundle
  public var resources: [String]?

  /// macOS-specific bundle settings
  public var macos: MacOSBundleConfig?

  public init(
    active: Bool? = nil,
    targets: [BundleTarget]? = nil,
    publisher: String? = nil,
    icon: BundleIcon? = nil,
    resources: [String]? = nil,
    macos: MacOSBundleConfig? = nil
  ) {
    self.active = active
    self.targets = targets
    self.publisher = publisher
    self.icon = icon
    self.resources = resources
    self.macos = macos
  }
}

public enum BundleTarget: String, Codable, Sendable {
  case app
  case dmg
}

public struct BundleIcon: Codable, Sendable {
  public let paths: [String]

  public init(_ paths: [String]) {
    self.paths = paths
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let single = try? container.decode(String.self) {
      self.paths = [single]
    } else {
      self.paths = try container.decode([String].self)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if paths.count == 1, let first = paths.first {
      try container.encode(first)
    } else {
      try container.encode(paths)
    }
  }
}

public struct MacOSBundleConfig: Codable, Sendable {
  /// Minimum supported macOS version (LSMinimumSystemVersion)
  public var minimumSystemVersion: String?

  /// Path to an Info.plist to merge into the generated plist
  public var infoPlist: String?

  /// Path to entitlements file for code signing
  public var entitlements: String?

  /// Code signing identity (e.g., "Developer ID Application: ...")
  public var signingIdentity: String?

  /// Enable hardened runtime (codesign --options runtime)
  public var hardenedRuntime: Bool?

  /// Notarization configuration
  public var notarization: NotarizationConfig?

  /// DMG configuration
  public var dmg: DmgConfig?

  public init(
    minimumSystemVersion: String? = nil,
    infoPlist: String? = nil,
    entitlements: String? = nil,
    signingIdentity: String? = nil,
    hardenedRuntime: Bool? = nil,
    notarization: NotarizationConfig? = nil,
    dmg: DmgConfig? = nil
  ) {
    self.minimumSystemVersion = minimumSystemVersion
    self.infoPlist = infoPlist
    self.entitlements = entitlements
    self.signingIdentity = signingIdentity
    self.hardenedRuntime = hardenedRuntime
    self.notarization = notarization
    self.dmg = dmg
  }
}

public struct NotarizationConfig: Codable, Sendable {
  /// Keychain profile name for notarytool
  public var keychainProfile: String?

  /// Apple ID for notarytool
  public var appleId: String?

  /// Team ID for notarytool
  public var teamId: String?

  /// App-specific password for notarytool
  public var password: String?

  /// Wait for notarization to complete
  public var wait: Bool?

  /// Staple the notarization ticket to the bundle
  public var staple: Bool?

  public init(
    keychainProfile: String? = nil,
    appleId: String? = nil,
    teamId: String? = nil,
    password: String? = nil,
    wait: Bool? = nil,
    staple: Bool? = nil
  ) {
    self.keychainProfile = keychainProfile
    self.appleId = appleId
    self.teamId = teamId
    self.password = password
    self.wait = wait
    self.staple = staple
  }
}

public struct DmgConfig: Codable, Sendable {
  /// Whether to create a DMG
  public var enabled: Bool?

  /// Optional custom DMG name (without extension)
  public var name: String?

  /// Optional volume name shown when mounting the DMG
  public var volumeName: String?

  public init(
    enabled: Bool? = nil,
    name: String? = nil,
    volumeName: String? = nil
  ) {
    self.enabled = enabled
    self.name = name
    self.volumeName = volumeName
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
