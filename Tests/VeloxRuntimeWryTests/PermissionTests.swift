// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import VeloxRuntime
@testable import VeloxRuntimeWry

// MARK: - Permission Manager Tests

@Suite("PermissionManager")
struct PermissionManagerTests {

  // MARK: - Default Policy Tests

  @Test("Default allow policy for app commands")
  func defaultAllowPolicyForAppCommands() {
    let manager = PermissionManager()

    // With no capabilities configured, app commands use default allow
    let result = manager.checkPermission(
      command: "greet",
      webviewId: "main"
    )

    #expect(result.isSuccess, "App commands should be allowed by default when no capabilities configured")
  }

  @Test("Default deny policy for plugin commands")
  func defaultDenyPolicyForPluginCommands() {
    let manager = PermissionManager()

    // Configure with a capability so default policy applies
    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        windows: ["main"],
        permissions: ["greet"]
      ))

    let result = manager.checkPermission(
      command: "plugin:fs:read",
      webviewId: "main"
    )

    #expect(result.isFailure, "Plugin commands should be denied by default")
  }

  // MARK: - Capability Targeting Tests

  @Test("Capability window targeting")
  func capabilityWindowTargeting() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "main-only",
        windows: ["main"],
        permissions: ["secret"]
      ))

    // Main window should have access
    let mainResult = manager.checkPermission(
      command: "secret",
      webviewId: "main"
    )
    #expect(mainResult.isSuccess, "Main window should have access to 'secret'")

    // Other window should not
    let otherResult = manager.checkPermission(
      command: "secret",
      webviewId: "settings"
    )
    #expect(otherResult.isFailure, "Settings window should not have access to 'secret'")
  }

  @Test("Capability with no targets applies to all windows")
  func capabilityWithNoTargetsAppliesToAll() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "global",
        permissions: ["ping"]
      ))

    // Any webview should have access
    #expect(
      manager.checkPermission(command: "ping", webviewId: "main").isSuccess,
      "Main should have access")
    #expect(
      manager.checkPermission(command: "ping", webviewId: "settings").isSuccess,
      "Settings should have access")
    #expect(
      manager.checkPermission(command: "ping", webviewId: "any").isSuccess,
      "Any webview should have access")
  }

  // MARK: - Permission Allow/Deny Tests

  @Test("Deny takes priority over allow")
  func denyTakesPriorityOverAllow() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["plugin:fs:*"]
      ))

    manager.registerPermission(
      PermissionConfig(
        identifier: "plugin:fs:*",
        allow: ["plugin:fs:*"],
        deny: ["plugin:fs:delete"]
      ))

    // Read should be allowed
    #expect(
      manager.checkPermission(command: "plugin:fs:read", webviewId: "main").isSuccess,
      "Read should be allowed")

    // Delete should be denied (deny takes priority)
    #expect(
      manager.checkPermission(command: "plugin:fs:delete", webviewId: "main").isFailure,
      "Delete should be denied")
  }

  @Test("Wildcard permission grants all commands")
  func wildcardPermission() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "admin",
        windows: ["admin"],
        permissions: ["*"]
      ))

    // Should allow any command
    #expect(
      manager.checkPermission(command: "anything", webviewId: "admin").isSuccess,
      "Wildcard should allow any command")
    #expect(
      manager.checkPermission(command: "plugin:fs:delete", webviewId: "admin").isSuccess,
      "Wildcard should allow plugin commands too")
  }

  @Test("Plugin wildcard permission")
  func pluginWildcardPermission() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["plugin:analytics:*"]
      ))

    #expect(
      manager.checkPermission(command: "plugin:analytics:track", webviewId: "main").isSuccess,
      "Should allow analytics:track")
    #expect(
      manager.checkPermission(command: "plugin:analytics:stats", webviewId: "main").isSuccess,
      "Should allow analytics:stats")
    #expect(
      manager.checkPermission(command: "plugin:fs:read", webviewId: "main").isFailure,
      "Should not allow fs:read")
  }

  // MARK: - Scope Tests

  @Test("Path scope with glob patterns")
  func pathScopeWithGlobs() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["fs:read"]
      ))

    manager.registerPermission(
      PermissionConfig(
        identifier: "fs:read",
        scopes: [
          "path": .globs(["/tmp/*", "/home/user/Documents/*"])
        ]
      ))

    // Allowed path
    #expect(
      manager.checkPermission(
        command: "fs:read",
        webviewId: "main",
        scopeValues: ["path": "/tmp/file.txt"]
      ).isSuccess,
      "/tmp/file.txt should be allowed")

    // Disallowed path
    #expect(
      manager.checkPermission(
        command: "fs:read",
        webviewId: "main",
        scopeValues: ["path": "/etc/passwd"]
      ).isFailure,
      "/etc/passwd should be denied")
  }

  @Test("URL scope with patterns")
  func urlScopeWithPatterns() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["http:fetch"]
      ))

    manager.registerPermission(
      PermissionConfig(
        identifier: "http:fetch",
        scopes: [
          "url": .urls(["https://api.example.com/*", "https://*.trusted.com/*"])
        ]
      ))

    // Allowed URLs
    #expect(
      manager.checkPermission(
        command: "http:fetch",
        webviewId: "main",
        scopeValues: ["url": "https://api.example.com/users"]
      ).isSuccess,
      "api.example.com should be allowed")

    // Disallowed URL
    #expect(
      manager.checkPermission(
        command: "http:fetch",
        webviewId: "main",
        scopeValues: ["url": "https://evil.com/steal"]
      ).isFailure,
      "evil.com should be denied")
  }

  @Test("Custom scope validator")
  func customScopeValidator() {
    let manager = PermissionManager()

    // Register custom validator for file size
    manager.registerScopeValidator("fileSize") { value in
      guard let size = Int(value) else { return false }
      return size <= 10_000_000  // 10MB limit
    }

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["upload"]
      ))

    manager.registerPermission(
      PermissionConfig(
        identifier: "upload",
        scopes: ["size": .custom("fileSize")]
      ))

    // Under limit
    #expect(
      manager.checkPermission(
        command: "upload",
        webviewId: "main",
        scopeValues: ["size": "5000000"]
      ).isSuccess,
      "5MB upload should be allowed")

    // Over limit
    #expect(
      manager.checkPermission(
        command: "upload",
        webviewId: "main",
        scopeValues: ["size": "50000000"]
      ).isFailure,
      "50MB upload should be denied")
  }

  // MARK: - Configuration Loading

  @Test("Configure from SecurityConfig")
  func configureFromSecurityConfig() {
    let manager = PermissionManager()

    manager.configure(
      capabilities: [
        CapabilityConfig(
          identifier: "main",
          windows: ["main"],
          permissions: ["greet", "plugin:analytics:*"]
        )
      ],
      permissions: [
        "plugin:analytics:track": PermissionConfig(
          identifier: "plugin:analytics:track",
          scopes: ["event": .values(["click", "view", "purchase"])]
        )
      ],
      defaultAppCommandPolicy: .allow,
      defaultPluginCommandPolicy: .deny
    )

    // Should work based on loaded config
    #expect(
      manager.checkPermission(command: "greet", webviewId: "main").isSuccess,
      "Greet should be allowed for main window")
    #expect(
      manager.checkPermission(command: "plugin:analytics:track", webviewId: "main").isSuccess,
      "Analytics track should be allowed")
  }

  // MARK: - Command Registry Integration

  @Test("CommandRegistry integration with permissions")
  func commandRegistryWithPermissions() {
    let registry = CommandRegistry()
    registry.register("greet", returning: String.self) { _ in "Hello!" }
    registry.register("secret", returning: String.self) { _ in "Secret data" }

    let manager = PermissionManager()
    manager.registerCapability(
      CapabilityConfig(
        identifier: "main",
        windows: ["main"],
        permissions: ["greet"]
      ))

    let context = CommandContext(
      command: "greet",
      rawBody: Data(),
      headers: [:],
      webviewId: "main",
      stateContainer: StateContainer(),
      webview: nil
    )

    // Allowed command
    let result1 = registry.invoke("greet", context: context, permissionManager: manager)
    #expect(result1.isSuccess, "Greet should succeed")

    // Denied command
    let context2 = CommandContext(
      command: "secret",
      rawBody: Data(),
      headers: [:],
      webviewId: "main",
      stateContainer: StateContainer(),
      webview: nil
    )
    let result2 = registry.invoke("secret", context: context2, permissionManager: manager)

    if case .error(let error) = result2 {
      #expect(error.code == "PermissionDenied", "Should return PermissionDenied error")
    } else {
      Issue.record("Secret should be denied")
    }
  }
}

