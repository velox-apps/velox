// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Command Result

/// The result of a command execution.
///
/// Commands return one of three result types:
/// - `.success`: A JSON-encodable value to return to the frontend
/// - `.binary`: Raw binary data with a MIME type (images, files, etc.)
/// - `.error`: An error with a code and message
///
/// Example:
/// ```swift
/// registry.register("greet") { ctx in
///   let name = ctx.decodeArgs()["name"] as? String ?? "World"
///   return .ok(["message": "Hello, \(name)!"])
/// }
///
/// registry.register("getImage") { ctx in
///   let imageData = loadPNGImage()
///   return .image(imageData, type: .png)
/// }
/// ```
public enum CommandResult: Sendable {
  /// A successful result with an encodable value.
  case success(Encodable & Sendable)

  /// A binary result with raw data and MIME type.
  case binary(Data, mimeType: String)

  /// An error result with details about what went wrong.
  case error(CommandError)

  /// Create a success result with any encodable value
  public static func ok<T: Encodable & Sendable>(_ value: T) -> CommandResult {
    .success(value)
  }

  /// Create a success result with no return value
  public static var ok: CommandResult {
    .success(EmptyResponse())
  }

  /// Create a binary result with raw data and default mime type
  public static func binaryData(_ data: Data) -> CommandResult {
    .binary(data, mimeType: "application/octet-stream")
  }

