// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - IPC Command Handler

/// Creates an IPC protocol handler from a CommandRegistry
public func createCommandHandler(
  registry: CommandRegistry,
  stateContainer: StateContainer = StateContainer(),
  eventManager: VeloxEventManager? = nil
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

    let result = registry.invoke(command, context: context)
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
      eventManager: eventManager
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
