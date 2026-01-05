// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

#if canImport(AppKit)
import AppKit
#endif

/// Built-in Dialog plugin providing native system dialogs.
///
/// This plugin exposes the following commands:
/// - `plugin:dialog:open` - Open file/directory selection dialog
/// - `plugin:dialog:save` - Save file dialog
/// - `plugin:dialog:message` - Show a message dialog
/// - `plugin:dialog:ask` - Show a Yes/No question dialog
/// - `plugin:dialog:confirm` - Show an Ok/Cancel confirmation dialog
///
/// Example frontend usage:
/// ```javascript
/// // Open file dialog
/// const files = await invoke('plugin:dialog:open', {
///   title: 'Select File',
///   multiple: true,
///   filters: [{ name: 'Images', extensions: ['png', 'jpg'] }]
/// });
///
/// // Show message
/// await invoke('plugin:dialog:message', {
///   title: 'Info',
///   message: 'Operation complete!',
///   kind: 'info'
/// });
///
/// // Ask question
/// const answer = await invoke('plugin:dialog:ask', {
///   message: 'Do you want to continue?',
///   title: 'Confirm'
/// });
/// ```
public final class DialogPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "dialog"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    #if canImport(AppKit)
    // Use native AppKit dialogs with runModal for proper event loop handling
    commands.register("open", args: OpenArgs.self, returning: [String]?.self) { args, _ in
      Self.runModalDeferred {
        Self.showOpenPanel(args: args)
      }
    }

    commands.register("save", args: SaveArgs.self, returning: String?.self) { args, _ in
      Self.runModalDeferred {
        Self.showSavePanel(args: args)
      }
    }

    // Alert dialogs (message, ask, confirm) return a deferred response so the
    // IPC handler can return before showing a modal dialog.
    commands.register("message", args: MessageArgs.self, returning: DeferredCommandResponse.self) { args, context in
      let deferred = try context.deferResponse()
      DispatchQueue.main.async {
        let result = Self.showMessage(args: args)
        deferred.responder.resolve(result)
      }
      return deferred.pending
    }

    commands.register("ask", args: AskArgs.self, returning: DeferredCommandResponse.self) { args, context in
      let deferred = try context.deferResponse()
      DispatchQueue.main.async {
        let result = Self.showAsk(args: args)
        deferred.responder.resolve(result)
      }
      return deferred.pending
    }

    commands.register("confirm", args: ConfirmArgs.self, returning: DeferredCommandResponse.self) { args, context in
      let deferred = try context.deferResponse()
      DispatchQueue.main.async {
        let result = Self.showConfirm(args: args)
        deferred.responder.resolve(result)
      }
      return deferred.pending
    }
    #endif
  }

  /// Run a modal dialog operation deferred to escape WebKit callback conflicts
  private static func runModalDeferred<T>(_ operation: @escaping () -> T) -> T {
    var result: T?
    var completed = false

    // Use CFRunLoopPerformBlock to schedule the operation
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
      NSApp.activate(ignoringOtherApps: true)
      result = operation()
      completed = true
    }

    // Wake up the run loop to ensure our block gets processed
    CFRunLoopWakeUp(CFRunLoopGetMain())

    // Process events until the dialog completes
    while !completed {
      // Process one event at a time
      autoreleasepool {
        if let event = NSApp.nextEvent(
          matching: .any,
          until: Date(timeIntervalSinceNow: 0.05),
          inMode: .default,
          dequeue: true
        ) {
          NSApp.sendEvent(event)
        }
      }
    }

    return result!
  }

  #if canImport(AppKit)
  // MARK: - Native AppKit Dialog Implementations
  // Use begin() with completion handler to avoid runModal() issues

  private static func showOpenPanel(args: OpenArgs) -> [String]? {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = args.title ?? "Open"
    panel.canChooseFiles = !(args.directory ?? false)
    panel.canChooseDirectories = args.directory ?? false
    panel.allowsMultipleSelection = args.multiple ?? false

    if let defaultPath = args.defaultPath {
      panel.directoryURL = URL(fileURLWithPath: defaultPath)
    }

    if let filters = args.filters, !filters.isEmpty {
      var allowedTypes: [String] = []
      for filter in filters {
        allowedTypes.append(contentsOf: filter.extensions)
      }
      panel.allowedFileTypes = allowedTypes
    }

    var result: [String]?
    var done = false

    panel.begin { response in
      if response == .OK {
        result = panel.urls.map { $0.path }
      }
      done = true
    }

    // Wait for completion by running modal panel mode
    while !done {
      _ = CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.1, true)
    }

    return result
  }

  private static func showSavePanel(args: SaveArgs) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSSavePanel()
    panel.title = args.title ?? "Save"
    panel.canCreateDirectories = true

    if let defaultPath = args.defaultPath {
      panel.directoryURL = URL(fileURLWithPath: defaultPath)
    }
    if let defaultName = args.defaultName {
      panel.nameFieldStringValue = defaultName
    }

    if let filters = args.filters, !filters.isEmpty {
      var allowedTypes: [String] = []
      for filter in filters {
        allowedTypes.append(contentsOf: filter.extensions)
      }
      panel.allowedFileTypes = allowedTypes
    }

    var result: String?
    var done = false

    panel.begin { response in
      if response == .OK, let url = panel.url {
        result = url.path
      }
      done = true
    }

    // Wait for completion by running modal panel mode
    while !done {
      _ = CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.1, true)
    }

    return result
  }

  private static func alertStyle(from kind: String?) -> NSAlert.Style {
    switch kind?.lowercased() {
    case "warning": return .warning
    case "error": return .critical
    default: return .informational
    }
  }
  #endif

  // MARK: - Argument Types

  struct FilterDef: Codable, Sendable {
    let name: String
    let extensions: [String]
  }

  struct OpenArgs: Codable, Sendable {
    var title: String?
    var defaultPath: String?
    var filters: [FilterDef]?
    var directory: Bool?
    var multiple: Bool?
  }

  struct SaveArgs: Codable, Sendable {
    var title: String?
    var defaultPath: String?
    var defaultName: String?
    var filters: [FilterDef]?
  }

  struct MessageArgs: Codable, Sendable {
    var title: String?
    var message: String
    var kind: String?
    var okLabel: String?
    var cancelLabel: String?
  }

  struct AskArgs: Codable, Sendable {
    var title: String?
    var message: String
    var kind: String?
    var yesLabel: String?
    var noLabel: String?
  }

  struct ConfirmArgs: Codable, Sendable {
    var title: String?
    var message: String
    var kind: String?
    var okLabel: String?
    var cancelLabel: String?
  }

  // MARK: - Alert Dialogs
  //
  // These must run after the IPC handler returns to keep the run loop free.

  private static func showMessage(args: MessageArgs) -> Bool {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = args.title ?? ""
    alert.informativeText = args.message
    alert.alertStyle = alertStyle(from: args.kind)
    alert.addButton(withTitle: args.okLabel ?? "OK")

    _ = alert.runModal()
    return true
  }

  private static func showAsk(args: AskArgs) -> Bool {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = args.title ?? ""
    alert.informativeText = args.message
    alert.alertStyle = alertStyle(from: args.kind)
    alert.addButton(withTitle: args.yesLabel ?? "Yes")
    alert.addButton(withTitle: args.noLabel ?? "No")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
  }

  private static func showConfirm(args: ConfirmArgs) -> Bool {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = args.title ?? ""
    alert.informativeText = args.message
    alert.alertStyle = alertStyle(from: args.kind)
    alert.addButton(withTitle: args.okLabel ?? "OK")
    alert.addButton(withTitle: args.cancelLabel ?? "Cancel")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
  }

  // MARK: - FFI Helpers

  private static func parseLevel(_ kind: String?) -> VeloxRuntimeWry.Dialog.MessageLevel {
    switch kind?.lowercased() {
    case "warning": return .warning
    case "error": return .error
    default: return .info
    }
  }
}
