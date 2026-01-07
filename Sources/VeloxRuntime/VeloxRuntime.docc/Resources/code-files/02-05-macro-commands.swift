import Foundation
import VeloxMacros
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Response Types

struct GreetResponse: Codable, Sendable {
    let message: String
}

struct MathResponse: Codable, Sendable {
    let result: Double
    let operation: String
}

// MARK: - Commands Container

enum Commands {
    /// Greet a user by name
    @VeloxCommand
    static func greet(name: String) -> GreetResponse {
        GreetResponse(message: "Hello, \(name)!")
    }

    /// Add two numbers
    @VeloxCommand
    static func add(a: Double, b: Double) -> MathResponse {
        MathResponse(result: a + b, operation: "addition")
    }

    /// Multiply two numbers
    @VeloxCommand
    static func multiply(a: Double, b: Double) -> MathResponse {
        MathResponse(result: a * b, operation: "multiplication")
    }

    /// Divide two numbers (can throw)
    @VeloxCommand
    static func divide(numerator: Double, denominator: Double) throws -> MathResponse {
        guard denominator != 0 else {
            throw CommandError(code: "DivisionByZero", message: "Cannot divide by zero")
        }
        return MathResponse(result: numerator / denominator, operation: "division")
    }
}
