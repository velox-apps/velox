// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Async Invoke Bridge

/// JavaScript bridge for asynchronous command invocation.
///
/// This bridge enables commands to return results asynchronously after the initial
/// HTTP response. When a command returns a ``DeferredCommandResponse``, the frontend
/// waits for a matching event to resolve the Promise.
///
/// The flow is:
/// 1. Frontend calls `window.Velox.invoke('myCommand', args)`
/// 2. Backend returns `DeferredCommandResponse(id: "...")` immediately
/// 3. Backend performs async work
/// 4. Backend calls `responder.resolve(result)` or `responder.reject(...)`
/// 5. Frontend Promise resolves/rejects with the result
public enum VeloxInvokeBridge {
  /// The event name used to deliver async invoke responses.
  public static let responseEvent = "__velox_invoke_response__"

  /// JavaScript initialization script for the async invoke bridge.
  ///
  /// This script is automatically injected into webviews and provides the
  /// `window.Velox.invoke()` function that supports deferred responses.
  public static let initScript: String = """
    (function() {
      if (window.__VELOX_INVOKE__) return;

      const pending = new Map();
      let listenerReady = false;

      function registerListener() {
        if (listenerReady) return true;
        if (!window.__VELOX_EVENTS__ || typeof window.__VELOX_EVENTS__.listen !== 'function') {
          return false;
        }

        window.__VELOX_EVENTS__.listen('\(responseEvent)', (event) => {
          const payload = event && event.payload ? event.payload : {};
          const id = payload.id;
          if (!id || !pending.has(id)) return;

          const entry = pending.get(id);
          pending.delete(id);

          if (payload.ok) {
            let result = null;
            if (payload.resultJSON) {
              try {
                result = JSON.parse(payload.resultJSON);
              } catch (e) {
                result = null;
              }
            }
            entry.resolve(result);
          } else {
            const message = payload.error && payload.error.message ? payload.error.message : 'Command failed';
            const err = new Error(message);
            if (payload.error && payload.error.code) {
              err.code = payload.error.code;
            }
            entry.reject(err);
          }
        });

        listenerReady = true;
        return true;
      }

      if (!registerListener()) {
        const timer = setInterval(() => {
          if (registerListener()) {
            clearInterval(timer);
          }
        }, 50);
      }

      async function invoke(command, args = {}) {
        if (!listenerReady) {
          registerListener();
        }
        const response = await fetch(`ipc://localhost/${command}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(args)
        });

        const text = await response.text();

        if (!response.ok) {
          let message = `Command failed: ${command}`;
          try {
            const err = JSON.parse(text);
            if (err && err.message) message = err.message;
          } catch (_) {}
          throw new Error(message);
        }

        if (!text) return null;

        let data = null;
        try {
          data = JSON.parse(text);
        } catch (_) {
          return null;
        }

        const result = data ? data.result : null;
        if (result && result.__veloxPending && result.id) {
          return new Promise((resolve, reject) => {
            pending.set(result.id, { resolve, reject });
          });
        }

        return result;
      }

      window.__VELOX_INVOKE__ = { invoke };
      window.Velox = window.Velox || {};
      if (typeof window.Velox.invoke !== 'function') {
        window.Velox.invoke = invoke;
      }
    })();
    """
}

// MARK: - Deferred Command Responses

/// A response indicating that the command result will be delivered asynchronously.
///
/// Return this from a command handler when you need to perform async work
/// before providing the final result. The frontend will wait for an event
/// with matching ID to resolve the Promise.
///
/// Example:
/// ```swift
/// registry.register("longOperation") { ctx in
///   let deferred = try ctx.deferResponse()
///
///   Task {
///     let result = await performLongOperation()
///     deferred.responder.resolve(result)
///   }
///
///   return .ok(deferred.pending)
/// }
/// ```
public struct DeferredCommandResponse: Codable, Sendable {
  /// Marker field to identify this as a pending response.
  public let __veloxPending: Bool

  /// Unique identifier linking the response to its future resolution.
  public let id: String

  /// Creates a deferred response with the specified ID.
  ///
  /// - Parameter id: A unique identifier for this pending response.
  public init(id: String) {
    self.__veloxPending = true
    self.id = id
  }
}

/// Error payload for rejected async invoke responses.
///
/// Sent to the frontend when an async operation fails.
public struct InvokeErrorPayload: Codable, Sendable {
  /// A machine-readable error code.
  public let code: String

  /// A human-readable error message.
  public let message: String

  /// Creates an error payload.
  ///
  /// - Parameters:
  ///   - code: A machine-readable error code.
  ///   - message: A human-readable error description.
  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

/// Payload for async invoke response events.
///
/// Sent via the event system to resolve pending frontend Promises.
public struct InvokeResponsePayload: Codable, Sendable {
  /// The ID matching the original ``DeferredCommandResponse``.
  public let id: String

