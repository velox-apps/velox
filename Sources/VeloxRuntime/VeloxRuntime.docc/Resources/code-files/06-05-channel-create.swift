import Foundation
import VeloxRuntime

// MARK: - Channel Message Types

/// Events sent through the streaming channel
enum StreamEvent<T: Codable & Sendable>: Codable, Sendable {
    case data(T)
    case end

    enum CodingKeys: String, CodingKey {
        case event, data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .data(let payload):
            try container.encode("data", forKey: .event)
            try container.encode(payload, forKey: .data)
        case .end:
            try container.encode("end", forKey: .event)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let event = try container.decode(String.self, forKey: .event)
        switch event {
        case "data":
            let data = try container.decode(T.self, forKey: .data)
            self = .data(data)
        default:
            self = .end
        }
    }
}

// MARK: - Command that Creates a Channel

let registry = commands {
    // Command receives a channel from the frontend
    command("start_stream") { ctx -> CommandResult in
        // Get the channel passed from JavaScript
        guard let channel: Channel<StreamEvent<Int>> = ctx.channel("onData") else {
            return .err(code: "MissingChannel", message: "onData channel required")
        }

        // Channel is ready to use
        print("Channel created with ID: \(channel.id)")

        // Continue in next step...
        return .ok
    }
}
