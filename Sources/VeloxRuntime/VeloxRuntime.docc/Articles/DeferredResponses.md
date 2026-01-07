# Deferred Responses

Handle async operations that complete after your command returns.

## Overview

Some operations can't return immediately—modal dialogs, long-running tasks, or operations that need to wait for user input. Deferred responses let you return a placeholder and resolve the actual result later.

## When to Use Deferred Responses

Use deferred responses when:

- Showing modal dialogs (file pickers, alerts, confirmations)
- Performing long-running operations with progress
- Waiting for external callbacks (network, hardware)
- Operations that must run on the main thread after the command returns

## Basic Usage

### Create a Deferred Response

```swift
command("show_dialog", returning: DeferredCommandResponse.self) { context in
    let deferred = try context.deferResponse()

    DispatchQueue.main.async {
        let result = showNativeDialog()
        deferred.responder.resolve(result)
    }

    return deferred.pending
}
```

### How It Works

1. **`context.deferResponse()`** creates a deferred handle with a unique ID
2. **`deferred.pending`** is returned immediately to the IPC layer
3. **`deferred.responder.resolve()`** sends the actual result when ready
4. **JavaScript awaits** the final result transparently

```
JavaScript                          Swift
    │                                  │
    ├─── invoke('show_dialog') ───────▶│
    │                                  ├─── deferResponse()
    │                                  ├─── return pending
    │◀── { pending: true, id: "..." }──┤
    │                                  │
    │     (waiting...)                 ├─── showNativeDialog()
    │                                  │
    │◀── resolve(result) ─────────────┤
    │                                  │
    ├─── Promise resolves with result  │
```

## Dialog Plugin Example

The Dialog plugin uses deferred responses for native dialogs:

```swift
struct DialogPlugin: VeloxPlugin {
    func initialize(context: PluginSetupContext) throws {
        context.commands {
            command("message", args: MessageArgs.self, returning: DeferredCommandResponse.self) { args, ctx in
                let deferred = try ctx.deferResponse()

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = args.title
                    alert.informativeText = args.message
                    alert.addButton(withTitle: "OK")

                    let response = alert.runModal()
                    deferred.responder.resolve(["clicked": "ok"])
                }

                return deferred.pending
            }

            command("confirm", args: ConfirmArgs.self, returning: DeferredCommandResponse.self) { args, ctx in
                let deferred = try ctx.deferResponse()

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = args.title
                    alert.informativeText = args.message
                    alert.addButton(withTitle: args.okLabel ?? "OK")
                    alert.addButton(withTitle: args.cancelLabel ?? "Cancel")

                    let response = alert.runModal()
                    let confirmed = response == .alertFirstButtonReturn
                    deferred.responder.resolve(["confirmed": confirmed])
                }

                return deferred.pending
            }
        }
    }
}
```

## Long-Running Operations

For operations with progress updates:

```swift
command("process_files", args: ProcessArgs.self, returning: DeferredCommandResponse.self) { args, ctx in
    let deferred = try ctx.deferResponse()

    Task {
        do {
            var processed = 0
            for file in args.files {
                try await processFile(file)
                processed += 1

                // Emit progress event
                ctx.emit("process:progress", payload: [
                    "current": processed,
                    "total": args.files.count
                ])
            }

            deferred.responder.resolve(ProcessResult(count: processed))
        } catch {
            deferred.responder.reject(error)
        }
    }

    return deferred.pending
}
```

```javascript
// Listen for progress
window.Velox.listen('process:progress', (e) => {
    updateProgress(e.payload.current, e.payload.total);
});

// Invoke and wait for completion
try {
    const result = await window.Velox.invoke('process_files', { files });
    console.log('Processed', result.count, 'files');
} catch (error) {
    console.error('Processing failed:', error);
}
```

## Error Handling

### Rejecting Deferred Responses

Use `reject()` to signal an error:

```swift
command("risky_operation", returning: DeferredCommandResponse.self) { ctx in
    let deferred = try ctx.deferResponse()

    Task {
        do {
            let result = try await performOperation()
            deferred.responder.resolve(result)
        } catch {
            deferred.responder.reject(error)
        }
    }

    return deferred.pending
}
```

### JavaScript Error Handling

Rejected deferred responses throw in JavaScript:

```javascript
try {
    const result = await window.Velox.invoke('risky_operation');
} catch (error) {
    console.error('Operation failed:', error.message);
}
```

## Typed Deferred Responses

Specify the response type for clarity:

```swift
struct FilePickerResult: Codable, Sendable {
    let paths: [String]
    let cancelled: Bool
}

command("pick_files", returning: DeferredCommandResponse.self) { ctx in
    let deferred = try ctx.deferResponse()

    DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true

        let response = panel.runModal()

        if response == .OK {
            let paths = panel.urls.map { $0.path }
            deferred.responder.resolve(FilePickerResult(paths: paths, cancelled: false))
        } else {
            deferred.responder.resolve(FilePickerResult(paths: [], cancelled: true))
        }
    }

    return deferred.pending
}
```

## Timeout Handling

Implement timeouts for operations that might hang:

```swift
command("fetch_with_timeout", args: FetchArgs.self, returning: DeferredCommandResponse.self) { args, ctx in
    let deferred = try ctx.deferResponse()
    let timeout = args.timeoutMs ?? 30000

    let task = Task {
        do {
            let result = try await fetchData(args.url)
            deferred.responder.resolve(result)
        } catch {
            deferred.responder.reject(error)
        }
    }

    // Timeout handler
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
        if !task.isCancelled {
            task.cancel()
            deferred.responder.reject(CommandError(
                code: "Timeout",
                message: "Operation timed out after \(timeout)ms"
            ))
        }
    }

    return deferred.pending
}
```

## Best Practices

### Always Resolve or Reject

Every deferred response must be resolved or rejected:

```swift
// Good: Always resolves
command("safe_operation", returning: DeferredCommandResponse.self) { ctx in
    let deferred = try ctx.deferResponse()

    Task {
        do {
            let result = try await operation()
            deferred.responder.resolve(result)
        } catch {
            deferred.responder.reject(error)  // Don't forget error cases!
        }
    }

    return deferred.pending
}

// Bad: May never resolve if operation fails
command("unsafe_operation", returning: DeferredCommandResponse.self) { ctx in
    let deferred = try ctx.deferResponse()

    Task {
        let result = try? await operation()  // Errors silently swallowed
        if let result = result {
            deferred.responder.resolve(result)
        }
        // Never resolves on failure - JavaScript hangs forever!
    }

    return deferred.pending
}
```

### Thread Safety

The responder is thread-safe, but resolve/reject only once:

```swift
// Safe: Can be called from any thread
DispatchQueue.global().async {
    deferred.responder.resolve(result)
}

// Warning: Calling twice has no effect (second call is ignored)
deferred.responder.resolve(result1)
deferred.responder.resolve(result2)  // Ignored
```

## See Also

- <doc:CreatingCommands>
- <doc:EventSystem>
- ``DeferredCommandResponse``
