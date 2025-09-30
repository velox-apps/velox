#if os(macOS)
import AppKit
import VeloxRuntimeWryFFI

enum AppKitHost {
  private static let lock = NSLock()
  private static var prepared = false
  private static var launched = false

  static func prepareIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    guard !prepared else { return }

    let prepare: () -> Void = {
      _ = NSApplication.shared
      prepared = true
    }

    if Thread.isMainThread {
      prepare()
    } else {
      DispatchQueue.main.sync(execute: prepare)
    }
  }

  static func finishLaunchingIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    guard !launched else { return }

    let launch: () -> Void = {
      let app = NSApplication.shared
      if app.activationPolicy() != .accessory {
        app.setActivationPolicy(.accessory)
      }
      if !app.isRunning {
        app.finishLaunching()
      }
      velox_app_state_force_launched()
      launched = true
    }

    if Thread.isMainThread {
      launch()
    } else {
      DispatchQueue.main.sync(execute: launch)
    }
  }
}
#endif
