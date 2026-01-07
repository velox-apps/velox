import Foundation
import VeloxRuntime

// MARK: - Organize commands by domain

/// User-related commands
let userCommands = commands {
    command("user:create", args: CreateUserArgs.self, returning: User.self) { args, ctx in
        // ... implementation
    }

    command("user:get", args: GetUserArgs.self, returning: User.self) { args, ctx in
        // ... implementation
    }

    command("user:delete", args: DeleteUserArgs.self, returning: Bool.self) { args, ctx in
        // ... implementation
    }
}

/// File-related commands
let fileCommands = commands {
    command("file:read", args: ReadFileArgs.self, returning: String.self) { args, ctx in
        // ... implementation
    }

    command("file:write", args: WriteFileArgs.self, returning: Bool.self) { args, ctx in
        // ... implementation
    }

    command("file:list", args: ListFilesArgs.self, returning: [FileInfo].self) { args, ctx in
        // ... implementation
    }
}

/// Settings commands
let settingsCommands = commands {
    command("settings:get", returning: AppSettings.self) { ctx in
        // ... implementation
    }

    command("settings:update", args: UpdateSettingsArgs.self, returning: AppSettings.self) { args, ctx in
        // ... implementation
    }
}

// MARK: - Compose into a single registry

let allCommands = commands {
    userCommands
    fileCommands
    settingsCommands

    // Add additional standalone commands
    command("app:version", returning: String.self) { _ in
        "1.0.0"
    }
}

// MARK: - Use in app

func main() {
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            .registerCommands(allCommands)  // Single composed registry
        try app.run()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}
