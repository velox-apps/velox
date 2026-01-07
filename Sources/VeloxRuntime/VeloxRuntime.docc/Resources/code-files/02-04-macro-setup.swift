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

/// Container for all commands - the @VeloxCommand macro generates
/// command definitions as static properties on this enum
enum Commands {
    // Commands will be defined here
}
