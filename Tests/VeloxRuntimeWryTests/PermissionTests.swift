// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import XCTest

@testable import VeloxRuntime
@testable import VeloxRuntimeWry

// MARK: - Permission Manager Tests

final class PermissionManagerTests: XCTestCase {

  // MARK: - Default Policy Tests

  func testDefaultAllowPolicyForAppCommands() {
    let manager = PermissionManager()

    // With no capabilities configured, app commands use default allow
    let result = manager.checkPermission(
      command: "greet",
      webviewId: "main"
    )

    switch result {
    case .success:
      // Expected - default is allow for app commands
      break
    case .failure:
      XCTFail("App commands should be allowed by default when no capabilities configured")
    }
  }

  func testDefaultDenyPolicyForPluginCommands() {
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

    switch result {
    case .success:
      XCTFail("Plugin commands should be denied by default")
    case .failure:
      // Expected - default is deny for plugin commands
      break
    }
  }

  // MARK: - Capability Targeting Tests

  func testCapabilityWindowTargeting() {
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
    XCTAssertTrue(mainResult.isSuccess, "Main window should have access to 'secret'")

    // Other window should not
    let otherResult = manager.checkPermission(
      command: "secret",
      webviewId: "settings"
    )
    XCTAssertTrue(otherResult.isFailure, "Settings window should not have access to 'secret'")
  }

  func testCapabilityWithNoTargetsAppliesToAll() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "global",
        permissions: ["ping"]
      ))

    // Any webview should have access
    XCTAssertTrue(
      manager.checkPermission(command: "ping", webviewId: "main").isSuccess,
      "Main should have access")
    XCTAssertTrue(
      manager.checkPermission(command: "ping", webviewId: "settings").isSuccess,
      "Settings should have access")
    XCTAssertTrue(
      manager.checkPermission(command: "ping", webviewId: "any").isSuccess,
      "Any webview should have access")
  }

  // MARK: - Permission Allow/Deny Tests

  func testDenyTakesPriorityOverAllow() {
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
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:fs:read", webviewId: "main").isSuccess,
      "Read should be allowed")

    // Delete should be denied (deny takes priority)
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:fs:delete", webviewId: "main").isFailure,
      "Delete should be denied")
  }

  func testWildcardPermission() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "admin",
        windows: ["admin"],
        permissions: ["*"]
      ))

    // Should allow any command
    XCTAssertTrue(
      manager.checkPermission(command: "anything", webviewId: "admin").isSuccess,
      "Wildcard should allow any command")
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:fs:delete", webviewId: "admin").isSuccess,
      "Wildcard should allow plugin commands too")
  }

  func testPluginWildcardPermission() {
    let manager = PermissionManager()

    manager.registerCapability(
      CapabilityConfig(
        identifier: "test",
        permissions: ["plugin:analytics:*"]
      ))

    XCTAssertTrue(
      manager.checkPermission(command: "plugin:analytics:track", webviewId: "main").isSuccess,
      "Should allow analytics:track")
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:analytics:stats", webviewId: "main").isSuccess,
      "Should allow analytics:stats")
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:fs:read", webviewId: "main").isFailure,
      "Should not allow fs:read")
  }

  // MARK: - Scope Tests

  func testPathScopeWithGlobs() {
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
    XCTAssertTrue(
      manager.checkPermission(
        command: "fs:read",
        webviewId: "main",
        scopeValues: ["path": "/tmp/file.txt"]
      ).isSuccess,
      "/tmp/file.txt should be allowed")

    // Disallowed path
    XCTAssertTrue(
      manager.checkPermission(
        command: "fs:read",
        webviewId: "main",
        scopeValues: ["path": "/etc/passwd"]
      ).isFailure,
      "/etc/passwd should be denied")
  }

  func testURLScopeWithPatterns() {
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
    XCTAssertTrue(
      manager.checkPermission(
        command: "http:fetch",
        webviewId: "main",
        scopeValues: ["url": "https://api.example.com/users"]
      ).isSuccess,
      "api.example.com should be allowed")

    // Disallowed URL
    XCTAssertTrue(
      manager.checkPermission(
        command: "http:fetch",
        webviewId: "main",
        scopeValues: ["url": "https://evil.com/steal"]
      ).isFailure,
      "evil.com should be denied")
  }

  func testCustomScopeValidator() {
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
    XCTAssertTrue(
      manager.checkPermission(
        command: "upload",
        webviewId: "main",
        scopeValues: ["size": "5000000"]
      ).isSuccess,
      "5MB upload should be allowed")

    // Over limit
    XCTAssertTrue(
      manager.checkPermission(
        command: "upload",
        webviewId: "main",
        scopeValues: ["size": "50000000"]
      ).isFailure,
      "50MB upload should be denied")
  }

  // MARK: - Configuration Loading

  func testConfigureFromSecurityConfig() {
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
    XCTAssertTrue(
      manager.checkPermission(command: "greet", webviewId: "main").isSuccess,
      "Greet should be allowed for main window")
    XCTAssertTrue(
      manager.checkPermission(command: "plugin:analytics:track", webviewId: "main").isSuccess,
      "Analytics track should be allowed")
  }

  // MARK: - Command Registry Integration

  func testCommandRegistryWithPermissions() {
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
    XCTAssertTrue(result1.isSuccess, "Greet should succeed")

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
    switch result2 {
    case .error(let error):
      XCTAssertEqual(error.code, "PermissionDenied", "Should return PermissionDenied error")
    default:
      XCTFail("Secret should be denied")
    }
  }
}

