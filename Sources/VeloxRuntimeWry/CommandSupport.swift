// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - IPC Command Handler

/// Creates an IPC protocol handler from a CommandRegistry
///
/// - Parameters:
///   - registry: The command registry to use for command lookup
///   - stateContainer: Container for managed application state
///   - eventManager: Optional event manager for webview handles
///   - permissionManager: Optional permission manager for access control
/// - Returns: A protocol handler function
public func createCommandHandler(
  registry: CommandRegistry,
  stateContainer: StateContainer = StateContainer(),
  eventManager: VeloxEventManager? = nil,
  permissionManager: PermissionManager? = nil
) -> VeloxRuntimeWry.CustomProtocol.Handler {
  return { request in
    guard let url = URL(string: request.url) else {
      return errorResponse(code: "InvalidURL", message: "Invalid request URL")
    }

    let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    // Create webview handle if event manager is available
    let webviewHandle = eventManager?.getWebviewHandle(request.webviewIdentifier)

    let context = CommandContext(
      command: command,
      rawBody: request.body,
      headers: request.headers,
      webviewId: request.webviewIdentifier,
      stateContainer: stateContainer,
      webview: webviewHandle
    )

    // Invoke with permission checking
    let result = registry.invoke(command, context: context, permissionManager: permissionManager)
    let response = result.encodeToResponse()

    // Merge in CORS header
    var headers = response.headers
    headers["Access-Control-Allow-Origin"] = "*"

    return VeloxRuntimeWry.CustomProtocol.Response(
      status: response.status,
      headers: headers,
      mimeType: headers["Content-Type"],
      body: response.body
    )
  }
}

/// Helper to create error response
private func errorResponse(code: String, message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  let error: [String: Any] = ["error": code, "message": message]
  let data = (try? JSONSerialization.data(withJSONObject: error)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 400,
    headers: [
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*"
    ],
    mimeType: "application/json",
    body: data
  )
}

// MARK: - CommandResult Extension

extension CommandResult {
  var isSuccess: Bool {
    switch self {
    case .success, .binary: return true
    case .error: return false
    }
  }
}

// MARK: - VeloxAppBuilder Extension

public extension VeloxAppBuilder {
  /// Register commands using a CommandRegistry
  @discardableResult
  func registerCommands(
    _ registry: CommandRegistry,
    scheme: String = "ipc"
  ) -> Self {
    let handler = createCommandHandler(
      registry: registry,
      stateContainer: stateContainer,
      eventManager: eventManager,
      permissionManager: permissionManager
    )
    return registerProtocol(scheme) { request in
      handler(request)
    }
  }

  /// Register commands using a builder closure
  @discardableResult
  func commands(
    scheme: String = "ipc",
    _ builder: (CommandRegistry) -> Void
  ) -> Self {
    let registry = CommandRegistry()
    builder(registry)
    return registerCommands(registry, scheme: scheme)
  }
}

// MARK: - Command Builder DSL

/// A result builder for defining commands in a declarative way
@resultBuilder
public struct CommandBuilder {
  public static func buildBlock(_ commands: CommandDefinition...) -> [CommandDefinition] {
    commands
  }
}

/// A command definition for use with @CommandBuilder
public struct CommandDefinition {
  let name: String
  let handler: AnyCommandHandler

  public init(_ name: String, handler: @escaping AnyCommandHandler) {
    self.name = name
    self.handler = handler
  }

  public init<Args: Decodable & Sendable>(
    _ name: String,
    args: Args.Type,
    handler: @escaping @Sendable (Args, CommandContext) -> CommandResult
  ) {
    self.name = name
    self.handler = { context in
      do {
        let args = try context.decode(Args.self)
        return handler(args, context)
      } catch {
        return .err(code: "DecodeError", message: "Failed to decode arguments: \(error.localizedDescription)")
      }
    }
  }

