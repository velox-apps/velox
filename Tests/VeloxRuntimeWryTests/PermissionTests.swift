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

// MARK: - Security Configuration Tests

@Suite("SecurityConfig")
struct SecurityConfigTests {

  @Test("CSP string configuration")
  func cspStringConfig() throws {
    let json = """
      {
        "csp": "default-src 'self'; script-src 'unsafe-inline'"
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .string(let value) = config.csp else {
      Issue.record("CSP should be a string")
      return
    }
    #expect(value.contains("default-src"))
    #expect(config.csp?.buildHeaderValue() == "default-src 'self'; script-src 'unsafe-inline'")
  }

  @Test("CSP directives configuration")
  func cspDirectivesConfig() throws {
    let json = """
      {
        "csp": {
          "default-src": "'self'",
          "script-src": ["'self'", "'unsafe-inline'"],
          "img-src": "'self' data: blob:"
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .directives(let directives) = config.csp else {
      Issue.record("CSP should be directives")
      return
    }
    #expect(directives.count == 3)

    let headerValue = config.csp?.buildHeaderValue() ?? ""
    #expect(headerValue.contains("default-src 'self'"))
    #expect(headerValue.contains("script-src 'self' 'unsafe-inline'"))
  }

  @Test("Asset protocol configuration")
  func assetProtocolConfig() throws {
    let json = """
      {
        "assetProtocol": {
          "enable": true,
          "scope": ["/tmp/*", "$HOME/Documents/*"]
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    #expect(config.assetProtocol?.isEnabled == true)
    #expect(config.assetProtocol?.scope?.count == 2)
    #expect(config.assetProtocol?.scope?.first == "/tmp/*")
  }

  @Test("Asset protocol disabled by default")
  func assetProtocolDisabledByDefault() throws {
    let json = """
      {
        "assetProtocol": {
          "scope": ["/tmp/*"]
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    #expect(config.assetProtocol?.isEnabled == false)
  }

  @Test("Pattern brownfield configuration")
  func patternBrownfieldConfig() throws {
    let json = """
      {
        "pattern": {
          "use": "brownfield"
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .brownfield = config.pattern else {
      Issue.record("Pattern should be brownfield")
      return
    }
  }

  @Test("Pattern isolation configuration")
  func patternIsolationConfig() throws {
    let json = """
      {
        "pattern": {
          "use": "isolation",
          "options": {
            "dir": "../dist-isolation"
          }
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .isolation(let isolationConfig) = config.pattern else {
      Issue.record("Pattern should be isolation")
      return
    }
    #expect(isolationConfig.dir == "../dist-isolation")
  }

  @Test("Custom headers configuration")
  func customHeadersConfig() throws {
    let json = """
      {
        "headers": {
          "X-Frame-Options": "DENY",
          "X-Content-Type-Options": "nosniff"
        }
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    #expect(config.headers?["X-Frame-Options"] == "DENY")
    #expect(config.headers?["X-Content-Type-Options"] == "nosniff")
  }

  @Test("Dangerous disable CSP modification - all")
  func dangerousDisableCspAll() throws {
    let json = """
      {
        "dangerousDisableAssetCspModification": true
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .all = config.dangerousDisableAssetCspModification else {
      Issue.record("Should disable all CSP modifications")
      return
    }
    #expect(config.dangerousDisableAssetCspModification?.shouldDisable(directive: "script-src") == true)
  }

  @Test("Dangerous disable CSP modification - selective")
  func dangerousDisableCspSelective() throws {
    let json = """
      {
        "dangerousDisableAssetCspModification": ["script-src", "style-src"]
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    guard case .directives(let directives) = config.dangerousDisableAssetCspModification else {
      Issue.record("Should have specific directives")
      return
    }
    #expect(directives.count == 2)
    #expect(config.dangerousDisableAssetCspModification?.shouldDisable(directive: "script-src") == true)
    #expect(config.dangerousDisableAssetCspModification?.shouldDisable(directive: "img-src") == false)
  }

  @Test("Freeze prototype configuration")
  func freezePrototypeConfig() throws {
    let json = """
      {
        "freezePrototype": true
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    #expect(config.freezePrototype == true)
  }

  @Test("Full security configuration")
  func fullSecurityConfig() throws {
    let json = """
      {
        "csp": "default-src 'self'",
        "devCsp": "default-src 'self' 'unsafe-eval'",
        "freezePrototype": true,
        "assetProtocol": {
          "enable": true,
          "scope": ["/tmp/*"]
        },
        "pattern": {
          "use": "brownfield"
        },
        "headers": {
          "X-Custom": "value"
        },
        "dangerousDisableAssetCspModification": false,
        "capabilities": [
          {
            "identifier": "main",
            "windows": ["main"],
            "permissions": ["greet"]
          }
        ],
        "defaultAppCommandPolicy": "allow",
        "defaultPluginCommandPolicy": "deny"
      }
      """
    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(SecurityConfig.self, from: data)

    #expect(config.csp != nil)
    #expect(config.devCsp != nil)
    #expect(config.freezePrototype == true)
    #expect(config.assetProtocol?.isEnabled == true)
    #expect(config.headers?["X-Custom"] == "value")
    #expect(config.capabilities?.count == 1)
    #expect(config.defaultAppCommandPolicy == .allow)
    #expect(config.defaultPluginCommandPolicy == .deny)
  }
}

// MARK: - CSP Builder Tests

@Suite("CSPBuilder")
struct CSPBuilderTests {

  @Test("Build CSP from directives")
  func buildFromDirectives() {
    var builder = CSPBuilder()
    builder.set(directive: "default-src", sources: ["'self'"])
    builder.set(directive: "script-src", sources: ["'self'", "'unsafe-inline'"])

    let result = builder.build()
    #expect(result.contains("default-src 'self'"))
    #expect(result.contains("script-src 'self' 'unsafe-inline'"))
  }

  @Test("Add source to directive")
  func addSource() {
    var builder = CSPBuilder()
    builder.set(directive: "default-src", sources: ["'self'"])
    builder.add(source: "app:", to: "default-src")

    let sources = builder.get(directive: "default-src")
    #expect(sources.contains("'self'"))
    #expect(sources.contains("app:"))
  }

  @Test("Initialize from CSPConfig string")
  func initFromString() {
    let config = CSPConfig.string("default-src 'self'; script-src 'unsafe-inline'")
    let builder = CSPBuilder(from: config)

    #expect(builder.get(directive: "default-src") == ["'self'"])
    #expect(builder.get(directive: "script-src") == ["'unsafe-inline'"])
  }

  @Test("Initialize from CSPConfig directives")
  func initFromDirectives() {
    let config = CSPConfig.directives([
      "default-src": .single("'self'"),
      "script-src": .multiple(["'self'", "'unsafe-inline'"])
    ])
    let builder = CSPBuilder(from: config)

    #expect(builder.get(directive: "default-src") == ["'self'"])
    #expect(builder.get(directive: "script-src") == ["'self'", "'unsafe-inline'"])
  }

  @Test("Default CSP has required sources")
  func defaultCSP() {
    let builder = CSPBuilder.defaultCSP

    #expect(builder.get(directive: "default-src").contains("'self'"))
    #expect(builder.get(directive: "connect-src").contains("ipc:"))
  }
}

// MARK: - Asset Path Validator Tests

@Suite("AssetPathValidator")
struct AssetPathValidatorTests {

  @Test("Empty scope denies all")
  func emptyScopeDeniesAll() {
    let validator = AssetPathValidator(scope: [])
    #expect(!validator.isAllowed("/tmp/file.txt"))
    #expect(!validator.isAllowed("/any/path"))
  }

  @Test("Glob pattern matches")
  func globPatternMatches() {
    let validator = AssetPathValidator(scope: ["/tmp/*"])
    #expect(validator.isAllowed("/tmp/file.txt"))
    #expect(validator.isAllowed("/tmp/subdir/file.txt"))
    #expect(!validator.isAllowed("/etc/passwd"))
  }

  @Test("Multiple patterns")
  func multiplePatterns() {
    let validator = AssetPathValidator(scope: ["/tmp/*", "/var/log/*"])
    #expect(validator.isAllowed("/tmp/file.txt"))
    #expect(validator.isAllowed("/var/log/app.log"))
    #expect(!validator.isAllowed("/etc/passwd"))
  }

  @Test("Home directory expansion")
  func homeDirectoryExpansion() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let validator = AssetPathValidator(scope: ["~/Documents/*"])
    #expect(validator.isAllowed("\(home)/Documents/file.txt"))
  }
}

// MARK: - Security Script Generator Tests

@Suite("SecurityScriptGenerator")
struct SecurityScriptGeneratorTests {

  @Test("No freeze script when freezePrototype is false")
  func noFreezeScriptWhenDisabled() {
    let config = SecurityConfig(freezePrototype: false)
    let script = SecurityScriptGenerator.generateInitScript(config: config, includeChannelAPI: false)
    #expect(script.isEmpty)
  }

  @Test("No freeze script when config is nil")
  func noFreezeScriptWhenNil() {
    let script = SecurityScriptGenerator.generateInitScript(config: nil, includeChannelAPI: false)
    #expect(script.isEmpty)
  }

  @Test("Generates freeze script when enabled")
  func generatesScriptWhenEnabled() {
    let config = SecurityConfig(freezePrototype: true)
    let script = SecurityScriptGenerator.generateInitScript(config: config, includeChannelAPI: false)
    #expect(!script.isEmpty)
    #expect(script.contains("Object.freeze"))
    #expect(script.contains("Object.prototype"))
  }

  @Test("Freeze prototype script freezes all prototypes")
  func freezePrototypeScriptContent() {
    let script = SecurityScriptGenerator.freezePrototypeScript
    #expect(script.contains("Object.freeze(Object.prototype)"))
    #expect(script.contains("Object.freeze(Array.prototype)"))
    #expect(script.contains("Object.freeze(Function.prototype)"))
    #expect(script.contains("Object.freeze(String.prototype)"))
  }

  @Test("Includes channel API by default")
  func includesChannelAPIByDefault() {
    let script = SecurityScriptGenerator.generateInitScript(config: nil)
    #expect(script.contains("VeloxChannel"))
    #expect(script.contains("__veloxChannels"))
  }

  @Test("Can exclude channel API")
  func excludeChannelAPI() {
    let script = SecurityScriptGenerator.generateInitScript(config: nil, includeChannelAPI: false)
    #expect(!script.contains("VeloxChannel"))
  }
}

// MARK: - Channel Tests

@Suite("Channel")
struct ChannelTests {

  @Test("Channel reference decoding")
  func channelRefDecoding() throws {
    let json = """
      {
        "__channelId": "ch_abc123_1234567890"
      }
      """
    let data = Data(json.utf8)
    let ref = try JSONDecoder().decode(ChannelRef.self, from: data)

    #expect(ref.channelId == "ch_abc123_1234567890")
  }

  @Test("Channel reference encoding")
  func channelRefEncoding() throws {
    let ref = ChannelRef(channelId: "ch_test123")
    let data = try JSONEncoder().encode(ref)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["__channelId"] as? String == "ch_test123")
  }

  @Test("Channel starts open")
  func channelStartsOpen() {
    let channel = Channel<String>(id: "test", webview: nil)
    #expect(!channel.closed)
  }

  @Test("Channel can be closed")
  func channelCanBeClosed() {
    let channel = Channel<String>(id: "test", webview: nil)
    channel.close()
    #expect(channel.closed)
  }

  @Test("Send fails after close")
  func sendFailsAfterClose() {
    let channel = Channel<String>(id: "test", webview: nil)
    channel.close()
    let result = channel.send("message")
    #expect(!result)
  }

  @Test("ChannelRegistry stores and retrieves channels")
  func channelRegistryOperations() {
    let registry = ChannelRegistry()
    let channel = Channel<String>(id: "test-channel", webview: nil)

    registry.register(channel)

    let retrieved = registry.get("test-channel", as: String.self)
    #expect(retrieved?.id == "test-channel")
  }

  @Test("ChannelRegistry removes channels")
  func channelRegistryRemove() {
    let registry = ChannelRegistry()
    let channel = Channel<String>(id: "test-channel", webview: nil)

    registry.register(channel)
    registry.remove("test-channel")

    let retrieved = registry.get("test-channel", as: String.self)
    #expect(retrieved == nil)
  }

  @Test("CommandContext extracts channel from args")
  func commandContextChannel() {
    let json = """
      {
        "onProgress": {
          "__channelId": "ch_progress_123"
        },
        "other": "value"
      }
      """
    let context = CommandContext(
      command: "test",
      rawBody: Data(json.utf8),
      webviewId: "main"
    )

    #expect(context.hasChannel("onProgress"))
    #expect(!context.hasChannel("other"))
    #expect(!context.hasChannel("missing"))
  }
}

// MARK: - Progress Event Tests

@Suite("ProgressEvent")
struct ProgressEventTests {

  @Test("Progress percentage calculation")
  func progressPercentage() {
    let event = ProgressEvent(current: 50, total: 100)
    #expect(event.percentage == 50.0)
  }

  @Test("Progress percentage with no total")
  func progressPercentageNoTotal() {
    let event = ProgressEvent(current: 50, total: nil)
    #expect(event.percentage == nil)
  }

  @Test("Progress event encoding")
  func progressEventEncoding() throws {
    let event = ProgressEvent(current: 75, total: 100, message: "Downloading...")
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["current"] as? UInt64 == 75)
    #expect(json?["total"] as? UInt64 == 100)
    #expect(json?["message"] as? String == "Downloading...")
  }
}

// MARK: - Download Event Tests

@Suite("DownloadEvent")
struct DownloadEventTests {

  @Test("Download started encoding")
  func downloadStartedEncoding() throws {
    let event = DownloadEvent.started(url: "https://example.com/file.zip", contentLength: 1024)
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "started")
    let eventData = json?["data"] as? [String: Any]
    #expect(eventData?["url"] as? String == "https://example.com/file.zip")
    #expect(eventData?["contentLength"] as? UInt64 == 1024)
  }

  @Test("Download progress encoding")
  func downloadProgressEncoding() throws {
    let event = DownloadEvent.progress(bytesReceived: 512, totalBytes: 1024)
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "progress")
    let eventData = json?["data"] as? [String: Any]
    #expect(eventData?["bytesReceived"] as? UInt64 == 512)
  }

  @Test("Download finished encoding")
  func downloadFinishedEncoding() throws {
    let event = DownloadEvent.finished(path: "/tmp/file.zip")
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "finished")
    let eventData = json?["data"] as? [String: Any]
    #expect(eventData?["path"] as? String == "/tmp/file.zip")
  }

  @Test("Download failed encoding")
  func downloadFailedEncoding() throws {
    let event = DownloadEvent.failed(error: "Network error")
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "failed")
    let eventData = json?["data"] as? [String: Any]
    #expect(eventData?["error"] as? String == "Network error")
  }
}

// MARK: - Stream Event Tests

@Suite("StreamEvent")
struct StreamEventTests {

  @Test("Stream data event encoding")
  func streamDataEncoding() throws {
    let event = StreamEvent<String>.data("Hello, World!")
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "data")
    #expect(json?["data"] as? String == "Hello, World!")
  }

  @Test("Stream end event encoding")
  func streamEndEncoding() throws {
    let event = StreamEvent<String>.end
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "end")
  }

  @Test("Stream error event encoding")
  func streamErrorEncoding() throws {
    let event = StreamEvent<String>.error("Something went wrong")
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["event"] as? String == "error")
    #expect(json?["data"] as? String == "Something went wrong")
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
