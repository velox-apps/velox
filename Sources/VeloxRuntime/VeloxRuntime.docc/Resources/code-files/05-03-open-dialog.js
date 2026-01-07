// Open a file selection dialog
async function selectFile() {
    try {
        const result = await window.Velox.invoke('plugin:dialog:open', {
            title: 'Select a file',
            multiple: false,
            filters: [
                { name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif'] },
                { name: 'Documents', extensions: ['pdf', 'doc', 'docx'] },
                { name: 'All Files', extensions: ['*'] }
            ]
        });

        if (result) {
            console.log('Selected file:', result);
            return result;
        } else {
            console.log('Dialog cancelled');
            return null;
        }
    } catch (error) {
        console.error('Failed to open dialog:', error);
        throw error;
    }
}

// Open a multi-file selection dialog
async function selectMultipleFiles() {
    const result = await window.Velox.invoke('plugin:dialog:open', {
        title: 'Select files',
        multiple: true,
        directory: false
    });

    if (result && result.length > 0) {
        console.log(`Selected ${result.length} files:`, result);
    }
    return result;
}

// Select a directory
async function selectDirectory() {
    const result = await window.Velox.invoke('plugin:dialog:open', {
        title: 'Select a folder',
        directory: true
    });

    return result;
}
