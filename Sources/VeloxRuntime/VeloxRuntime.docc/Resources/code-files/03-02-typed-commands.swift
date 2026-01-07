import Foundation
import VeloxRuntime

// MARK: - Arguments

struct GetUserArgs: Codable, Sendable {
    let id: String
}

struct ListUsersArgs: Codable, Sendable {
    let page: Int
    let limit: Int
}

// MARK: - Commands with typed responses

let userCommands = commands {
    command("get_user", args: GetUserArgs.self, returning: UserResponse.self) { args, ctx in
        // Look up user from state or database
        let state: UserDatabase = ctx.requireState()
        guard let user = state.findUser(id: args.id) else {
            throw CommandError(code: "NotFound", message: "User not found: \(args.id)")
        }
        return UserResponse(user: user, isOnline: state.isOnline(args.id))
    }

    command("list_users", args: ListUsersArgs.self, returning: UsersListResponse.self) { args, ctx in
        let state: UserDatabase = ctx.requireState()
        let users = state.listUsers(page: args.page, limit: args.limit)
        return UsersListResponse(
            users: users,
            total: state.totalUsers,
            page: args.page
        )
    }
}
