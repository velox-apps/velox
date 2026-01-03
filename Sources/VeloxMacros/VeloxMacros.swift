// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

@_exported import VeloxRuntime

/// Marks a function as a Velox command.
///
/// This macro generates a `CommandDefinition` property that can be used to register
/// the function as a command handler. The generated property name is the function
/// name with "Command" appended.
///
/// ## Basic Usage
///
/// ```swift
/// @VeloxCommand
/// func greet(name: String) -> GreetResponse {
///     GreetResponse(message: "Hello, \(name)!")
/// }
///
/// // Use in command registration:
/// let registry = commands {
///     greetCommand  // Generated property
/// }
/// ```
///
/// ## Custom Command Name
///
/// By default, the command name matches the function name. You can override this:
///
/// ```swift
/// @VeloxCommand("say_hello")
/// func greet(name: String) -> GreetResponse {
///     GreetResponse(message: "Hello, \(name)!")
/// }
/// // Registers as "say_hello" instead of "greet"
/// ```
///
/// ## With CommandContext
///
/// To access state or other context, add a `context: CommandContext` parameter:
///
/// ```swift
/// @VeloxCommand
/// func increment(context: CommandContext) -> CounterResponse {
///     let state: AppState = context.requireState()
///     return CounterResponse(value: state.increment())
/// }
/// ```
///
/// ## Throwing Commands
///
/// Commands can throw errors:
///
/// ```swift
/// @VeloxCommand
/// func divide(numerator: Double, denominator: Double) throws -> MathResponse {
///     guard denominator != 0 else {
///         throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
///     }
///     return MathResponse(result: numerator / denominator)
/// }
/// ```
///
/// - Parameter name: Optional custom command name. Defaults to the function name.
@attached(peer, names: arbitrary)
public macro VeloxCommand(_ name: String? = nil) = #externalMacro(
  module: "VeloxMacrosImpl",
  type: "VeloxCommandMacro"
)