// MARK: - Permission Scope Tests

final class PermissionScopeTests: XCTestCase {

  func testAnyScopeAllowsAll() {
    let scope = PermissionScope.any
    XCTAssertTrue(scope.allows("anything"))
    XCTAssertTrue(scope.allows("/path/to/file"))
    XCTAssertTrue(scope.allows(""))
  }

  func testValuesScope() {
    let scope = PermissionScope.values(["read", "write", "execute"])

    XCTAssertTrue(scope.allows("read"))
    XCTAssertTrue(scope.allows("write"))
    XCTAssertFalse(scope.allows("delete"))
    XCTAssertFalse(scope.allows("READ"))  // case sensitive
  }

  func testGlobsScope() {
    let scope = PermissionScope.globs(["/tmp/*", "*.txt"])

    XCTAssertTrue(scope.allows("/tmp/file"))
    XCTAssertTrue(scope.allows("/tmp/subdir/file"))
    XCTAssertTrue(scope.allows("document.txt"))
    XCTAssertFalse(scope.allows("/etc/passwd"))
  }

  func testURLsScope() {
    let scope = PermissionScope.urls([
      "https://api.example.com/*"
    ])

    XCTAssertTrue(scope.allows("https://api.example.com/users"))
    XCTAssertTrue(scope.allows("https://api.example.com/data/123"))
    XCTAssertFalse(scope.allows("https://evil.com/api"))
  }

  func testScopeCodable() throws {
    let scope = PermissionScope.globs(["/tmp/*", "/var/*"])

    let encoder = JSONEncoder()
    let data = try encoder.encode(scope)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(PermissionScope.self, from: data)

    XCTAssertEqual(scope, decoded)
  }
}

// MARK: - Capability Config Tests

final class CapabilityConfigTests: XCTestCase {

  func testCapabilityTargetsWebview() {
    let capability = CapabilityConfig(
      identifier: "test",
      windows: ["main", "settings"],
      permissions: ["greet"]
    )

    XCTAssertTrue(capability.targetsWebview("main"))
    XCTAssertTrue(capability.targetsWebview("settings"))
    XCTAssertFalse(capability.targetsWebview("other"))
  }

  func testCapabilityWithNoTargetsAppliesToAll() {
    let capability = CapabilityConfig(
      identifier: "global",
      permissions: ["ping"]
    )

    XCTAssertTrue(capability.targetsWebview("main"))
    XCTAssertTrue(capability.targetsWebview("any"))
    XCTAssertTrue(capability.targetsWebview("window123"))
  }

  func testCapabilityCodable() throws {
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

    XCTAssertEqual(decoded.identifier, capability.identifier)
    XCTAssertEqual(decoded.description, capability.description)
    XCTAssertEqual(decoded.windows, capability.windows)
    XCTAssertEqual(decoded.permissions, capability.permissions)
  }
}

// MARK: - Helper Extension

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