  /// Whether the operation succeeded.
  public let ok: Bool

  /// JSON-encoded result for successful operations.
  public let resultJSON: String?

  /// Error details for failed operations.
  public let error: InvokeErrorPayload?

  /// Creates a response payload.
  ///
  /// - Parameters:
  ///   - id: The deferred response ID.
  ///   - ok: Whether the operation succeeded.
  ///   - resultJSON: JSON result string (for success).
  ///   - error: Error details (for failure).
  public init(id: String, ok: Bool, resultJSON: String?, error: InvokeErrorPayload?) {
    self.id = id
    self.ok = ok
    self.resultJSON = resultJSON
    self.error = error
  }
}

/// A deferred command containing the pending response and responder.
///
/// Created by ``CommandContext/deferResponse()`` to enable async command handling.
/// Return the `pending` value from your handler and use `responder` to deliver
/// the final result.
public struct DeferredCommand: Sendable {
  /// The pending response to return from the command handler.
  public let pending: DeferredCommandResponse

  /// The responder used to deliver the final result.
  public let responder: CommandResponder
}

/// Responder for delivering deferred command results.
///
/// Use this to resolve or reject a pending command after async work completes.
/// The responder emits an event that the frontend's invoke bridge listens for.
///
/// Example:
/// ```swift
/// let deferred = try ctx.deferResponse()
///
/// Task {
///   do {
///     let result = await fetchData()
///     deferred.responder.resolve(result)
///   } catch {
///     deferred.responder.reject(code: "FetchError", message: error.localizedDescription)
///   }
/// }
///
/// return .ok(deferred.pending)
/// ```
public struct CommandResponder: @unchecked Sendable {
  private let id: String
  private let webview: WebviewHandle?

  fileprivate init(id: String, webview: WebviewHandle?) {
    self.id = id
    self.webview = webview
  }

  /// Resolves the pending command with no return value.
  ///
  /// Use this when the command succeeds but has no meaningful result.
  public func resolve() {
    emitResult(resultJSON: "null")
  }

  /// Resolves the pending command with an encodable value.
  ///
  /// - Parameter value: The result to send to the frontend.
  public func resolve<T: Encodable & Sendable>(_ value: T) {
    guard let json = encodeJSON(value) else {
      reject(code: "EncodeError", message: "Failed to encode async response")
      return
    }
    emitResult(resultJSON: json)
  }

  /// Rejects the pending command with an error.
  ///
  /// - Parameters:
  ///   - code: A machine-readable error code.
  ///   - message: A human-readable error description.
  public func reject(code: String, message: String) {
    let payload = InvokeResponsePayload(
      id: id,
      ok: false,
      resultJSON: nil,
      error: InvokeErrorPayload(code: code, message: message)
    )
    emit(payload)
  }

  private func emitResult(resultJSON: String) {
    let payload = InvokeResponsePayload(id: id, ok: true, resultJSON: resultJSON, error: nil)
    emit(payload)
  }

  private func emit(_ payload: InvokeResponsePayload) {
    guard let webview else { return }
    DispatchQueue.main.async {
      do {
        try webview.emit(VeloxInvokeBridge.responseEvent, payload: payload)
      } catch {
        // If emission fails, there's no recovery path.
      }
    }
  }

  private func encodeJSON<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(AnyEncodable(value)) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}

public extension CommandContext {
  /// Creates a deferred response for async command handling.
  ///
  /// Use this when your command needs to perform async work before returning.
  /// The returned ``DeferredCommand`` contains a pending response to return
  /// immediately, and a responder to deliver the final result later.
  ///
  /// Example:
  /// ```swift
  /// registry.register("fetchData") { ctx in
  ///   let deferred = try ctx.deferResponse()
  ///
  ///   Task {
  ///     let data = await api.fetchData()
  ///     deferred.responder.resolve(data)
  ///   }
  ///
  ///   return .ok(deferred.pending)
  /// }
  /// ```
  ///
  /// - Returns: A ``DeferredCommand`` with pending response and responder.
  /// - Throws: ``CommandError`` if the webview handle is unavailable.
  func deferResponse() throws -> DeferredCommand {
    guard let webview else {
      throw CommandError(code: "WebviewUnavailable", message: "No webview handle for async response")
    }
    let id = UUID().uuidString
    let pending = DeferredCommandResponse(id: id)
    let responder = CommandResponder(id: id, webview: webview)
    return DeferredCommand(pending: pending, responder: responder)
  }
}

// MARK: - AnyEncodable

private struct AnyEncodable: Encodable {
  private let _encode: (Encoder) throws -> Void

  init<T: Encodable>(_ value: T) {
    _encode = { encoder in
      try value.encode(to: encoder)
    }
  }

  func encode(to encoder: Encoder) throws {
    try _encode(encoder)
  }
}
