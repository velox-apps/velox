// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Permission Error

/// Errors related to permission checking
public enum PermissionError: Error, Sendable, LocalizedError {
  case denied(command: String, reason: String)
  case scopeViolation(command: String, scope: String, value: String)
  case invalidConfiguration(String)

  public var errorDescription: String? {
    switch self {
    case .denied(let command, let reason):
      return "Permission denied for '\(command)': \(reason)"
    case .scopeViolation(let command, let scope, let value):
      return "Scope violation for '\(command)': \(scope) does not allow '\(value)'"
    case .invalidConfiguration(let message):
      return "Invalid permission configuration: \(message)"
    }
  }
}

// MARK: - Default Policy

/// Default permission policy for commands
public enum DefaultPolicy: String, Codable, Sendable {
  case allow
  case deny
}

// MARK: - Permission Scope

/// A scope that limits what values a permission allows
public enum PermissionScope: Codable, Sendable, Equatable {
  /// Allow any value
  case any

  /// Allow specific literal values
  case values([String])

  /// Allow values matching glob patterns (e.g., "/tmp/*", "*.txt")
  case globs([String])

  /// Allow values matching URL patterns
  case urls([String])

  /// Custom scope with named validator
  case custom(String)

  enum CodingKeys: String, CodingKey {
    case values, globs, urls, custom
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    if container.contains(.values) {
      let vals = try container.decode([String].self, forKey: .values)
      self = .values(vals)
    } else if container.contains(.globs) {
      let globs = try container.decode([String].self, forKey: .globs)
      self = .globs(globs)
    } else if container.contains(.urls) {
      let urls = try container.decode([String].self, forKey: .urls)
      self = .urls(urls)
    } else if container.contains(.custom) {
      let name = try container.decode(String.self, forKey: .custom)
      self = .custom(name)
    } else {
      self = .any
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .any:
      break  // empty object means any
    case .values(let vals):
      try container.encode(vals, forKey: .values)
    case .globs(let globs):
      try container.encode(globs, forKey: .globs)
    case .urls(let urls):
      try container.encode(urls, forKey: .urls)
    case .custom(let name):
      try container.encode(name, forKey: .custom)
    }
  }

  /// Check if a value is allowed by this scope
  public func allows(_ value: String, customValidator: ((String, String) -> Bool)? = nil) -> Bool {
    switch self {
    case .any:
      return true
    case .values(let allowed):
      return allowed.contains(value)
    case .globs(let patterns):
      return patterns.contains { matchGlob(pattern: $0, value: value) }
    case .urls(let patterns):
      return patterns.contains { matchURLPattern(pattern: $0, value: value) }
    case .custom(let name):
      return customValidator?(name, value) ?? false
    }
  }
}

// MARK: - Permission Configuration

/// Configuration for a single permission
public struct PermissionConfig: Codable, Sendable {
  /// Permission identifier (e.g., "fs:read", "http:fetch")
  public let identifier: String

  /// Commands to allow (empty = allow all for this permission)
  public var allow: [String]?

  /// Commands to explicitly deny (takes priority over allow)
  public var deny: [String]?

  /// Scopes for fine-grained access control
  public var scopes: [String: PermissionScope]?

  public init(
    identifier: String,
    allow: [String]? = nil,
    deny: [String]? = nil,
    scopes: [String: PermissionScope]? = nil
  ) {
    self.identifier = identifier
    self.allow = allow
    self.deny = deny
    self.scopes = scopes
  }
}

// MARK: - Capability Configuration

/// A capability groups permissions and targets specific windows
public struct CapabilityConfig: Codable, Sendable {
  /// Unique identifier for this capability
  public let identifier: String

  /// Human-readable description
  public var description: String?

  /// Window labels this capability applies to (empty = all windows)
  public var windows: [String]?

  /// Webview labels this capability applies to (empty = all webviews)
  public var webviews: [String]?

  /// Permission identifiers included in this capability
  public var permissions: [String]

  /// Whether this capability is enabled
  public var enabled: Bool?