// MARK: - Permission Scope Tests

@Suite("PermissionScope")
struct PermissionScopeTests {

  @Test("Any scope allows all values")
  func anyScopeAllowsAll() {
    let scope = PermissionScope.any
    #expect(scope.allows("anything"))
    #expect(scope.allows("/path/to/file"))
    #expect(scope.allows(""))
  }

  @Test("Values scope matches exact values")
  func valuesScope() {
    let scope = PermissionScope.values(["read", "write", "execute"])

    #expect(scope.allows("read"))
    #expect(scope.allows("write"))
    #expect(!scope.allows("delete"))
    #expect(!scope.allows("READ"))  // case sensitive
  }

  @Test("Globs scope matches patterns")
  func globsScope() {
    let scope = PermissionScope.globs(["/tmp/*", "*.txt"])

    #expect(scope.allows("/tmp/file"))
    #expect(scope.allows("/tmp/subdir/file"))
    #expect(scope.allows("document.txt"))
    #expect(!scope.allows("/etc/passwd"))
  }

  @Test("URLs scope matches URL patterns")
  func urlsScope() {
    let scope = PermissionScope.urls([
      "https://api.example.com/*"
    ])

    #expect(scope.allows("https://api.example.com/users"))
    #expect(scope.allows("https://api.example.com/data/123"))
    #expect(!scope.allows("https://evil.com/api"))
  }