  /// Create a binary result for an image
  public static func image(_ data: Data, type: ImageType) -> CommandResult {
    .binary(data, mimeType: type.mimeType)
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

/// Image formats for binary command responses.
///
/// Use these types with ``CommandResult/image(_:type:)`` to return images
/// with the correct MIME type.
public enum ImageType: Sendable {
  /// PNG format (image/png)
  case png
  /// JPEG format (image/jpeg)
  case jpeg
  /// GIF format (image/gif)
  case gif
  /// WebP format (image/webp)
  case webp
  /// SVG format (image/svg+xml)
  case svg

  /// The MIME type string for this image format.
  public var mimeType: String {
    switch self {
    case .png: return "image/png"
    case .jpeg: return "image/jpeg"
    case .gif: return "image/gif"
    case .webp: return "image/webp"
    case .svg: return "image/svg+xml"
    }
  }
}

/// An empty response for commands that don't return a value.
///
/// Used internally by ``CommandResult/ok`` when a command succeeds
/// but has no meaningful return value.
public struct EmptyResponse: Codable, Sendable {}

/// An error returned from a command handler.
///
/// Command errors include a machine-readable code and a human-readable message.
/// The code can be used by frontend code to handle specific error types.
///
/// Example:
/// ```swift
/// registry.register("readFile") { ctx in
///   guard let path = ctx.decodeArgs()["path"] as? String else {
///     return .err(CommandError(code: "InvalidArgs", message: "Missing path"))
///   }
///   // ...
/// }
/// ```
public struct CommandError: Error, Sendable {
  /// A machine-readable error code (e.g., "NotFound", "PermissionDenied").
  public let code: String

  /// A human-readable description of the error.
  public let message: String

  /// Creates a command error with a code and message.
  ///
  /// - Parameters:
  ///   - code: A machine-readable error code.
  ///   - message: A human-readable error description.
  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  /// Creates a command error with a message and default "Error" code.
  ///
  /// - Parameter message: A human-readable error description.
  public init(_ message: String) {
    self.code = "Error"
    self.message = message
  }
}

// MARK: - Webview Handle

/// Handle for interacting with a webview from command handlers
public protocol WebviewHandle: Sendable {
  /// The webview identifier
  var id: String { get }

  /// Execute JavaScript in the webview
  /// - Parameter script: The JavaScript code to execute
  /// - Returns: true if the script was sent successfully
  @discardableResult
  func evaluate(script: String) -> Bool

  /// Emit an event to this webview
  /// - Parameters:
  ///   - eventName: The name of the event
  ///   - payload: The event payload (must be Encodable)
  func emit<T: Encodable & Sendable>(_ eventName: String, payload: T) throws
}

// MARK: - Command Context

/// Context passed to command handlers providing request details and utilities.
///
/// The command context contains everything a handler needs:
/// - Request data (command name, raw body, headers)
/// - Webview information (ID and handle for JavaScript evaluation)
/// - State access (managed application state)
///
/// Example:
/// ```swift
/// registry.register("getUserData") { ctx in
///   // Access request arguments
///   let userId = ctx.decodeArgs()["userId"] as? String
///
///   // Access managed state
///   let db: DatabaseService = ctx.requireState()
///
///   // Access webview for direct JavaScript evaluation
///   ctx.webview?.evaluate(script: "console.log('Loading...')")
///
///   // Return result
///   return .ok(db.getUser(userId))
/// }
/// ```
public struct CommandContext: @unchecked Sendable {
  /// The name of the command being invoked.
  public let command: String

  /// The raw request body as JSON data.
  public let rawBody: Data

  /// HTTP-style request headers from the IPC call.
  public let headers: [String: String]

  /// The identifier of the webview that made this request.
  public let webviewId: String

  /// The state container for accessing managed application state.
  public let stateContainer: StateContainer

  /// Handle to the requesting webview for JavaScript evaluation and events.
  ///
  /// May be `nil` if the webview is no longer available.
  public let webview: WebviewHandle?

  /// Creates a command context with the specified values.
  ///
  /// - Parameters:
  ///   - command: The command name.
  ///   - rawBody: The raw JSON request body.
  ///   - headers: Request headers.
  ///   - webviewId: The requesting webview's identifier.
  ///   - stateContainer: The application state container.
  ///   - webview: Handle to the requesting webview.
  public init(
    command: String,
    rawBody: Data,
    headers: [String: String] = [:],
    webviewId: String = "",
    stateContainer: StateContainer = StateContainer(),
    webview: WebviewHandle? = nil
  ) {
    self.command = command
    self.rawBody = rawBody
    self.headers = headers
    self.webviewId = webviewId
    self.stateContainer = stateContainer
    self.webview = webview
  }

  /// Decodes the request body as a specific `Decodable` type.
  ///
  /// Use this for type-safe argument parsing:
  /// ```swift
  /// struct GreetArgs: Decodable {
  ///   let name: String
  /// }
  /// let args = try ctx.decode(GreetArgs.self)
  /// ```
  ///
  /// - Parameter type: The type to decode the request body as.
  /// - Returns: The decoded value.
  /// - Throws: `DecodingError` if decoding fails.
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(type, from: rawBody)
  }

  /// Decodes the request body as a dictionary for dynamic argument access.
  ///
  /// Use this when you don't have a specific struct for the arguments:
  /// ```swift
  /// let args = ctx.decodeArgs()
  /// let name = args["name"] as? String ?? "World"
  /// ```
  ///
  /// - Returns: A dictionary of argument values, or empty dictionary if decoding fails.
  public func decodeArgs() -> [String: Any] {
    guard !rawBody.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any]
    else {
      return [:]
    }
    return json
  }

  /// Retrieves managed state of the specified type.
  ///
  /// - Returns: The state value if registered, or `nil` if not found.
  public func state<T>() -> T? {
    stateContainer.get()
  }

  /// Retrieves managed state of the specified type, crashing if not registered.
  ///
  /// Use this when you're certain the state has been registered during setup.
  ///
  /// - Returns: The state value.
  /// - Precondition: State of type `T` must be registered.
  public func requireState<T>() -> T {
    stateContainer.require()
  }
}

// MARK: - Command Handler Types

/// A type-erased command handler that receives context and returns a result.
///
/// This is the fundamental handler type used internally by the command registry.
/// Prefer using typed registration methods that provide automatic argument decoding.
public typealias AnyCommandHandler = @Sendable (CommandContext) -> CommandResult

/// A command handler that receives decoded arguments along with the context.
///
/// Use this signature with `register(_:args:handler:)` for type-safe argument handling.
public typealias TypedCommandHandler<Args: Decodable> = @Sendable (Args, CommandContext) -> CommandResult

/// A command handler that only needs the context (no arguments).
///
/// Use this for commands that don't require any input parameters.
public typealias SimpleCommandHandler = @Sendable (CommandContext) -> CommandResult

