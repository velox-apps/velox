// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

#if os(macOS)
import IOKit
#endif

/// Built-in OS Info plugin for reading system information.
///
/// This plugin exposes the following commands:
/// - `plugin:os:platform` - Get the operating system platform
/// - `plugin:os:version` - Get the OS version
/// - `plugin:os:type` - Get the OS type
/// - `plugin:os:arch` - Get the CPU architecture
/// - `plugin:os:hostname` - Get the hostname
/// - `plugin:os:locale` - Get the system locale
/// - `plugin:os:tempdir` - Get the temp directory path
/// - `plugin:os:homedir` - Get the home directory path
///
/// Example frontend usage:
/// ```javascript
/// const platform = await invoke('plugin:os:platform'); // 'darwin'
/// const version = await invoke('plugin:os:version');   // '14.0.0'
/// const arch = await invoke('plugin:os:arch');         // 'aarch64' or 'x86_64'
/// ```
public final class OSInfoPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "os"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Get platform name
    commands.register("platform", returning: String.self) { _ in
      #if os(macOS)
      return "darwin"
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

    // Get OS version
    commands.register("version", returning: String.self) { _ in
      let version = ProcessInfo.processInfo.operatingSystemVersion
      return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    // Get OS type
    commands.register("type", returning: String.self) { _ in
      #if os(macOS)
      return "Darwin"
      #elseif os(iOS)
      return "iOS"
      #elseif os(Linux)
      return "Linux"
      #elseif os(Windows)
      return "Windows_NT"
      #else
      return "Unknown"
      #endif
    }

    // Get CPU architecture
    commands.register("arch", returning: String.self) { _ in
      #if arch(arm64)
      return "aarch64"
      #elseif arch(x86_64)
      return "x86_64"
      #elseif arch(i386)
      return "i686"
      #elseif arch(arm)
      return "arm"
      #else
      return "unknown"
      #endif
    }

    // Get hostname
    commands.register("hostname", returning: String.self) { _ in
      ProcessInfo.processInfo.hostName
    }

    // Get system locale
    commands.register("locale", returning: String?.self) { _ in
      Locale.current.identifier
    }

    // Get temp directory
    commands.register("tempdir", returning: String.self) { _ in
      NSTemporaryDirectory()
    }

    // Get home directory
    commands.register("homedir", returning: String.self) { _ in
      NSHomeDirectory()
    }

    // Get EOL character for current platform
    commands.register("eol", returning: String.self) { _ in
      #if os(Windows)
      return "\r\n"
      #else
      return "\n"
      #endif
    }

    // Get detailed system info
    commands.register("info", returning: SystemInfo.self) { _ in
      let version = ProcessInfo.processInfo.operatingSystemVersion

      return SystemInfo(
        platform: Self.platformName(),
        version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
        arch: Self.archName(),
        hostname: ProcessInfo.processInfo.hostName,
        locale: Locale.current.identifier,
        cpuCount: ProcessInfo.processInfo.processorCount,
        memoryTotal: ProcessInfo.processInfo.physicalMemory
      )
    }
  }

  // MARK: - Types

  struct SystemInfo: Codable, Sendable {
    let platform: String
    let version: String
    let arch: String
    let hostname: String
    let locale: String
    let cpuCount: Int
    let memoryTotal: UInt64
  }

  // MARK: - Helpers

  private static func platformName() -> String {
    #if os(macOS)
    return "darwin"
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

  private static func archName() -> String {
    #if arch(arm64)
    return "aarch64"
    #elseif arch(x86_64)
    return "x86_64"
    #elseif arch(i386)
    return "i686"
    #elseif arch(arm)
    return "arm"
    #else
    return "unknown"
    #endif
  }
}