  @Test("Scope is Codable")
  func scopeCodable() throws {
    let scope = PermissionScope.globs(["/tmp/*", "/var/*"])

    let encoder = JSONEncoder()
    let data = try encoder.encode(scope)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(PermissionScope.self, from: data)

    #expect(scope == decoded)
  }
}

// MARK: - Capability Config Tests

@Suite("CapabilityConfig")
struct CapabilityConfigTests {

  @Test("Capability targets specific webviews")
  func capabilityTargetsWebview() {
    let capability = CapabilityConfig(
      identifier: "test",
      windows: ["main", "settings"],
      permissions: ["greet"]
    )

    #expect(capability.targetsWebview("main"))
    #expect(capability.targetsWebview("settings"))
    #expect(!capability.targetsWebview("other"))
  }

  @Test("Capability with no targets applies to all")
  func capabilityWithNoTargetsAppliesToAll() {
    let capability = CapabilityConfig(
      identifier: "global",
      permissions: ["ping"]
    )

    #expect(capability.targetsWebview("main"))
    #expect(capability.targetsWebview("any"))
    #expect(capability.targetsWebview("window123"))
  }

  @Test("Capability is Codable")
  func capabilityCodable() throws {
    let capability = CapabilityConfig(
      identifier: "test",
      description: "Test capability",
      windows: ["main"],
      permissions: ["greet", "plugin:analytics:*"]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(capability)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(CapabilityConfig.self, from: data)

    #expect(decoded.identifier == capability.identifier)
    #expect(decoded.description == capability.description)
    #expect(decoded.windows == capability.windows)
    #expect(decoded.permissions == capability.permissions)
  }
}

// MARK: - Helper Extensions

extension Result {
  var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }

  var isFailure: Bool {
    !isSuccess
  }
}

extension CommandResult {
  var isSuccess: Bool {
    switch self {
    case .success, .binary: return true
    case .error: return false
    }
  }
}
