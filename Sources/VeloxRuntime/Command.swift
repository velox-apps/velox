// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Command Result

/// The result of a command execution
public enum CommandResult: Sendable {
  case success(Encodable & Sendable)
  case error(CommandError)

  /// Create a success result with any encodable value
  public static func ok<T: Encodable & Sendable>(_ value: T) -> CommandResult {
    .success(value)
  }

  /// Create a success result with no return value
  public static var ok: CommandResult {
    .success(EmptyResponse())
  }

  /// Create an error result
  public static func err(_ error: CommandError) -> CommandResult {
    .error(error)
  }

  /// Create an error result from a message
  public static func err(_ message: String) -> CommandResult {
    .error(CommandError(code: "Error", message: message))
  }

  /// Create an error result with code and message
  public static func err(code: String, message: String) -> CommandResult {
    .error(CommandError(code: code, message: message))
  }
}

/// An empty response for commands that don't return a value
public struct EmptyResponse: Codable, Sendable {}

/// A command error
public struct CommandError: Error, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  public init(_ message: String) {
    self.code = "Error"
    self.message = message
  }
}

// MARK: - Command Context

/// Context passed to command handlers
public struct CommandContext: @unchecked Sendable {
  /// The command name being invoked
  public let command: String

  /// The raw request body as Data
  public let rawBody: Data

  /// Request headers
  public let headers: [String: String]

  /// The webview identifier that made the request
  public let webviewId: String

  /// The state container for accessing managed state
  public let stateContainer: StateContainer

  public init(
    command: String,
    rawBody: Data,
    headers: [String: String] = [:],
    webviewId: String = "",
    stateContainer: StateContainer = StateContainer()
  ) {
    self.command = command
    self.rawBody = rawBody
    self.headers = headers
    self.webviewId = webviewId
    self.stateContainer = stateContainer
  }

  /// Decode the request body as a specific type
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(type, from: rawBody)
  }

  /// Decode the request body as a dictionary
  public func decodeArgs() -> [String: Any] {
    guard !rawBody.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any]
    else {
      return [:]
    }
    return json
  }

  /// Get managed state of type T
  public func state<T>() -> T? {
    stateContainer.get()
  }

  /// Get managed state of type T, or crash if not registered
  public func requireState<T>() -> T {
    stateContainer.require()
  }
}

// MARK: - Command Handler Types

/// A type-erased command handler
public typealias AnyCommandHandler = @Sendable (CommandContext) -> CommandResult

/// A command handler that takes typed arguments
public typealias TypedCommandHandler<Args: Decodable> = @Sendable (Args, CommandContext) -> CommandResult

/// A simple command handler with no arguments
public typealias SimpleCommandHandler = @Sendable (CommandContext) -> CommandResult

// MARK: - Command Registry

/// Registry for command handlers
public final class CommandRegistry: @unchecked Sendable {
  private var handlers: [String: AnyCommandHandler] = [:]
  private let lock = NSLock()

  public init() {}

  /// Register a command handler
  @discardableResult
  public func register(_ name: String, handler: @escaping AnyCommandHandler) -> Self {
    lock.lock()
    defer { lock.unlock() }
    handlers[name] = handler
    return self
  }

  /// Register a typed command handler with automatic argument decoding
  @discardableResult
  public func register<Args: Decodable & Sendable>(
    _ name: String,
    args: Args.Type,
    handler: @escaping @Sendable (Args, CommandContext) -> CommandResult
  ) -> Self {
    register(name) { context in
      do {
        let args = try context.decode(Args.self)
        return handler(args, context)
      } catch {
        return .err(code: "DecodeError", message: "Failed to decode arguments: \(error.localizedDescription)")
      }
    }
  }

  /// Register a command that returns a Codable result
  @discardableResult
  public func register<Args: Decodable & Sendable, Result: Encodable & Sendable>(
    _ name: String,
    args: Args.Type,
    returning: Result.Type,
    handler: @escaping @Sendable (Args, CommandContext) throws -> Result
  ) -> Self {
    register(name) { context in
      do {
        let args = try context.decode(Args.self)
        let result = try handler(args, context)
        return .ok(result)
      } catch let error as CommandError {
        return .err(error)
      } catch {
        return .err(code: "Error", message: error.localizedDescription)
      }
    }
  }

  /// Register a simple command that just needs context
  @discardableResult
  public func register<Result: Encodable & Sendable>(
    _ name: String,
    returning: Result.Type,
    handler: @escaping @Sendable (CommandContext) throws -> Result
  ) -> Self {
    register(name) { context in
      do {
        let result = try handler(context)
        return .ok(result)
      } catch let error as CommandError {
        return .err(error)
      } catch {
        return .err(code: "Error", message: error.localizedDescription)
      }
    }
  }

  /// Invoke a command by name
  public func invoke(_ name: String, context: CommandContext) -> CommandResult {
    lock.lock()
    let handler = handlers[name]
    lock.unlock()

    guard let handler = handler else {
      return .err(code: "UnknownCommand", message: "Unknown command: \(name)")
    }

    return handler(context)
  }

  /// Check if a command is registered
  public func hasCommand(_ name: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return handlers[name] != nil
  }

  /// Get all registered command names
  public var commandNames: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(handlers.keys)
  }
}

// MARK: - Command Response Encoding

public extension CommandResult {
  /// Encode the result as JSON data
  func encodeToJSON() -> Data {
    let encoder = JSONEncoder()

    switch self {
    case .success(let value):
      // Wrap in result object
      if let data = try? encoder.encode(AnyEncodable(value)) {
        // Create {"result": <value>} wrapper
        if let valueJSON = try? JSONSerialization.jsonObject(with: data),
           let wrappedData = try? JSONSerialization.data(withJSONObject: ["result": valueJSON])
        {
          return wrappedData
        }
        return data
      }
      return Data("{\"result\":null}".utf8)

    case .error(let error):
      let errorObj: [String: Any] = [
        "error": error.code,
        "message": error.message
      ]
      return (try? JSONSerialization.data(withJSONObject: errorObj)) ?? Data("{\"error\":\"Unknown\"}".utf8)
    }
  }
}

/// Type-erased Encodable wrapper
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

// MARK: - Convenience Argument Types

/// Empty arguments for commands that don't need any
public struct NoArgs: Codable, Sendable {
  public init() {}
}

/// Single string argument - accepts "value", "theArgument", "arg", or "argument" keys
public struct StringArg: Sendable {
  public let value: String

  public init(value: String) {
    self.value = value
  }
}

extension StringArg: Decodable {
  enum CodingKeys: String, CodingKey {
    case value
    case theArgument
    case arg
    case argument
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? container.decode(String.self, forKey: .value) {
      self.value = v
    } else if let v = try? container.decode(String.self, forKey: .theArgument) {
      self.value = v
    } else if let v = try? container.decode(String.self, forKey: .arg) {
      self.value = v
    } else if let v = try? container.decode(String.self, forKey: .argument) {
      self.value = v
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: [], debugDescription: "No string argument found")
      )
    }
  }
}

/// Single integer argument - accepts "value", "number", or "n" keys
public struct IntArg: Sendable {
  public let value: Int

  public init(value: Int) {
    self.value = value
  }
}

extension IntArg: Decodable {
  enum CodingKeys: String, CodingKey {
    case value
    case number
    case n
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? container.decode(Int.self, forKey: .value) {
      self.value = v
    } else if let v = try? container.decode(Int.self, forKey: .number) {
      self.value = v
    } else if let v = try? container.decode(Int.self, forKey: .n) {
      self.value = v
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: [], debugDescription: "No integer argument found")
      )
    }
  }
}