  public init(
    identifier: String,
    description: String? = nil,
    windows: [String]? = nil,
    webviews: [String]? = nil,
    permissions: [String] = [],
    enabled: Bool? = true
  ) {
    self.identifier = identifier
    self.description = description
    self.windows = windows
    self.webviews = webviews
    self.permissions = permissions
    self.enabled = enabled
  }

  /// Check if this capability targets a specific webview
  public func targetsWebview(_ label: String) -> Bool {
    // If no specific targets, applies to all
    if (windows == nil || windows?.isEmpty == true)
      && (webviews == nil || webviews?.isEmpty == true)
    {
      return true
    }

    // Check webview-specific targeting
    if let webviews = webviews, webviews.contains(label) {
      return true
    }

    // Check window targeting (webview label often matches window label)
    if let windows = windows, windows.contains(label) {
      return true
    }

    return false
  }
}

// MARK: - Glob Matching Helper

/// Simple glob pattern matching
func matchGlob(pattern: String, value: String) -> Bool {
  // Convert glob to regex
  var regex = "^"
  for char in pattern {
    switch char {
    case "*":
      regex += ".*"
    case "?":
      regex += "."
    case ".":
      regex += "\\."
    case "/":
      regex += "/"
    case "(", ")", "[", "]", "{", "}", "^", "$", "+", "|", "\\":
      regex += "\\\(char)"
    default:
      regex += String(char)
    }
  }
  regex += "$"

  guard let re = try? NSRegularExpression(pattern: regex, options: []) else {
    return false
  }

  let range = NSRange(value.startIndex..., in: value)
  return re.firstMatch(in: value, options: [], range: range) != nil
}

/// URL pattern matching
func matchURLPattern(pattern: String, value: String) -> Bool {
  guard let patternURL = URL(string: pattern),
    let valueURL = URL(string: value)
  else {
    return pattern == value
  }

  // Check scheme
  if let patternScheme = patternURL.scheme,
    patternScheme != "*",
    patternScheme != valueURL.scheme
  {
    return false
  }

  // Check host with wildcard support
  if let patternHost = patternURL.host {
    guard let valueHost = valueURL.host else { return false }

    if patternHost.hasPrefix("*.") {
      let suffix = String(patternHost.dropFirst(2))
      if !valueHost.hasSuffix(suffix) && valueHost != suffix {
        return false
      }
    } else if patternHost != "*" && patternHost != valueHost {
      return false
    }
  }

  // Check path with glob support
  let patternPath = patternURL.path
  if !patternPath.isEmpty && patternPath != "/" {
    if !matchGlob(pattern: patternPath, value: valueURL.path) {
      return false
    }
  }

  return true
}

// MARK: - Permission Manager

/// Manages runtime permission checking
public final class PermissionManager: @unchecked Sendable {
  /// Registered capabilities
  private var capabilities: [String: CapabilityConfig] = [:]

  /// Registered permissions
  private var permissions: [String: PermissionConfig] = [:]

  /// Custom scope validators
  private var customValidators: [String: @Sendable (String) -> Bool] = [:]

  /// Default policy for app commands
  private var defaultAppPolicy: DefaultPolicy = .allow

  /// Default policy for plugin commands
  private var defaultPluginPolicy: DefaultPolicy = .deny

  /// Lock for thread safety
  private let lock = NSLock()

  public init() {}

  // MARK: - Configuration

  /// Configure from SecurityConfig fields
  public func configure(
    capabilities: [CapabilityConfig]?,
    permissions: [String: PermissionConfig]?,
    defaultAppCommandPolicy: DefaultPolicy?,
    defaultPluginCommandPolicy: DefaultPolicy?
  ) {
    lock.lock()
    defer { lock.unlock() }

    // Load capabilities
    if let caps = capabilities {
      for cap in caps where cap.enabled != false {
        self.capabilities[cap.identifier] = cap
      }
    }

    // Load permissions
    if let perms = permissions {
      self.permissions = perms
    }

    // Set default policies
    if let policy = defaultAppCommandPolicy {
      defaultAppPolicy = policy
    }
    if let policy = defaultPluginCommandPolicy {
      defaultPluginPolicy = policy
    }
  }

  /// Register a capability programmatically
  @discardableResult
  public func registerCapability(_ capability: CapabilityConfig) -> Self {
    lock.lock()
    defer { lock.unlock() }
    capabilities[capability.identifier] = capability
    return self
  }

