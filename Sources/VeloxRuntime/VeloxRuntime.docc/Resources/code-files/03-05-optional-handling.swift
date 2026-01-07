import Foundation
import VeloxRuntime

let searchCommands = commands {
    command("search", args: SearchArgs.self, returning: SearchResponse.self) { args, ctx in
        let state: SearchIndex = ctx.requireState()

        // Use default value if optional is nil
        let limit = args.limit ?? 20
        let includeArchived = args.includeArchived ?? false

        // Build search with optional category filter
        var results = state.search(args.query, limit: limit)

        if let category = args.category {
            results = results.filter { $0.category == category }
        }

        if !includeArchived {
            results = results.filter { !$0.isArchived }
        }

        return SearchResponse(results: results, query: args.query)
    }

    command("create_user", args: CreateUserArgs.self, returning: User.self) { args, ctx in
        let state: UserDatabase = ctx.requireState()

        // Create user with optional fields
        let user = User(
            id: UUID().uuidString,
            name: args.name,
            email: args.email,
            nickname: args.nickname,  // Passes through as nil or value
            bio: args.bio ?? "No bio provided",  // Default if nil
            avatarUrl: args.avatarUrl,
            createdAt: Date()
        )

        state.save(user)
        return user
    }
}
