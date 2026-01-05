// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

/// Built-in Process plugin for accessing current process information.
///
/// This plugin exposes the following commands:
/// - `plugin:process:exit` - Exit the application
/// - `plugin:process:relaunch` - Relaunch the application
/// - `plugin:process:pid` - Get the process ID
/// - `plugin:process:cwd` - Get the current working directory
/// - `plugin:process:env` - Get environment variables
/// - `plugin:process:args` - Get command line arguments
///
/// Example frontend usage:
/// ```javascript
/// // Get process ID
/// const pid = await invoke('plugin:process:pid');
///
/// // Get environment variable
/// const home = await invoke('plugin:process:env', { name: 'HOME' });
///
/// // Exit application
/// await invoke('plugin:process:exit', { code: 0 });
/// ```
public final class ProcessPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "process"

  /// Callback to exit the app
  public var exitHandler: ((Int32) -> Void)?

  /// Callback to relaunch the app
  public var relaunchHandler: (() -> Void)?

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Exit the application
    commands.register("exit", args: ExitArgs.self, returning: EmptyResponse.self) { [self] args, _ in
      let code = args.code ?? 0
      if let handler = exitHandler {
        handler(code)
      } else {
        exit(code)
      }
      return EmptyResponse()
    }

    // Relaunch the application
    commands.register("relaunch", returning: EmptyResponse.self) { [self] _ in
      if let handler = relaunchHandler {
        handler()
      } else {
        // Default relaunch implementation for macOS
        #if os(macOS)
        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = Array(CommandLine.arguments.dropFirst())
        try? task.run()
        exit(0)
        #endif
      }
      return EmptyResponse()
    }

    // Get process ID
    commands.register("pid", returning: Int32.self) { _ in
      ProcessInfo.processInfo.processIdentifier
    }

    // Get current working directory
    commands.register("cwd", returning: String.self) { _ in
      FileManager.default.currentDirectoryPath
    }

    // Get all environment variables
    commands.register("envAll", returning: [String: String].self) { _ in
      ProcessInfo.processInfo.environment
    }

    // Get specific environment variable
    commands.register("env", args: EnvArgs.self, returning: String?.self) { args, _ in
      ProcessInfo.processInfo.environment[args.name]
    }

    // Get command line arguments
    commands.register("args", returning: [String].self) { _ in
      Array(CommandLine.arguments.dropFirst())
    }

    // Get executable path
    commands.register("executablePath", returning: String.self) { _ in
      Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    // Get resource path (bundle resources)
    commands.register("resourcePath", returning: String?.self) { _ in
      Bundle.main.resourcePath
    }

    // Get app data directory
    commands.register("appDataDir", returning: String?.self) { _ in
      #if os(macOS)
      let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      if let path = paths.first {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.velox.app"
        return path.appendingPathComponent(bundleId).path
      }
      #endif
      return nil
    }

    // Get app config directory
    commands.register("appConfigDir", returning: String?.self) { _ in
      #if os(macOS)
      let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      if let path = paths.first {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.velox.app"
        return path.appendingPathComponent(bundleId).path
      }
      #endif
      return nil
    }

    // Get app cache directory
    commands.register("appCacheDir", returning: String?.self) { _ in
      #if os(macOS)
      let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      if let path = paths.first {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.velox.app"
        return path.appendingPathComponent(bundleId).path
      }
      #endif
      return nil
    }

    // Get app log directory
    commands.register("appLogDir", returning: String?.self) { _ in
      #if os(macOS)
      let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
      if let path = paths.first {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.velox.app"
        return path.appendingPathComponent("Logs").appendingPathComponent(bundleId).path
      }
      #endif
      return nil
    }
  }

  // MARK: - Argument Types

  struct ExitArgs: Codable, Sendable {
    var code: Int32?
  }

  struct EnvArgs: Codable, Sendable {
    let name: String
  }

  struct EmptyResponse: Codable, Sendable {}
}
