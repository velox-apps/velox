// Write text to clipboard
async function copyToClipboard(text) {
    try {
        await window.Velox.invoke('plugin:clipboard|writeText', { text });
        console.log('Copied to clipboard:', text);
        return true;
    } catch (error) {
        console.error('Failed to copy:', error);
        return false;
    }
}

// Read text from clipboard
async function pasteFromClipboard() {
    try {
        const text = await window.Velox.invoke('plugin:clipboard|readText', {});
        console.log('Clipboard contents:', text);
        return text;
    } catch (error) {
        console.error('Failed to read clipboard:', error);
        return null;
    }
}

// Clear the clipboard
async function clearClipboard() {
    await window.Velox.invoke('plugin:clipboard|clear', {});
}

// Example: Copy button handler
document.getElementById('copy-btn').addEventListener('click', async () => {
    const textToCopy = document.getElementById('text-input').value;
    const success = await copyToClipboard(textToCopy);

    if (success) {
        showNotification('Copied to clipboard!');
    }
});

// Example: Paste button handler
document.getElementById('paste-btn').addEventListener('click', async () => {
    const text = await pasteFromClipboard();

    if (text) {
        document.getElementById('text-input').value = text;
    }
});