  public init<Args: Decodable & Sendable, Result: Encodable & Sendable>(
    _ name: String,
    args: Args.Type,
    returning: Result.Type,
    handler: @escaping @Sendable (Args, CommandContext) throws -> Result
  ) {
    self.name = name
    self.handler = { context in
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
}

/// Create a CommandRegistry from a list of command definitions
public func commands(@CommandBuilder _ builder: () -> [CommandDefinition]) -> CommandRegistry {
  let registry = CommandRegistry()
  for def in builder() {
    registry.register(def.name, handler: def.handler)
  }
  return registry
}

// MARK: - Convenience Functions for Command Definitions

/// Define a command with no arguments
public func command(
  _ name: String,
  handler: @escaping @Sendable (CommandContext) -> CommandResult
) -> CommandDefinition {
  CommandDefinition(name, handler: handler)
}

/// Define a command with typed arguments
public func command<Args: Decodable & Sendable>(
  _ name: String,
  args: Args.Type,
  handler: @escaping @Sendable (Args, CommandContext) -> CommandResult
) -> CommandDefinition {
  CommandDefinition(name, args: args, handler: handler)
}

/// Define a command with typed arguments and return type
public func command<Args: Decodable & Sendable, Result: Encodable & Sendable>(
  _ name: String,
  args: Args.Type,
  returning: Result.Type,
  handler: @escaping @Sendable (Args, CommandContext) throws -> Result
) -> CommandDefinition {
  CommandDefinition(name, args: args, returning: returning, handler: handler)
}

/// Define a command with just a return type (no args)
public func command<Result: Encodable & Sendable>(
  _ name: String,
  returning: Result.Type,
  handler: @escaping @Sendable (CommandContext) throws -> Result
) -> CommandDefinition {
  CommandDefinition(name) { context in
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

// MARK: - Binary Command Helpers

/// Define a command that returns binary data
public func binaryCommand(
  _ name: String,
  mimeType: String = "application/octet-stream",
  handler: @escaping @Sendable (CommandContext) throws -> Data
) -> CommandDefinition {
  CommandDefinition(name) { context in
    do {
      let data = try handler(context)
      return .binary(data, mimeType: mimeType)
    } catch let error as CommandError {
      return .err(error)
    } catch {
      return .err(code: "Error", message: error.localizedDescription)
    }
  }
}

/// Define a command with typed args that returns binary data
public func binaryCommand<Args: Decodable & Sendable>(
  _ name: String,
  args: Args.Type,
  mimeType: String = "application/octet-stream",
  handler: @escaping @Sendable (Args, CommandContext) throws -> Data
) -> CommandDefinition {
  CommandDefinition(name) { context in
    do {
      let args = try context.decode(Args.self)
      let data = try handler(args, context)
      return .binary(data, mimeType: mimeType)
    } catch let error as CommandError {
      return .err(error)
    } catch {
      return .err(code: "Error", message: error.localizedDescription)
    }
  }
}

/// Define a command that returns an image
public func imageCommand(
  _ name: String,
  type: ImageType = .png,
  handler: @escaping @Sendable (CommandContext) throws -> Data
) -> CommandDefinition {
  binaryCommand(name, mimeType: type.mimeType, handler: handler)
}

/// Define a command with typed args that returns an image
public func imageCommand<Args: Decodable & Sendable>(
  _ name: String,
  args: Args.Type,
  type: ImageType = .png,
  handler: @escaping @Sendable (Args, CommandContext) throws -> Data
) -> CommandDefinition {
  binaryCommand(name, args: args, mimeType: type.mimeType, handler: handler)
}

// MARK: - Channel Command Helpers

/// Define a streaming command that uses a channel for progress/data updates.
///
/// The handler receives a Channel that can be used to send updates back to the frontend.
/// The command returns immediately after starting, with updates flowing through the channel.
///
/// Frontend usage:
/// ```javascript
/// const channel = new VeloxChannel();
/// channel.onmessage = (msg) => console.log('Update:', msg);
/// await invoke('stream_data', { onProgress: channel });
/// ```
///
/// - Parameters:
///   - name: The command name
///   - channelKey: The argument key containing the channel reference (default: "onProgress")
///   - handler: The handler that receives the channel and context
public func streamingCommand<Event: Encodable & Sendable>(
  _ name: String,
  channelKey: String = "onProgress",
  handler: @escaping @Sendable (Channel<Event>, CommandContext) throws -> Void
) -> CommandDefinition {
  CommandDefinition(name) { context in
    guard let channel: Channel<Event> = context.channel(channelKey) else {
      return .err(code: "MissingChannel", message: "Missing or invalid channel parameter '\(channelKey)'")
    }

    do {
      try handler(channel, context)
      return .ok
    } catch let error as CommandError {
      return .err(error)
    } catch {
      return .err(code: "Error", message: error.localizedDescription)
    }
  }
}

/// Define a streaming command with typed arguments.
///
/// This overload allows you to decode typed arguments alongside the channel.
///
/// Example:
/// ```swift
/// struct DownloadArgs: Codable { let url: String }
///
/// streamingCommand("download", args: DownloadArgs.self) { args, channel, ctx in
///   channel.send(DownloadEvent.started(url: args.url, contentLength: nil))
///   // ... perform download ...
///   channel.send(DownloadEvent.finished(path: localPath))
/// }
/// ```
///
/// - Parameters:
///   - name: The command name
///   - args: The type to decode arguments into
///   - channelKey: The argument key containing the channel reference (default: "onProgress")
///   - handler: The handler that receives decoded args, channel, and context
/// - Returns: A command definition for registration
public func streamingCommand<Args: Decodable & Sendable, Event: Encodable & Sendable>(
  _ name: String,
  args: Args.Type,
  channelKey: String = "onProgress",
  handler: @escaping @Sendable (Args, Channel<Event>, CommandContext) throws -> Void
) -> CommandDefinition {
  CommandDefinition(name) { context in
    guard let channel: Channel<Event> = context.channel(channelKey) else {
      return .err(code: "MissingChannel", message: "Missing or invalid channel parameter '\(channelKey)'")
    }

    do {
      let args = try context.decode(Args.self)
      try handler(args, channel, context)
      return .ok
    } catch let error as CommandError {
      return .err(error)
    } catch {
      return .err(code: "Error", message: error.localizedDescription)
    }
  }
}

/// Define an async streaming command that runs in the background.
///
/// The command returns immediately while the handler runs asynchronously in a detached task.
/// Progress updates are sent through the channel, and the channel is automatically closed
/// when the handler completes (or errors).
///
/// Example:
/// ```swift
/// asyncStreamingCommand("long_task") { (channel: Channel<ProgressEvent>, ctx) in
///   for i in 0..<100 {
///     try await Task.sleep(nanoseconds: 100_000_000)
///     channel.send(ProgressEvent(current: UInt64(i), total: 100))
///   }
/// }
/// ```
///
/// - Parameters:
///   - name: The command name
///   - channelKey: The argument key containing the channel reference (default: "onProgress")
///   - handler: The async handler that receives the channel and context
/// - Returns: A command definition for registration
public func asyncStreamingCommand<Event: Encodable & Sendable>(
  _ name: String,
  channelKey: String = "onProgress",
  handler: @escaping @Sendable (Channel<Event>, CommandContext) async throws -> Void
) -> CommandDefinition {
  CommandDefinition(name) { context in
    guard let channel: Channel<Event> = context.channel(channelKey) else {
      return .err(code: "MissingChannel", message: "Missing or invalid channel parameter '\(channelKey)'")
    }

    // Run the async handler in a detached task
    Task.detached {
      do {
        try await handler(channel, context)
      } catch {
        // Send error through channel if possible
        if let errorChannel = channel as? Channel<StreamEvent<String>> {
          _ = errorChannel.send(.error(error.localizedDescription))
        }
      }
      channel.close()
    }

    // Return immediately - updates flow through channel
    return .ok
  }
}

/// Define an async streaming command with typed arguments.
///
/// Combines async execution with typed argument decoding. The command returns
/// immediately while the handler runs in the background.
///
/// Example:
/// ```swift
/// struct ProcessArgs: Codable { let files: [String] }
///
/// asyncStreamingCommand("process_files", args: ProcessArgs.self) { args, channel, ctx in
///   for (index, file) in args.files.enumerated() {
///     try await processFile(file)
///     channel.send(ProgressEvent(current: UInt64(index + 1), total: UInt64(args.files.count)))
///   }
/// }
/// ```
///
/// - Parameters:
///   - name: The command name
///   - args: The type to decode arguments into
///   - channelKey: The argument key containing the channel reference (default: "onProgress")
///   - handler: The async handler that receives decoded args, channel, and context
/// - Returns: A command definition for registration
public func asyncStreamingCommand<Args: Decodable & Sendable, Event: Encodable & Sendable>(
  _ name: String,
  args: Args.Type,
  channelKey: String = "onProgress",
  handler: @escaping @Sendable (Args, Channel<Event>, CommandContext) async throws -> Void
) -> CommandDefinition {
  CommandDefinition(name) { context in
    guard let channel: Channel<Event> = context.channel(channelKey) else {
      return .err(code: "MissingChannel", message: "Missing or invalid channel parameter '\(channelKey)'")
    }

    let decodedArgs: Args
    do {
      decodedArgs = try context.decode(Args.self)
    } catch {
      return .err(code: "DecodeError", message: "Failed to decode arguments: \(error.localizedDescription)")
    }

    // Run the async handler in a detached task
    Task.detached {
      do {
        try await handler(decodedArgs, channel, context)
      } catch {
        // Send error through channel if possible
        if let errorChannel = channel as? Channel<StreamEvent<String>> {
          _ = errorChannel.send(.error(error.localizedDescription))
        }
      }
      channel.close()
    }

    // Return immediately - updates flow through channel
    return .ok
  }
}