  /// Register a permission programmatically
  @discardableResult
  public func registerPermission(_ permission: PermissionConfig) -> Self {
    lock.lock()
    defer { lock.unlock() }
    permissions[permission.identifier] = permission
    return self
  }

  /// Register a custom scope validator
  @discardableResult
  public func registerScopeValidator(
    _ name: String,
    validator: @escaping @Sendable (String) -> Bool
  ) -> Self {
    lock.lock()
    defer { lock.unlock() }
    customValidators[name] = validator
    return self
  }

  /// Set default policy for app commands
  @discardableResult
  public func setDefaultAppPolicy(_ policy: DefaultPolicy) -> Self {
    lock.lock()
    defer { lock.unlock() }
    defaultAppPolicy = policy
    return self
  }

  /// Set default policy for plugin commands
  @discardableResult
  public func setDefaultPluginPolicy(_ policy: DefaultPolicy) -> Self {
    lock.lock()
    defer { lock.unlock() }
    defaultPluginPolicy = policy
    return self
  }

  // MARK: - Permission Checking

  /// Check if a command is allowed for a given webview
  /// - Parameters:
  ///   - command: The command name (e.g., "greet" or "plugin:fs|read")
  ///   - webviewId: The webview identifier making the request
  ///   - scopeValues: Values to check against scopes (e.g., ["path": "/tmp/file.txt"])
  /// - Returns: Result indicating success or the permission error
  public func checkPermission(
    command: String,
    webviewId: String,
    scopeValues: [String: String] = [:]
  ) -> Result<Void, PermissionError> {
    lock.lock()
    defer { lock.unlock() }

    // Determine if this is a plugin command
    let isPluginCommand = command.hasPrefix("plugin:")

    // Get default policy
    let defaultPolicy = isPluginCommand ? defaultPluginPolicy : defaultAppPolicy

    // If no capabilities configured, use default policy
    if capabilities.isEmpty {
      return defaultPolicy == .allow
        ? .success(()) : .failure(.denied(command: command, reason: "No capabilities configured"))
    }

    // Check if any capability covers this command and if it's allowed for this webview
    var commandCoveredByCapability = false

    for capability in capabilities.values {
      for permissionId in capability.permissions {
        if permissionId == "*" || commandMatchesPermission(command: command, permissionId: permissionId) {
          commandCoveredByCapability = true

          // Check if this capability targets the requesting webview
          if capability.targetsWebview(webviewId) {
            // Check permission config if exists
            if let permConfig = permissions[permissionId] {
              let result = checkPermissionConfig(permConfig, command: command, scopeValues: scopeValues)
              if case .success = result {
                return .success(())
              }
              // If permission config denied, continue checking other capabilities
            } else {
              // Simple permission without config - allow
              return .success(())
            }
          }
        }
      }
    }

    // If command is covered by any capability but not allowed for this webview, deny
    if commandCoveredByCapability {
      return .failure(.denied(command: command, reason: "Not allowed by any capability targeting this webview"))
    }

    // Command not covered by any capability
    // Since capabilities are configured, uncovered commands are denied unless they're
    // app commands with default allow policy AND no capability targets this webview at all
    let webviewHasCapabilities = capabilities.values.contains { $0.targetsWebview(webviewId) }

    if !webviewHasCapabilities && defaultPolicy == .allow {
      // No capabilities target this webview, use default policy
      return .success(())
    }

    // Capabilities exist for this webview but don't cover this command - deny
    return .failure(.denied(command: command, reason: "No capability grants this command"))
  }

  /// Check a specific capability for a command
  private func checkCapability(
    _ capability: CapabilityConfig,
    command: String,
    scopeValues: [String: String]
  ) -> Result<Void, PermissionError> {
    // Check each permission in the capability
    for permissionId in capability.permissions {
      // Handle wildcard permission
      if permissionId == "*" {
        return .success(())
      }

      // Handle command prefix permissions (e.g., "greet" allows "greet" command)
      if commandMatchesPermission(command: command, permissionId: permissionId) {
        // Check if there's a detailed permission config
        if let permConfig = permissions[permissionId] {
          let result = checkPermissionConfig(permConfig, command: command, scopeValues: scopeValues)
          if case .success = result {
            return .success(())
          }
        } else {
          // Simple permission without config - allow
          return .success(())
        }
      }
    }

    return .failure(.denied(command: command, reason: "Not in capability permissions"))
  }

