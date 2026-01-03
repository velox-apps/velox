// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Event Types

/// A Velox event that can be emitted from the backend to the frontend.
public struct VeloxEvent<T: Encodable>: Sendable where T: Sendable {
  /// The event name/type identifier
  public let name: String

  /// The event payload
  public let payload: T

  /// Unique event ID
  public let id: UUID

  /// Timestamp when the event was created
  public let timestamp: Date

  public init(name: String, payload: T) {
    self.name = name
    self.payload = payload
    self.id = UUID()
    self.timestamp = Date()
  }
}

/// A type-erased event for internal use
public struct AnyVeloxEvent: Sendable {
  public let name: String
  public let payloadJSON: String
  public let id: UUID
  public let timestamp: Date

  public init<T: Encodable & Sendable>(from event: VeloxEvent<T>) throws {
    self.name = event.name
    self.id = event.id
    self.timestamp = event.timestamp

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let data = try encoder.encode(event.payload)
    self.payloadJSON = String(data: data, encoding: .utf8) ?? "null"
  }

  public init(name: String, payloadJSON: String) {
    self.name = name
    self.payloadJSON = payloadJSON
    self.id = UUID()
    self.timestamp = Date()
  }
}

// MARK: - Event Target

/// Specifies which webviews should receive an event
public enum EventTarget: Sendable {
  /// Emit to all webviews in all windows
  case all

  /// Emit to a specific window by label
  case window(String)

  /// Emit to a specific webview by label
  case webview(String)

  /// Emit to webviews matching a predicate (evaluated at emit time)
  case filter(@Sendable (String) -> Bool)
}

// MARK: - Event Listener

/// Represents a registered event listener
public struct EventListenerHandle: Sendable, Hashable {
  public let id: UUID
  public let eventName: String

  public init(id: UUID = UUID(), eventName: String) {
    self.id = id
    self.eventName = eventName
  }

  public static func == (lhs: EventListenerHandle, rhs: EventListenerHandle) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// Callback type for event listeners
public typealias EventCallback = @Sendable (AnyVeloxEvent) -> Void

// MARK: - Event Emitter Protocol

/// Protocol for types that can emit events to the frontend
public protocol EventEmitter: Sendable {
  /// Emit an event to all webviews
  func emit<T: Encodable & Sendable>(_ event: String, payload: T) throws

  /// Emit an event to a specific target
  func emit<T: Encodable & Sendable>(_ event: String, payload: T, to target: EventTarget) throws

  /// Emit an event to a specific window by label
  func emitTo<T: Encodable & Sendable>(_ label: String, event: String, payload: T) throws
}

// MARK: - Event Listener Protocol

/// Protocol for types that can listen to events from the frontend
public protocol EventListener: Sendable {
  /// Listen for events with a given name
  @discardableResult
  func listen(_ event: String, handler: @escaping EventCallback) -> EventListenerHandle

  /// Listen for a single event occurrence
  @discardableResult
  func once(_ event: String, handler: @escaping EventCallback) -> EventListenerHandle

  /// Remove an event listener
  func unlisten(_ handle: EventListenerHandle)

  /// Remove all listeners for an event
  func removeAllListeners(for event: String)
}

// MARK: - JavaScript Event Bridge

/// Generates JavaScript code for the event system
public enum VeloxEventBridge {
  /// The JavaScript code to inject into webviews for event support
  public static let initScript: String = """
    (function() {
      if (window.__VELOX_EVENTS__) return;

      const listeners = new Map();
      let listenerIdCounter = 0;

      window.__VELOX_EVENTS__ = {
        // Internal: called by Swift to deliver events
        _emit: function(eventName, payload, eventId, timestamp) {
          const handlers = listeners.get(eventName) || [];
          const event = {
            name: eventName,
            payload: payload,
            id: eventId,
            timestamp: new Date(timestamp)
          };

          handlers.forEach(({ handler, once, id }) => {
            try {
              handler(event);
              if (once) {
                this.unlisten(id);
              }
            } catch (e) {
              console.error(`[Velox] Error in event handler for '${eventName}':`, e);
            }
          });
        },

        // Listen for an event
        listen: function(eventName, handler) {
          const id = ++listenerIdCounter;
          if (!listeners.has(eventName)) {
            listeners.set(eventName, []);
          }
          listeners.get(eventName).push({ handler, once: false, id });
          return id;
        },

        // Listen for a single event occurrence
        once: function(eventName, handler) {
          const id = ++listenerIdCounter;
          if (!listeners.has(eventName)) {
            listeners.set(eventName, []);
          }
          listeners.get(eventName).push({ handler, once: true, id });
          return id;
        },

        // Remove a listener by ID
        unlisten: function(listenerId) {
          for (const [eventName, handlers] of listeners) {
            const idx = handlers.findIndex(h => h.id === listenerId);
            if (idx !== -1) {
              handlers.splice(idx, 1);
              if (handlers.length === 0) {
                listeners.delete(eventName);
              }
              return true;
            }
          }
          return false;
        },

        // Remove all listeners for an event
        removeAllListeners: function(eventName) {
          if (eventName) {
            listeners.delete(eventName);
          } else {
            listeners.clear();
          }
        },

        // Emit an event to the backend
        emit: async function(eventName, payload) {
          return fetch('ipc://localhost/__velox_event__', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ event: eventName, payload: payload })
          }).then(r => r.json());
        }
      };

      // Expose convenient API
      window.Velox = window.Velox || {};
      window.Velox.event = {
        listen: (e, h) => window.__VELOX_EVENTS__.listen(e, h),
        once: (e, h) => window.__VELOX_EVENTS__.once(e, h),
        unlisten: (id) => window.__VELOX_EVENTS__.unlisten(id),
        emit: (e, p) => window.__VELOX_EVENTS__.emit(e, p)
      };
    })();
    """

  /// Generate JavaScript to emit an event
  public static func emitScript(event: AnyVeloxEvent) -> String {
    let escapedPayload = event.payloadJSON
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")

    let timestamp = Int64(event.timestamp.timeIntervalSince1970 * 1000)

    return """
      (function() {
        if (window.__VELOX_EVENTS__) {
          window.__VELOX_EVENTS__._emit(
            '\(event.name)',
            JSON.parse('\(escapedPayload)'),
            '\(event.id.uuidString)',
            \(timestamp)
          );
        }
      })();
      """
  }
}
