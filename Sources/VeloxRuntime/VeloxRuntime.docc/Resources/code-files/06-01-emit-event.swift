import Foundation
import VeloxRuntime

// MARK: - Event Payload Types

struct StatusPayload: Codable, Sendable {
    let status: String
    let timestamp: Date
}

struct DataPayload: Codable, Sendable {
    let items: [String]
    let count: Int
}

// MARK: - Commands that Emit Events

let registry = commands {
    // Emit an event from a command
    command("start_task", returning: String.self) { ctx in
        // Emit an event to notify the frontend
        try ctx.emit("task-started", payload: StatusPayload(
            status: "running",
            timestamp: Date()
        ))

        return "Task started"
    }

    // Emit multiple events during processing
    command("process_items", returning: Int.self) { ctx in
        let items = ["Item 1", "Item 2", "Item 3"]

        for item in items {
            // Emit progress event
            try ctx.emit("item-processed", payload: ["item": item])
        }

        // Emit completion event
        try ctx.emit("processing-complete", payload: DataPayload(
            items: items,
            count: items.count
        ))

        return items.count
    }
}
