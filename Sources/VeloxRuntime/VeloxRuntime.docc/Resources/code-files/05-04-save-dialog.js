// Show a save file dialog
async function saveFile(content) {
    try {
        const path = await window.Velox.invoke('plugin:dialog:save', {
            title: 'Save file as',
            defaultName: 'untitled.txt',
            filters: [
                { name: 'Text Files', extensions: ['txt'] },
                { name: 'JSON Files', extensions: ['json'] },
                { name: 'All Files', extensions: ['*'] }
            ]
        });

        if (path) {
            // User selected a path - save the file
            await window.Velox.invoke('file:write', {
                path: path,
                content: content
            });
            console.log('File saved to:', path);
            return path;
        } else {
            console.log('Save cancelled');
            return null;
        }
    } catch (error) {
        console.error('Failed to save file:', error);
        throw error;
    }
}

// Save with a suggested name based on content type
async function saveDocument(doc) {
    const extension = doc.type === 'markdown' ? 'md' : 'txt';
    const defaultName = `${doc.title}.${extension}`;

    const path = await window.Velox.invoke('plugin:dialog:save', {
        title: 'Save Document',
        defaultName: defaultName
    });

    if (path) {
        await window.Velox.invoke('file:write', {
            path: path,
            content: doc.content
        });
    }

    return path;
}