// MARK: - Command Registry

/// A thread-safe registry for command handlers.
///
/// The command registry stores and invokes command handlers by name.
/// Commands can be registered with various signatures for flexibility.
///
/// Example:
/// ```swift
/// let registry = CommandRegistry()
///
/// // Simple handler
/// registry.register("ping") { _ in .ok("pong") }
///
/// // Typed arguments
/// struct GreetArgs: Codable { let name: String }
/// registry.register("greet", args: GreetArgs.self) { args, _ in
///   .ok("Hello, \(args.name)!")
/// }
///
/// // Typed arguments and return value
/// registry.register("add", args: MathArgs.self, returning: Int.self) { args, _ in
///   args.a + args.b
/// }
/// ```
public final class CommandRegistry: @unchecked Sendable {
  private var handlers: [String: AnyCommandHandler] = [:]
  private let lock = NSLock()

  /// Creates an empty command registry.
  public init() {}

  /// Registers a command handler with a given name.
  ///
  /// - Parameters:
  ///   - name: The command name to register.
  ///   - handler: The handler closure to invoke when the command is called.
  /// - Returns: Self for method chaining.
  @discardableResult
  public func register(_ name: String, handler: @escaping AnyCommandHandler) -> Self {
    lock.lock()
    defer { lock.unlock() }
    handlers[name] = handler
    return self
  }

  /// Registers a typed command handler with automatic argument decoding.
  ///
  /// The arguments are automatically decoded from JSON before the handler is called.
  /// If decoding fails, an error response is returned.
  ///
  /// - Parameters:
  ///   - name: The command name to register.
  ///   - args: The type to decode arguments as.
  ///   - handler: The handler receiving decoded arguments and context.
  /// - Returns: Self for method chaining.
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

  /// Registers a command with typed arguments and return value.
  ///
  /// This is the most ergonomic registration method. Arguments are decoded,
  /// the handler can throw errors, and the result is automatically encoded.
  ///
  /// - Parameters:
  ///   - name: The command name to register.
  ///   - args: The type to decode arguments as.
  ///   - returning: The return type (for documentation, not used at runtime).
  ///   - handler: The handler that processes arguments and returns a result.
  /// - Returns: Self for method chaining.
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

  /// Registers a command that takes no arguments but returns a typed result.
  ///
  /// Use this for commands that don't need input but produce output.
  ///
  /// - Parameters:
  ///   - name: The command name to register.
  ///   - returning: The return type (for documentation, not used at runtime).
  ///   - handler: The handler that processes context and returns a result.
  /// - Returns: Self for method chaining.
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

  /// Invoke a command by name with optional permission checking
  ///
  /// - Parameters:
  ///   - name: The command name to invoke
  ///   - context: The command context containing request details
  ///   - permissionManager: Optional permission manager for access control
  /// - Returns: The command result
  public func invoke(
    _ name: String,
    context: CommandContext,
    permissionManager: PermissionManager? = nil
  ) -> CommandResult {
    // Permission check (if manager provided)
    if let manager = permissionManager {
      // Extract scope values from the request body
      let scopeValues = extractScopeValues(from: context)

      let result = manager.checkPermission(
        command: name,
        webviewId: context.webviewId,
        scopeValues: scopeValues
      )

      if case .failure(let error) = result {
        return .err(code: "PermissionDenied", message: error.localizedDescription)
      }
    }

    lock.lock()
    let handler = handlers[name]
    lock.unlock()

    guard let handler = handler else {
      return .err(code: "UnknownCommand", message: "Unknown command: \(name)")
    }

    return handler(context)
  }

  /// Extract scope values from command context for permission checking
  private func extractScopeValues(from context: CommandContext) -> [String: String] {
    var values: [String: String] = [:]

    // Try to parse JSON from request body
    guard let json = try? JSONSerialization.jsonObject(with: context.rawBody) as? [String: Any]
    else {
      return values
    }

    // Common scope parameters
    if let path = json["path"] as? String {
      values["path"] = path
    }
    if let url = json["url"] as? String {
      values["url"] = url
    }
    if let file = json["file"] as? String {
      values["path"] = file
    }
    if let dir = json["dir"] as? String {
      values["path"] = dir
    }

    return values
  }

