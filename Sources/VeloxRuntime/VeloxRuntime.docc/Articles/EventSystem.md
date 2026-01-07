# Event System

Push updates from Swift to your frontend in real-time.

## Overview

While commands let the frontend request data from Swift, events let Swift push data to the frontend. Use events for:

- Real-time notifications
- Progress updates
- State change broadcasts
- Server-sent data

## Emitting Events

### From Commands

Use the command context to emit events:

```swift
@VeloxCommand
static func startDownload(url: String, context: CommandContext) -> DownloadStarted {
    // Start async download
    Task {
        for progress in 0...100 {
            try await Task.sleep(nanoseconds: 100_000_000)
            context.emit("download:progress", payload: ProgressEvent(percent: progress))
        }
        context.emit("download:complete", payload: DownloadComplete(url: url))
    }

    return DownloadStarted(id: UUID().uuidString)
}

struct ProgressEvent: Codable, Sendable {
    let percent: Int
}

struct DownloadComplete: Codable, Sendable {
    let url: String
}
```

### Targeted Events

Send events to specific windows or webviews:

```swift
// To all windows/webviews
context.emit("notification", payload: message)

// To a specific window
context.emit("notification", payload: message, target: .window("main"))

// To a specific webview
context.emit("notification", payload: message, target: .webview("settings"))
```

## Listening in JavaScript

Use the event listener API:

```javascript
// Listen for events
const unlisten = await window.Velox.listen('download:progress', (event) => {
    console.log('Progress:', event.payload.percent);
    updateProgressBar(event.payload.percent);
});

// Listen once
await window.Velox.once('download:complete', (event) => {
    console.log('Download complete!');
    showNotification('Download finished');
});

// Stop listening
unlisten();
```

## Channels for Streaming

For large data streams, use ``Channel`` for better performance:

```swift
command("stream_data", returning: ChannelResponse.self) { context in
    let channel = context.createChannel(StreamEvent<DataChunk>.self)

    Task {
        for chunk in dataSource {
            channel.send(StreamEvent(data: chunk))
        }
        channel.close()
    }

    return channel.response
}

struct DataChunk: Codable, Sendable {
    let index: Int
    let data: Data
}
```

In JavaScript:

```javascript
const channel = await window.Velox.invoke('stream_data');

channel.onMessage((event) => {
    processChunk(event.data);
});

channel.onClose(() => {
    console.log('Stream complete');
});
```

## Event Patterns

### Progress Updates

```swift
func processFile(path: String, context: CommandContext) async throws -> ProcessResult {
    let totalSteps = 100

    for step in 1...totalSteps {
        // Do work...
        try await performStep(step)

        // Report progress
        context.emit("process:progress", payload: [
            "step": step,
            "total": totalSteps,
            "percent": (step * 100) / totalSteps
        ])
    }

    context.emit("process:complete", payload: ["path": path])
    return ProcessResult(success: true)
}
```

```javascript
window.Velox.listen('process:progress', (e) => {
    progressBar.value = e.payload.percent;
    statusText.textContent = `Step ${e.payload.step} of ${e.payload.total}`;
});

window.Velox.once('process:complete', () => {
    showSuccess('Processing complete!');
});
```

### State Broadcasting

Notify all frontends when state changes:

```swift
final class UserState: @unchecked Sendable {
    private let lock = NSLock()
    private var _user: User?
    weak var emitter: EventEmitter?

    var user: User? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _user
        }
        set {
            lock.lock()
            _user = newValue
            lock.unlock()
            emitter?.emit("user:changed", payload: newValue)
        }
    }
}
```

### Real-time Updates

```swift
// WebSocket or server connection
func connectToServer(context: CommandContext) {
    serverConnection.onMessage { message in
        context.emit("server:message", payload: message)
    }

    serverConnection.onDisconnect {
        context.emit("server:disconnected", payload: EmptyPayload())
    }
}
```

## Event Filtering

Send events only to matching targets:

```swift
// Only to webviews that pass a filter
context.emit("notification", payload: message, target: .filter { webview in
    webview.url.hasPrefix("app://localhost/admin")
})
```

## Best Practices

### Event Naming

Use namespaced event names:

```swift
// Good
context.emit("download:started", ...)
context.emit("download:progress", ...)
context.emit("download:complete", ...)
context.emit("user:login", ...)
context.emit("user:logout", ...)

// Avoid
context.emit("started", ...)
context.emit("data", ...)
```

### Payload Structure

Keep payloads focused and typed:

```swift
// Good: Typed payload
struct ProgressPayload: Codable, Sendable {
    let taskId: String
    let percent: Int
    let currentItem: String?
}

// Avoid: Unstructured dictionaries
context.emit("progress", payload: [
    "id": taskId,
    "p": 50,
    "item": currentItem
])
```

### Cleanup Listeners

Always store and call the unlisten function:

```javascript
// Store unlisten functions
const listeners = [];

function setupListeners() {
    listeners.push(await window.Velox.listen('event1', handler1));
    listeners.push(await window.Velox.listen('event2', handler2));
}

function cleanup() {
    listeners.forEach(unlisten => unlisten());
    listeners.length = 0;
}

// Call cleanup when navigating away or unmounting
window.addEventListener('beforeunload', cleanup);
```

## See Also

- <doc:CreatingCommands>
- <doc:DeferredResponses>
- ``EventEmitter``
- ``EventListener``
- ``Channel``
