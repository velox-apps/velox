// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Async Invoke Bridge

public enum VeloxInvokeBridge {
  public static let responseEvent = "__velox_invoke_response__"

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

public struct DeferredCommandResponse: Codable, Sendable {
  public let __veloxPending: Bool
  public let id: String

  public init(id: String) {
    self.__veloxPending = true
    self.id = id
  }
}

public struct InvokeErrorPayload: Codable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct InvokeResponsePayload: Codable, Sendable {
  public let id: String
  public let ok: Bool
  public let resultJSON: String?
  public let error: InvokeErrorPayload?

  public init(id: String, ok: Bool, resultJSON: String?, error: InvokeErrorPayload?) {
    self.id = id
    self.ok = ok
    self.resultJSON = resultJSON
    self.error = error
  }
}

public struct DeferredCommand: Sendable {
  public let pending: DeferredCommandResponse
  public let responder: CommandResponder
}

public struct CommandResponder: @unchecked Sendable {
  private let id: String
  private let webview: WebviewHandle?

  fileprivate init(id: String, webview: WebviewHandle?) {
    self.id = id
    self.webview = webview
  }

  public func resolve() {
    emitResult(resultJSON: "null")
  }

  public func resolve<T: Encodable & Sendable>(_ value: T) {
    guard let json = encodeJSON(value) else {
      reject(code: "EncodeError", message: "Failed to encode async response")
      return
    }
    emitResult(resultJSON: json)
  }

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
