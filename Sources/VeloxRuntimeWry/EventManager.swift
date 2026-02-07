// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - Event Manager

/// Manages event emission and listening across webviews
public final class VeloxEventManager: @unchecked Sendable {
  /// Registered webviews by label
  private var webviews: [String: WeakWebview] = [:]

  /// Registered windows by label
  private var windows: [String: WeakWindow] = [:]

  /// Mapping from internal webview IDs to labels
  private var internalIdToLabel: [String: String] = [:]

  /// Backend event listeners
  private var listeners: [String: [(EventListenerHandle, EventCallback)]] = [:]

  /// Lock for thread safety
  private let lock = NSLock()

  /// Shared instance for global events
  public static let shared = VeloxEventManager()

  public init() {}

  // MARK: - Webview Registration

  /// Register a webview for receiving events
  public func register(webview: VeloxRuntimeWry.Webview, label: String) {
    lock.lock()
    defer { lock.unlock() }
    webviews[label] = WeakWebview(webview)

    // Also register by internal identifier for IPC lookups
    let internalId = webview.identifier
    if !internalId.isEmpty {
      internalIdToLabel[internalId] = label
    }

    // Inject the event bridge script
    webview.evaluate(script: VeloxEventBridge.initScript)
  }

  /// Unregister a webview
  public func unregister(label: String) {
    lock.lock()
    defer { lock.unlock() }
    webviews.removeValue(forKey: label)
    // Clean up internal ID mapping
    internalIdToLabel = internalIdToLabel.filter { $0.value != label }
  }

  // MARK: - Window Registration

  /// Register a window for menu and window-specific operations.
  public func register(window: VeloxRuntimeWry.Window, label: String) {
    lock.lock()
    defer { lock.unlock() }
    windows[label] = WeakWindow(window)
  }

  /// Unregister a window.
  public func unregisterWindow(label: String) {
    lock.lock()
    defer { lock.unlock() }
    windows.removeValue(forKey: label)
  }

  /// Get a window by its label.
  public func window(for label: String) -> VeloxRuntimeWry.Window? {
    lock.lock()
    defer { lock.unlock() }
    return windows[label]?.window
  }

  /// Get all registered webview labels
  public var registeredLabels: [String] {
    lock.lock()
    defer { lock.unlock() }
    // Clean up deallocated webviews and stale internal ID mappings
    webviews = webviews.filter { $0.value.webview != nil }
    let validLabels = Set(webviews.keys)
    internalIdToLabel = internalIdToLabel.filter { validLabels.contains($0.value) }
    return Array(webviews.keys)
  }

  /// Resolve a webview identifier to its user-friendly label.
  ///
  /// The identifier can be either a user-provided label or an internal wry ID.
  /// Returns the label if found, or the original identifier if no mapping exists.
  ///
  /// - Parameter id: The webview identifier (internal ID or label)
  /// - Returns: The user-friendly label
  public func resolveLabel(_ id: String) -> String {
    lock.lock()
    defer { lock.unlock() }

    // If it's already a known label, return it
    if webviews[id] != nil {
      return id
    }

    // Try to map internal ID to label
    if let label = internalIdToLabel[id] {
      return label
    }

    // Return the original ID if no mapping found
    return id
  }

  // MARK: - Event Emission

  /// Emit an event to all registered webviews
  public func emit<T: Encodable & Sendable>(_ eventName: String, payload: T) throws {
    try emit(eventName, payload: payload, to: .all)
  }

  /// Emit an event to a specific target
  public func emit<T: Encodable & Sendable>(
    _ eventName: String,
    payload: T,
    to target: EventTarget
  ) throws {
    let event = VeloxEvent(name: eventName, payload: payload)
    let anyEvent = try AnyVeloxEvent(from: event)
    let script = VeloxEventBridge.emitScript(event: anyEvent)

    lock.lock()
    // Clean up deallocated webviews
    webviews = webviews.filter { $0.value.webview != nil }

    let targetWebviews: [(String, VeloxRuntimeWry.Webview)]
    switch target {
    case .all:
      targetWebviews = webviews.compactMap { label, weak in
        weak.webview.map { (label, $0) }
      }

    case .window(let label), .webview(let label):
      if let weak = webviews[label], let webview = weak.webview {
        targetWebviews = [(label, webview)]
      } else {
        targetWebviews = []
      }

    case .filter(let predicate):
      targetWebviews = webviews.compactMap { label, weak in
        guard predicate(label), let webview = weak.webview else { return nil }
        return (label, webview)
      }
    }
    lock.unlock()

    // Emit to all target webviews
    for (_, webview) in targetWebviews {
      webview.evaluate(script: script)
    }

    // Also notify backend listeners
    notifyListeners(event: anyEvent)
  }

  /// Emit an event to a specific webview by label
  public func emitTo<T: Encodable & Sendable>(
    _ label: String,
    event eventName: String,
    payload: T
  ) throws {
    try emit(eventName, payload: payload, to: .webview(label))
  }

  // MARK: - Backend Event Listening

  /// Listen for events emitted from the frontend
  @discardableResult
  public func listen(_ eventName: String, handler: @escaping EventCallback) -> EventListenerHandle {
    lock.lock()
    defer { lock.unlock() }

    let handle = EventListenerHandle(eventName: eventName)
    if listeners[eventName] == nil {
      listeners[eventName] = []
    }
    listeners[eventName]?.append((handle, handler))
    return handle
  }

