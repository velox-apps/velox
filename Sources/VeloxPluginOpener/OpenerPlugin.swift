// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

#if os(macOS)
import AppKit
#endif

/// Built-in Opener plugin for opening files and URLs in external applications.
///
/// This plugin exposes the following commands:
/// - `plugin:opener|open_url` - Open a URL in the default browser
/// - `plugin:opener|open_path` - Open a file/folder with its default application
/// - `plugin:opener|reveal_path` - Reveal a file in Finder/Explorer
///
/// Example frontend usage:
/// ```javascript
/// // Open URL in browser
/// await invoke('plugin:opener|open_url', { url: 'https://example.com' });
///
/// // Open file with default app
/// await invoke('plugin:opener|open_path', { path: '/path/to/document.pdf' });
///
/// // Reveal in Finder
/// await invoke('plugin:opener|reveal_path', { path: '/path/to/file.txt' });
/// ```
public final class OpenerPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "opener"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    let openUrlHandler: (OpenUrlArgs) throws -> Bool = { args in
      guard let url = URL(string: args.url) else {
        throw CommandError(code: "InvalidUrl", message: "Invalid URL: \(args.url)")
      }

      #if os(macOS)
      return NSWorkspace.shared.open(url)
      #else
      return false
      #endif
    }

    // Open URL in default browser
    commands.register("openUrl", args: OpenUrlArgs.self, returning: Bool.self) { args, _ in
      try openUrlHandler(args)
    }
    commands.register("open_url", args: OpenUrlArgs.self, returning: Bool.self) { args, _ in
      try openUrlHandler(args)
    }

    // Open file/folder with default application
    let openPathHandler: (OpenPathArgs) throws -> Bool = { args in
      let url = URL(fileURLWithPath: args.path)

      #if os(macOS)
      if let app = args.with {
        // Open with specific application
        let appUrl = URL(fileURLWithPath: app)
        let config = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: config) { _, error in
          result = error == nil
          semaphore.signal()
        }
        semaphore.wait()
        return result
      } else {
        return NSWorkspace.shared.open(url)
      }
      #else
      return false
      #endif
    }
    commands.register("openPath", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
      try openPathHandler(args)
    }
    commands.register("open_path", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
      try openPathHandler(args)
    }

    // Reveal file in Finder
    let revealPathHandler: (OpenPathArgs) throws -> Bool = { args in
      let url = URL(fileURLWithPath: args.path)

      #if os(macOS)
      NSWorkspace.shared.activateFileViewerSelecting([url])
      return true
      #else
      return false
      #endif
    }
    commands.register("revealPath", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
      try revealPathHandler(args)
    }
    commands.register("reveal_path", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
      try revealPathHandler(args)
    }

    // Open file with specific application
    let openWithHandler: (OpenWithArgs) throws -> Bool = { args in
      let fileUrl = URL(fileURLWithPath: args.path)
      let appUrl = URL(fileURLWithPath: args.app)

      #if os(macOS)
      let config = NSWorkspace.OpenConfiguration()
      let semaphore = DispatchSemaphore(value: 0)
      var result = false
      NSWorkspace.shared.open([fileUrl], withApplicationAt: appUrl, configuration: config) { _, error in
        result = error == nil
        semaphore.signal()
      }
      semaphore.wait()
      return result
      #else
      return false
      #endif
    }
    commands.register("openWith", args: OpenWithArgs.self, returning: Bool.self) { args, _ in
      try openWithHandler(args)
    }
    commands.register("open_with", args: OpenWithArgs.self, returning: Bool.self) { args, _ in
      try openWithHandler(args)
    }

    // Get default application for file
    let getDefaultAppHandler: (OpenPathArgs) throws -> String? = { args in
      let url = URL(fileURLWithPath: args.path)

      #if os(macOS)
      if let appUrl = NSWorkspace.shared.urlForApplication(toOpen: url) {
        return appUrl.path
      }
      #endif
      return nil
    }
    commands.register("getDefaultApp", args: OpenPathArgs.self, returning: String?.self) { args, _ in
      try getDefaultAppHandler(args)
    }
    commands.register("get_default_app", args: OpenPathArgs.self, returning: String?.self) { args, _ in
      try getDefaultAppHandler(args)
    }
  }

  // MARK: - Argument Types

  struct OpenUrlArgs: Codable, Sendable {
    let url: String
  }

  struct OpenPathArgs: Codable, Sendable {
    let path: String
    var with: String?
  }

  struct OpenWithArgs: Codable, Sendable {
    let path: String
    let app: String
  }
}
