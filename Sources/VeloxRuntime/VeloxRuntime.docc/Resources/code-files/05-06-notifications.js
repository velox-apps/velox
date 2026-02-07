// Check if notifications are permitted
async function checkNotificationPermission() {
    const granted = await window.Velox.invoke(
        'plugin:notification|isPermissionGranted',
        {}
    );
    console.log('Notification permission:', granted ? 'granted' : 'denied');
    return granted;
}

// Request notification permission
async function requestNotificationPermission() {
    const granted = await window.Velox.invoke(
        'plugin:notification|requestPermission',
        {}
    );

    if (granted) {
        console.log('Permission granted!');
    } else {
        console.log('Permission denied');
    }

    return granted;
}

// Send a notification
async function sendNotification(title, body) {
    try {
        // Check/request permission first
        let hasPermission = await checkNotificationPermission();

        if (!hasPermission) {
            hasPermission = await requestNotificationPermission();
        }

        if (!hasPermission) {
            console.warn('No notification permission');
            return false;
        }

        // Send the notification
        const success = await window.Velox.invoke(
            'plugin:notification|sendNotification',
            { title, body }
        );

        return success;
    } catch (error) {
        console.error('Failed to send notification:', error);
        return false;
    }
}

// Example: Notify when a task completes
async function completeTask(taskName) {
    // ... do the task work ...

    await sendNotification(
        'Task Complete',
        `${taskName} has finished successfully!`
    );
}
