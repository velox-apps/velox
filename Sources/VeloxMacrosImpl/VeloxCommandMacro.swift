// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `@VeloxCommand` macro.
///
/// This macro transforms a function into a command that can be registered with Velox.
/// It generates a computed property that returns a `CommandDefinition`.
///
/// Example:
/// ```swift
/// @VeloxCommand
/// func greet(name: String) -> GreetResponse {
///     GreetResponse(message: "Hello, \(name)!")
/// }
/// ```
///
/// Expands to:
/// ```swift
/// func greet(name: String) -> GreetResponse {
///     GreetResponse(message: "Hello, \(name)!")
/// }
///
/// var greetCommand: CommandDefinition {
///     struct Args: Codable, Sendable {
///         let name: String
///     }
///     return command("greet", args: Args.self, returning: GreetResponse.self) { args, _ in
///         greet(name: args.name)
///     }
/// }
/// ```
public struct VeloxCommandMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Ensure we're attached to a function
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw VeloxCommandMacroError.notAFunction
    }

    let funcName = funcDecl.name.text

    // Get the command name from the attribute argument or default to function name
    let commandName = extractCommandName(from: node) ?? funcName

    // Check if the function is static
    let isStatic = funcDecl.modifiers.contains { modifier in
      modifier.name.tokenKind == .keyword(.static)
    }

    // Get the return type
    guard let returnClause = funcDecl.signature.returnClause else {
      throw VeloxCommandMacroError.missingReturnType
    }
    let returnType = returnClause.type.trimmedDescription

    // Check if the function throws
    let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil

    // Get the parameters
    let parameters = funcDecl.signature.parameterClause.parameters

    // Check if the function has a context parameter
    let hasContextParam = parameters.contains { param in
      let typeName = param.type.trimmedDescription
      return typeName == "CommandContext" || typeName.hasSuffix(".CommandContext")
    }

    // Filter out context parameter for Args struct
    let argsParameters = parameters.filter { param in
      let typeName = param.type.trimmedDescription
      return typeName != "CommandContext" && !typeName.hasSuffix(".CommandContext")
    }

    // Generate the command property
    if argsParameters.isEmpty {
      // No arguments - simpler form
      return [generateNoArgsCommand(
        funcName: funcName,
        commandName: commandName,
        returnType: returnType,
        hasContext: hasContextParam,
        isThrows: isThrows,
        isStatic: isStatic
      )]
    } else {
      // Has arguments - generate Args struct and command property
      return generateArgsCommand(
        funcName: funcName,
        commandName: commandName,
        returnType: returnType,
        parameters: argsParameters,
        hasContext: hasContextParam,
        isThrows: isThrows,
        isStatic: isStatic
      )
    }
  }

  private static func extractCommandName(from node: AttributeSyntax) -> String? {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
    else {
      return nil
    }
    return segment.content.text
  }

  private static func generateNoArgsCommand(
    funcName: String,
    commandName: String,
    returnType: String,
    hasContext: Bool,
    isThrows: Bool,
    isStatic: Bool
  ) -> DeclSyntax {
    let propertyName = "\(funcName)Command"
    let staticKeyword = isStatic ? "static " : ""
    let tryPrefix = isThrows ? "try " : ""
    let funcCall = hasContext ? "\(tryPrefix)\(funcName)(context: context)" : "\(tryPrefix)\(funcName)()"

    return """
      \(raw: staticKeyword)var \(raw: propertyName): CommandDefinition {
        command("\(raw: commandName)", returning: \(raw: returnType).self) { context in
          \(raw: funcCall)
        }
      }
      """
  }

  private static func generateArgsCommand(
    funcName: String,
    commandName: String,
    returnType: String,
    parameters: FunctionParameterListSyntax,
    hasContext: Bool,
    isThrows: Bool,
    isStatic: Bool
  ) -> [DeclSyntax] {
    let propertyName = "\(funcName)Command"
    let argsTypeName = "__\(funcName)Args"
    let staticKeyword = isStatic ? "static " : ""
    let tryPrefix = isThrows ? "try " : ""

    // Generate Args struct members
    var argsMembers: [String] = []
    var funcCallArgs: [String] = []

    for param in parameters {
      let paramName = (param.secondName ?? param.firstName).text
      let externalName = param.firstName.text
      let paramType = param.type.trimmedDescription

      argsMembers.append("let \(paramName): \(paramType)")

      // Handle external vs internal parameter names
      if externalName == "_" {
        funcCallArgs.append("args.\(paramName)")
      } else {
        funcCallArgs.append("\(externalName): args.\(paramName)")
      }
    }

    if hasContext {
      funcCallArgs.append("context: context")
    }

    let argsMembersStr = argsMembers.joined(separator: "; ")
    let funcCallArgsStr = funcCallArgs.joined(separator: ", ")

    // Generate the Args struct as a separate peer declaration
    let argsStruct: DeclSyntax = """
      private struct \(raw: argsTypeName): Codable, Sendable { \(raw: argsMembersStr) }
      """

    // Generate the command property
    let commandProperty: DeclSyntax = """
      \(raw: staticKeyword)var \(raw: propertyName): CommandDefinition {
        command("\(raw: commandName)", args: \(raw: argsTypeName).self, returning: \(raw: returnType).self) { args, context in
          \(raw: tryPrefix)\(raw: funcName)(\(raw: funcCallArgsStr))
        }
      }
      """

    return [argsStruct, commandProperty]
  }
}

/// Errors that can occur during `@VeloxCommand` macro expansion.
enum VeloxCommandMacroError: Error, CustomStringConvertible {
  /// The macro was applied to something other than a function.
  case notAFunction
  /// The function is missing a return type declaration.
  case missingReturnType

  var description: String {
    switch self {
    case .notAFunction:
      return "@VeloxCommand can only be applied to functions"
    case .missingReturnType:
      return "@VeloxCommand requires a return type"
    }
  }
}

/// The Swift compiler plugin that provides Velox macros.
@main
struct VeloxMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    VeloxCommandMacro.self
  ]
}