  /// Listen for a single event occurrence
  @discardableResult
  public func once(_ eventName: String, handler: @escaping EventCallback) -> EventListenerHandle {
    final class HandleBox {
      var handle: EventListenerHandle?
    }

    let box = HandleBox()
    let handle = listen(eventName) { [weak self] event in
      handler(event)
      if let handle = box.handle {
        self?.unlisten(handle)
      }
    }
    box.handle = handle
    return handle
  }

  /// Remove an event listener
  public func unlisten(_ handle: EventListenerHandle) {
    lock.lock()
    defer { lock.unlock() }

    listeners[handle.eventName]?.removeAll { $0.0 == handle }
    if listeners[handle.eventName]?.isEmpty == true {
      listeners.removeValue(forKey: handle.eventName)
    }
  }

  /// Remove all listeners for an event
  public func removeAllListeners(for eventName: String) {
    lock.lock()
    defer { lock.unlock() }
    listeners.removeValue(forKey: eventName)
  }

  // MARK: - Internal

  /// Process an event from the frontend
  public func handleFrontendEvent(name: String, payloadJSON: String, from label: String) {
    let event = AnyVeloxEvent(name: name, payloadJSON: payloadJSON)
    notifyListeners(event: event)
  }

  private func notifyListeners(event: AnyVeloxEvent) {
    lock.lock()
    let handlers = listeners[event.name] ?? []
    lock.unlock()

    for (_, handler) in handlers {
      handler(event)
    }
  }
}

// MARK: - Weak Webview Wrapper

private final class WeakWebview: @unchecked Sendable {
  weak var webview: VeloxRuntimeWry.Webview?

  init(_ webview: VeloxRuntimeWry.Webview) {
    self.webview = webview
  }
}

private final class WeakWindow: @unchecked Sendable {
  weak var window: VeloxRuntimeWry.Window?

  init(_ window: VeloxRuntimeWry.Window) {
    self.window = window
  }
}

// MARK: - Webview Handle Implementation

/// Concrete implementation of WebviewHandle using VeloxEventManager
internal final class WebviewHandleImpl: WebviewHandle, @unchecked Sendable {
  public let id: String
  private weak var eventManager: VeloxEventManager?

  init(id: String, eventManager: VeloxEventManager) {
    self.id = id
    self.eventManager = eventManager
  }

  @discardableResult
  public func evaluate(script: String) -> Bool {
    guard let manager = eventManager else { return false }
    return manager.evaluateInWebview(id, script: script)
  }

  public func emit<T: Encodable & Sendable>(_ eventName: String, payload: T) throws {
    try eventManager?.emitTo(id, event: eventName, payload: payload)
  }
}

// MARK: - VeloxEventManager Webview Handle Support

public extension VeloxEventManager {
  /// Get a webview handle for a given identifier.
  ///
  /// The identifier can be either:
  /// - A user-provided label (e.g., "main")
  /// - An internal webview ID from wry (used in IPC requests)
  func getWebviewHandle(_ id: String) -> WebviewHandle? {
    lock.lock()
    defer { lock.unlock() }

    // First try direct label lookup
    if webviews[id]?.webview != nil {
      return WebviewHandleImpl(id: id, eventManager: self)
    }

    // Then try internal ID to label mapping (for IPC requests)
    if let label = internalIdToLabel[id], webviews[label]?.webview != nil {
      return WebviewHandleImpl(id: label, eventManager: self)
    }

    return nil
  }

  /// Evaluate script in a specific webview (internal use)
  /// Note: Script execution is deferred to run after the current IPC request completes,
  /// as the webview is locked during request handling.
  internal func evaluateInWebview(_ id: String, script: String) -> Bool {
    lock.lock()
    let webview = webviews[id]?.webview
    lock.unlock()

    guard let wv = webview else {
      return false
    }

    // Defer script execution - webview is locked during IPC request handling
    DispatchQueue.main.async {
      _ = wv.evaluate(script: script)
    }
    return true
  }
}

// MARK: - Protocol Conformance

extension VeloxEventManager: EventEmitter {}
extension VeloxEventManager: EventListener {}

// MARK: - IPC Handler for Frontend Events

/// Creates an IPC protocol handler for receiving events from the frontend
public func createEventIPCHandler(
  manager: VeloxEventManager = .shared
) -> VeloxRuntimeWry.CustomProtocol.Handler {
  return { request in
    guard request.url.contains("__velox_event__") else {
      return nil
    }

    // Parse the event from the request body
    guard !request.body.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
          let eventName = json["event"] as? String
    else {
      return VeloxRuntimeWry.CustomProtocol.Response(
        status: 400,
        headers: ["Content-Type": "application/json"],
        body: Data("{\"error\":\"Invalid event format\"}".utf8)
      )
    }

    // Get payload as JSON string
    let payloadJSON: String
    if let payload = json["payload"] {
      if let data = try? JSONSerialization.data(withJSONObject: payload),
         let str = String(data: data, encoding: .utf8)
      {
        payloadJSON = str
      } else {
        payloadJSON = "null"
      }
    } else {
      payloadJSON = "null"
    }

    // Notify the event manager
    manager.handleFrontendEvent(
      name: eventName,
      payloadJSON: payloadJSON,
      from: request.webviewIdentifier
    )

    return VeloxRuntimeWry.CustomProtocol.Response(
      status: 200,
      headers: ["Content-Type": "application/json"],
      body: Data("{\"success\":true}".utf8)
    )
  }
}
