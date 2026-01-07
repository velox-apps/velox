// Listen for events from Swift
const listeners = {};

// Set up event listeners
function setupEventListeners() {
    // Listen for task started events
    listeners.taskStarted = Velox.event.listen('task-started', (event) => {
        console.log('Task started at:', event.payload.timestamp);
        updateStatus(event.payload.status);
    });

    // Listen for item processed events
    listeners.itemProcessed = Velox.event.listen('item-processed', (event) => {
        console.log('Processed:', event.payload.item);
        addToLog(event.payload.item);
    });

    // Listen for completion events
    listeners.complete = Velox.event.listen('processing-complete', (event) => {
        console.log(`Completed! Processed ${event.payload.count} items`);
        showCompletion(event.payload);
    });
}

// Remove a specific listener
function stopListening(name) {
    if (listeners[name]) {
        Velox.event.unlisten(listeners[name]);
        delete listeners[name];
        console.log(`Stopped listening to: ${name}`);
    }
}

// Remove all listeners
function removeAllListeners() {
    Object.keys(listeners).forEach(key => {
        Velox.event.unlisten(listeners[key]);
    });
    listeners = {};
    console.log('All listeners removed');
}

// Emit an event TO the backend
async function notifyBackend(eventName, data) {
    await Velox.event.emit(eventName, data);
}

// Example: Tell backend user clicked something
document.getElementById('action-btn').addEventListener('click', () => {
    notifyBackend('user-action', {
        action: 'click',
        element: 'action-btn',
        timestamp: Date.now()
    });
});

// Initialize listeners when page loads
document.addEventListener('DOMContentLoaded', setupEventListeners);
