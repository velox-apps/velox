// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

/// Plugin that persists and restores window geometry (position + size) across app launches.
///
/// Geometry is saved to `~/Library/Application Support/<identifier>/window-state.json`
/// (macOS) using the app identifier from the Velox config.
///
/// The plugin listens for `windowCreated`, `windowResized`, and `windowMoved` events.
/// On `windowCreated`, it restores any previously saved geometry. On resize/move,
/// it debounce-saves the new geometry after 500ms.
///
/// Example usage:
/// ```swift
/// VeloxAppBuilder(config: config)
///   .plugins {
///     WindowStatePlugin()
///   }
///   .run()
/// ```
public final class WindowStatePlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "windowstate"

  private let lock = NSLock()
  private var eventManager: VeloxEventManager?
  private var saveURL: URL?
  private var geometries: [String: WindowGeometry] = [:]
  private var saveWorkItem: DispatchWorkItem?
  private let saveQueue = DispatchQueue(label: "velox.plugin.windowstate.save")

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    self.eventManager = context.eventEmitter as? VeloxEventManager

    let identifier = context.config.identifier
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let appDir = appSupport.appendingPathComponent(identifier)
    try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    self.saveURL = appDir.appendingPathComponent("window-state.json")

    if let url = saveURL,
       let data = try? Data(contentsOf: url),
       let saved = try? JSONDecoder().decode([String: WindowGeometry].self, from: data) {
      self.geometries = saved
    }
  }

  public func onEvent(_ event: String) {
    guard let data = event.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else { return }

    switch type {
    case "windowCreated":
      guard let label = json["label"] as? String else { return }
      restoreGeometry(label: label)

    case "windowResized", "windowMoved":
      guard let windowId = json["windowId"] as? String else { return }
      let label = eventManager?.resolveLabel(windowId) ?? windowId
      recordGeometry(label: label)

    default:
      break
    }
  }

  // MARK: - Geometry Persistence

  private struct WindowGeometry: Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
  }

  private func restoreGeometry(label: String) {
    lock.lock()
    let geo = geometries[label]
    lock.unlock()

    guard let geo else { return }
    guard let window = eventManager?.window(for: label) else { return }

    window.setPosition(x: geo.x, y: geo.y)
    window.setSize(width: geo.width, height: geo.height)
  }

  /// Read the current full geometry from the window and save it.
  private func recordGeometry(label: String) {
    guard let window = eventManager?.window(for: label) else { return }
    guard let pos = window.outerPosition(), let size = window.outerSize() else { return }

    lock.lock()
    geometries[label] = WindowGeometry(x: pos.x, y: pos.y, width: size.width, height: size.height)
    lock.unlock()

    scheduleSave()
  }

  private func scheduleSave() {
    lock.lock()
    saveWorkItem?.cancel()
    let geos = geometries
    let url = saveURL
    let workItem = DispatchWorkItem {
      Self.performSave(geometries: geos, to: url)
    }
    saveWorkItem = workItem
    lock.unlock()

    saveQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
  }

  private static func performSave(geometries: [String: WindowGeometry], to url: URL?) {
    guard let url else { return }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      let data = try encoder.encode(geometries)
      try data.write(to: url, options: [.atomic])
    } catch {
      // Silent failure — persistence is best-effort
    }
  }
}
