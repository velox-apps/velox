// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

#if os(macOS)
import AppKit
#endif

/// Built-in Clipboard plugin for reading and writing system clipboard.
///
/// This plugin exposes the following commands:
/// - `plugin:clipboard|writeText` - Write plain text to clipboard
/// - `plugin:clipboard|readText` - Read plain text from clipboard
/// - `plugin:clipboard|writeHtml` - Write HTML to clipboard (with text fallback)
/// - `plugin:clipboard|readHtml` - Read HTML from clipboard
/// - `plugin:clipboard|clear` - Clear the clipboard
///
/// Example frontend usage:
/// ```javascript
/// // Write text
/// await invoke('plugin:clipboard|writeText', { text: 'Hello, World!' });
///
/// // Read text
/// const text = await invoke('plugin:clipboard|readText');
///
/// // Write HTML
/// await invoke('plugin:clipboard|writeHtml', {
///   html: '<b>Bold</b>',
///   altText: 'Bold'
/// });
/// ```
public final class ClipboardPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "clipboard"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Write plain text
    commands.register("writeText", args: WriteTextArgs.self, returning: EmptyResponse.self) { args, _ in
      #if os(macOS)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(args.text, forType: .string)
      #elseif os(Linux)
      Self.linuxClipboardWrite(args.text)
      #endif
      return EmptyResponse()
    }

    // Read plain text
    commands.register("readText", returning: String?.self) { _ in
      #if os(macOS)
      return NSPasteboard.general.string(forType: .string)
      #elseif os(Linux)
      return Self.linuxClipboardRead()
      #else
      return nil
      #endif
    }

    // Write HTML with text fallback
    commands.register("writeHtml", args: WriteHtmlArgs.self, returning: EmptyResponse.self) { args, _ in
      #if os(macOS)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      if let htmlData = args.html.data(using: .utf8) {
        pasteboard.setData(htmlData, forType: .html)
      }
      if let altText = args.altText {
        pasteboard.setString(altText, forType: .string)
      }
      #elseif os(Linux)
      Self.linuxClipboardWrite(args.altText ?? args.html)
      #endif
      return EmptyResponse()
    }

    // Read HTML
    commands.register("readHtml", returning: String?.self) { _ in
      #if os(macOS)
      let pasteboard = NSPasteboard.general
      if let data = pasteboard.data(forType: .html) {
        return String(data: data, encoding: .utf8)
      }
      #elseif os(Linux)
      return Self.linuxClipboardRead()
      #endif
      return nil
    }

    // Clear clipboard
    commands.register("clear", returning: EmptyResponse.self) { _ in
      #if os(macOS)
      NSPasteboard.general.clearContents()
      #elseif os(Linux)
      Self.linuxClipboardWrite("")
      #endif
      return EmptyResponse()
    }

    // Check if clipboard has text
    commands.register("hasText", returning: Bool.self) { _ in
      #if os(macOS)
      return NSPasteboard.general.string(forType: .string) != nil
      #elseif os(Linux)
      return Self.linuxClipboardRead() != nil
      #else
      return false
      #endif
    }
  }

  // MARK: - Linux clipboard helpers

  #if os(Linux)
  private static func linuxClipboardWrite(_ text: String) {
    // Try xclip first, then xsel, then wl-copy (Wayland)
    for (tool, args) in [
      ("/usr/bin/xclip", ["-selection", "clipboard"]),
      ("/usr/bin/xsel", ["--clipboard", "--input"]),
      ("/usr/bin/wl-copy", [] as [String]),
    ] {
      if FileManager.default.fileExists(atPath: tool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardInput = pipe
        do {
          try task.run()
          pipe.fileHandleForWriting.write(Data(text.utf8))
          pipe.fileHandleForWriting.closeFile()
          task.waitUntilExit()
          return
        } catch {}
      }
    }
  }

  private static func linuxClipboardRead() -> String? {
    for (tool, args) in [
      ("/usr/bin/xclip", ["-selection", "clipboard", "-o"]),
      ("/usr/bin/xsel", ["--clipboard", "--output"]),
      ("/usr/bin/wl-paste", [] as [String]),
    ] {
      if FileManager.default.fileExists(atPath: tool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
          try task.run()
          task.waitUntilExit()
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          return String(data: data, encoding: .utf8)
        } catch {}
      }
    }
    return nil
  }
  #endif

  // MARK: - Argument Types

  struct WriteTextArgs: Codable, Sendable {
    let text: String
  }

  struct WriteHtmlArgs: Codable, Sendable {
    let html: String
    var altText: String?
  }

  struct EmptyResponse: Codable, Sendable {}
}
