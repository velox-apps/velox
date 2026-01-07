import Foundation
import VeloxRuntime

// MARK: - Streaming Data Through a Channel

let registry = commands {
    command("start_stream") { ctx -> CommandResult in
        guard let channel: Channel<StreamEvent<Int>> = ctx.channel("onData") else {
            return .err(code: "MissingChannel", message: "onData channel required")
        }

        // Start streaming in a background task
        Task.detached {
            // Stream 10 values
            for i in 1...10 {
                // Send data through the channel
                channel.send(.data(i * 10))

                // Simulate delay between messages
                try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
            }

            // Signal end of stream
            channel.send(.end)

            // Close the channel when done
            channel.close()
        }

        // Return immediately - streaming happens in background
        return .ok
    }

    // Example: Controllable stream that can be stopped
    command("start_controllable_stream") { ctx -> CommandResult in
        guard let channel: Channel<StreamEvent<Double>> = ctx.channel("onData") else {
            return .err(code: "MissingChannel", message: "onData channel required")
        }

        let state: StreamState = ctx.requireState()
        let streamId = channel.id

        // Mark stream as active
        state.start(streamId)

        Task.detached {
            var sequence = 0
            while state.isActive(streamId) {
                sequence += 1
                let value = Double.random(in: 0...100)
                channel.send(.data(value))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            channel.send(.end)
            channel.close()
        }

        return .ok
    }

    command("stop_stream") { ctx -> CommandResult in
        let state: StreamState = ctx.requireState()
        if let channelId = ctx.decodeArgs()["channelId"] as? String {
            state.stop(channelId)
        }
        return .ok
    }
}
