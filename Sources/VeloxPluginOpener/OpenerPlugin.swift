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
/// - `plugin:opener:openUrl` - Open a URL in the default browser
/// - `plugin:opener:openPath` - Open a file/folder with its default application
/// - `plugin:opener:revealPath` - Reveal a file in Finder/Explorer
///
/// Example frontend usage:
/// ```javascript
/// // Open URL in browser
/// await invoke('plugin:opener:openUrl', { url: 'https://example.com' });
///
/// // Open file with default app
/// await invoke('plugin:opener:openPath', { path: '/path/to/document.pdf' });
///
/// // Reveal in Finder
/// await invoke('plugin:opener:revealPath', { path: '/path/to/file.txt' });
/// ```
public final class OpenerPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "opener"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Open URL in default browser
    commands.register("openUrl", args: OpenUrlArgs.self, returning: Bool.self) { args, _ in
      guard let url = URL(string: args.url) else {
        throw CommandError(code: "InvalidUrl", message: "Invalid URL: \(args.url)")
      }

      #if os(macOS)
      return NSWorkspace.shared.open(url)
      #else
      return false
      #endif
    }

    // Open file/folder with default application
    commands.register("openPath", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
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

    // Reveal file in Finder
    commands.register("revealPath", args: OpenPathArgs.self, returning: Bool.self) { args, _ in
      let url = URL(fileURLWithPath: args.path)

      #if os(macOS)
      NSWorkspace.shared.activateFileViewerSelecting([url])
      return true
      #else
      return false
      #endif
    }

    // Open file with specific application
    commands.register("openWith", args: OpenWithArgs.self, returning: Bool.self) { args, _ in
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

    // Get default application for file
    commands.register("getDefaultApp", args: OpenPathArgs.self, returning: String?.self) { args, _ in
      let url = URL(fileURLWithPath: args.path)

      #if os(macOS)
      if let appUrl = NSWorkspace.shared.urlForApplication(toOpen: url) {
        return appUrl.path
      }
      #endif
      return nil
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