  /// Checks if a command is registered.
  ///
  /// - Parameter name: The command name to check.
  /// - Returns: `true` if the command is registered.
  public func hasCommand(_ name: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return handlers[name] != nil
  }

  /// All registered command names.
  public var commandNames: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(handlers.keys)
  }
}

// MARK: - Command Response

/// An HTTP-style response from a command.
///
/// Contains a status code, headers, and body data. Used internally
/// to format responses for the IPC layer.
public struct CommandResponse: Sendable {
  /// The HTTP status code (200 for success, 400 for errors).
  public let status: Int

  /// Response headers, typically including Content-Type.
  public let headers: [String: String]

  /// The response body data.
  public let body: Data

  /// Creates a command response.
  ///
  /// - Parameters:
  ///   - status: HTTP status code.
  ///   - headers: Response headers.
  ///   - body: Response body data.
  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }
}

// MARK: - Command Response Encoding

public extension CommandResult {
  /// Encode the result as a full response with appropriate content type
  func encodeToResponse() -> CommandResponse {
    switch self {
    case .success:
      return CommandResponse(
        status: 200,
        headers: ["Content-Type": "application/json"],
        body: encodeToJSON()
      )
    case .binary(let data, let mimeType):
      return CommandResponse(
        status: 200,
        headers: ["Content-Type": mimeType],
        body: data
      )
    case .error(let error):
      return CommandResponse(
        status: 400,
        headers: ["Content-Type": "application/json"],
        body: encodeErrorToJSON(error)
      )
    }
  }

  /// Encode the result as JSON data (for success responses)
  func encodeToJSON() -> Data {
    let encoder = JSONEncoder()

    switch self {
    case .success(let value):
      // Wrap in result object
      if let data = try? encoder.encode(AnyEncodable(value)) {
        // Create {"result": <value>} wrapper
        // Use .fragmentsAllowed to parse primitives like strings, numbers, booleans, null
        if let valueJSON = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
           let wrappedData = try? JSONSerialization.data(withJSONObject: ["result": valueJSON])
        {
          return wrappedData
        }
        return data
      }
      return Data("{\"result\":null}".utf8)

    case .binary:
      // Binary responses shouldn't use JSON encoding
      return Data("{\"error\":\"Binary response cannot be encoded as JSON\"}".utf8)

    case .error(let error):
      return encodeErrorToJSON(error)
    }
  }

  /// Encode an error as JSON data
  private func encodeErrorToJSON(_ error: CommandError) -> Data {
    let errorObj: [String: Any] = [
      "error": error.code,
      "message": error.message
    ]
    return (try? JSONSerialization.data(withJSONObject: errorObj)) ?? Data("{\"error\":\"Unknown\"}".utf8)
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

/// Empty arguments for commands that don't need any input.
///
/// Use this as the argument type for commands that take no parameters:
/// ```swift
/// registry.register("getVersion", args: NoArgs.self) { _, _ in
///   .ok(["version": "1.0.0"])
/// }
/// ```
public struct NoArgs: Codable, Sendable {
  /// Creates an empty arguments instance.
  public init() {}
}

/// A single string argument with flexible key matching.
///
/// Accepts JSON with any of these keys: `value`, `theArgument`, `arg`, `argument`.
///
/// Example frontend calls:
/// ```javascript
/// invoke('myCommand', { value: 'hello' });
/// invoke('myCommand', { arg: 'hello' });
/// ```
public struct StringArg: Sendable {
  /// The string value from the request.
  public let value: String

  /// Creates a string argument with the specified value.
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

/// A single integer argument with flexible key matching.
///
/// Accepts JSON with any of these keys: `value`, `number`, `n`.
///
/// Example frontend calls:
/// ```javascript
/// invoke('myCommand', { value: 42 });
/// invoke('myCommand', { n: 42 });
/// ```
public struct IntArg: Sendable {
  /// The integer value from the request.
  public let value: Int

  /// Creates an integer argument with the specified value.
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