  /// Check if a command matches a permission identifier
  private func commandMatchesPermission(command: String, permissionId: String) -> Bool {
    // Exact match
    if command == permissionId {
      return true
    }

    // Prefix match for plugin commands
    // e.g., permission "plugin:fs" matches command "plugin:fs|read"
    if command.hasPrefix("\(permissionId)|") {
      return true
    }

    // Wildcard within permission
    // e.g., permission "plugin:fs|*" matches "plugin:fs|read"
    if permissionId.hasSuffix("|*") {
      let prefix = String(permissionId.dropLast(2))
      if command.hasPrefix(prefix) {
        return true
      }
    }

    // Legacy wildcard form for migration
    // e.g., permission "plugin:fs|*" matches "plugin:fs|read"
    if permissionId.hasSuffix(":*") {
      let prefix = String(permissionId.dropLast(2))
      if command.hasPrefix("\(prefix)|") {
        return true
      }
    }

    return false
  }

  /// Check a permission configuration
  private func checkPermissionConfig(
    _ config: PermissionConfig,
    command: String,
    scopeValues: [String: String]
  ) -> Result<Void, PermissionError> {
    // Check deny list first (deny takes priority)
    if let denyList = config.deny, !denyList.isEmpty {
      for pattern in denyList {
        if commandMatchesPattern(command: command, pattern: pattern) {
          return .failure(.denied(command: command, reason: "Explicitly denied"))
        }
      }
    }

    // Check allow list
    if let allowList = config.allow, !allowList.isEmpty {
      var allowed = false
      for pattern in allowList {
        if commandMatchesPattern(command: command, pattern: pattern) {
          allowed = true
          break
        }
      }
      if !allowed {
        return .failure(.denied(command: command, reason: "Not in allow list"))
      }
    }

    // Check scopes
    if let scopes = config.scopes {
      for (scopeName, scope) in scopes {
        if let value = scopeValues[scopeName] {
          let customValidator: ((String, String) -> Bool)? = { [weak self] name, val in
            guard let validator = self?.customValidators[name] else { return false }
            return validator(val)
          }
          if !scope.allows(value, customValidator: customValidator) {
            return .failure(.scopeViolation(command: command, scope: scopeName, value: value))
          }
        }
      }
    }

    return .success(())
  }

  /// Check if a command matches a pattern (supports wildcards)
  private func commandMatchesPattern(command: String, pattern: String) -> Bool {
    if pattern == "*" {
      return true
    }
    if pattern == command {
      return true
    }
    if pattern.hasSuffix("*") {
      let prefix = String(pattern.dropLast())
      return command.hasPrefix(prefix)
    }
    return false
  }

  // MARK: - Scope Access

  /// Get the scope for a permission and scope name
  public func getScope(permission: String, scopeName: String) -> PermissionScope? {
    lock.lock()
    defer { lock.unlock() }
    return permissions[permission]?.scopes?[scopeName]
  }

  /// Get all scopes for a command based on applicable capabilities
  public func getScopesForCommand(
    _ command: String,
    webviewId: String
  ) -> [String: PermissionScope] {
    lock.lock()
    defer { lock.unlock() }

    var result: [String: PermissionScope] = [:]

    let applicableCapabilities = capabilities.values.filter { $0.targetsWebview(webviewId) }

    for capability in applicableCapabilities {
      for permissionId in capability.permissions {
        if commandMatchesPermission(command: command, permissionId: permissionId) {
          if let scopes = permissions[permissionId]?.scopes {
            for (name, scope) in scopes {
              result[name] = scope
            }
          }
        }
      }
    }

    return result
  }

  // MARK: - Debugging

  /// Get all registered capability identifiers
  public var capabilityIdentifiers: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(capabilities.keys)
  }

  /// Get all registered permission identifiers
  public var permissionIdentifiers: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(permissions.keys)
  }
}
