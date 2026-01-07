import Foundation
import VeloxRuntime

// MARK: - Progress Event Payload

struct ProgressPayload: Codable, Sendable {
    let current: Int
    let total: Int
    let message: String
    let percent: Double
}

// MARK: - Long-running Command with Progress

let registry = commands {
    command("process_files", returning: String.self) { ctx in
        let files = ["file1.txt", "file2.txt", "file3.txt", "file4.txt", "file5.txt"]
        let total = files.count

        // Emit start event
        try ctx.emit("progress", payload: ProgressPayload(
            current: 0,
            total: total,
            message: "Starting...",
            percent: 0
        ))

        for (index, file) in files.enumerated() {
            // Simulate processing time
            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            let current = index + 1
            let percent = Double(current) / Double(total) * 100

            // Emit progress update
            try ctx.emit("progress", payload: ProgressPayload(
                current: current,
                total: total,
                message: "Processing \(file)...",
                percent: percent
            ))
        }

        // Emit completion
        try ctx.emit("progress", payload: ProgressPayload(
            current: total,
            total: total,
            message: "Complete!",
            percent: 100
        ))

        return "Processed \(total) files"
    }
}
