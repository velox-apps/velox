import Foundation

// MARK: - Arguments with Optional Properties

/// Search arguments with optional filters
struct SearchArgs: Codable, Sendable {
    let query: String           // Required
    let category: String?       // Optional - nil if not provided
    let limit: Int?             // Optional - will use default if nil
    let includeArchived: Bool?  // Optional - defaults to false
}

/// Create user arguments with optional fields
struct CreateUserArgs: Codable, Sendable {
    let name: String            // Required
    let email: String           // Required
    let nickname: String?       // Optional
    let bio: String?            // Optional
    let avatarUrl: String?      // Optional
}

/// Filter arguments - all optional
struct FilterArgs: Codable, Sendable {
    let minPrice: Double?
    let maxPrice: Double?
    let tags: [String]?         // Optional array
    let sortBy: String?
    let ascending: Bool?
}
