# Dialog Plugin: Alert Dialog Limitations

## Summary

**File dialogs (Open, Save) work correctly.** Alert dialogs (Message, Ask, Confirm) cannot run in-process while an IPC request is blocking the run loop. The Swift plugin now defers alert responses and resolves them asynchronously after the IPC handler returns.

## Root Cause

The Dialog plugin commands are invoked from WebKit's `WKURLSchemeHandler`, which runs synchronously on the main thread. This creates a conflict:

1. WebKit's custom protocol handler blocks the main thread waiting for a response
2. Modal dialogs need the run loop to process user input
3. The run loop is blocked waiting for the protocol handler to return
4. This creates a deadlock/conflict situation

## What Works: File Dialogs

`NSOpenPanel` and `NSSavePanel` work because they have a truly async API:

```swift
panel.begin { response in
    // Called when user responds
    done = true
}

// Pump run loop in .modalPanel mode until done
while !done {
    CFRunLoopRunInMode(.modalPanel, 0.1, true)
}
```

The key insight is that `panel.begin()` internally sets up a modal session that integrates properly with `.modalPanel` run loop mode.

## What Doesn't Work In-Process: Alert Dialogs

`NSAlert` does not have an equivalent async API that works in this context:

### Approaches Tried

| Approach | Result |
|----------|--------|
| `alert.runModal()` directly | Flashes and closes immediately |
| `alert.runModal()` inside `runModalDeferred` | Still flashes and closes |
| `beginSheetModal` + `.modalPanel` pumping | Hangs (busy loop) |
| `beginSheetModal` + `.default` mode pumping | Hangs (tao event loop conflict) |
| `beginSheetModal` on standalone panel | Hangs |
| `beginSheetModal` on main window | Hangs |
| `beginModalSession` + `runModalSession` | Auto-dismisses immediately |
| Dual mode pumping (modal + default) | Hangs |
| FFI/rfd dialogs via VeloxRuntimeWry | Same issues |

### Stack Trace Analysis

When pumping in `.default` mode, the run loop triggers tao's (Rust windowing library) event loop observers, causing nested event handling conflicts:

```
CoreFoundation CFRunLoopRunSpecific
HIToolbox RunCurrentEventLoopInMode
tao::platform_impl::macos::event_loop::callback
```

## Technical Details

### Why File Panels Work Differently

`NSOpenPanel.begin()` and `NSSavePanel.begin()` are special-cased in AppKit:
- They create their own modal session internally
- They integrate with `.modalPanel` run loop mode
- Events are properly dispatched without triggering the main event loop observers

### Why NSAlert Doesn't Work

`NSAlert` only provides:
- `runModal()` - Synchronous, blocks, conflicts with WebKit context
- `beginSheetModal(for:completionHandler:)` - Requires parent window, completion scheduled in `.default` mode which conflicts with tao

## Potential Solutions

### 1. Async Command API (Implemented)

Modify the IPC layer to support async responses:
- Command returns immediately with a "pending" state
- Dialog runs truly async
- Result sent via callback/event when user responds

### 2. Separate Process

Spawn a helper process to show dialogs:
- Avoids run loop conflicts entirely
- More complex architecture
- Would work for all dialog types

### 3. Custom Dialog UI

Build dialogs using web content instead of native alerts:
- Runs in WebView, no run loop issues
- Less native look and feel
- Full control over behavior

### 4. Accept Limitation

Document that alert dialogs are not supported in synchronous IPC mode:
- File dialogs work
- Alert dialogs require frontend-only implementation (JavaScript confirm/alert)

## Current State

File dialogs use AppKit and behave correctly. Alert dialog commands return a pending response immediately, then show `NSAlert` on the main thread and resolve via an async invoke response event.
