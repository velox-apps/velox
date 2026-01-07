import Foundation

// MARK: - Domain Models

/// Represents a user in the system
struct User: Codable, Sendable {
    let id: String
    let name: String
    let email: String
    let createdAt: Date
}

/// Response for user queries
struct UserResponse: Codable, Sendable {
    let user: User
    let isOnline: Bool
}

/// Response for listing users
struct UsersListResponse: Codable, Sendable {
    let users: [User]
    let total: Int
    let page: Int
}

/// Response for file operations
struct FileInfo: Codable, Sendable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modifiedAt: Date?
}
