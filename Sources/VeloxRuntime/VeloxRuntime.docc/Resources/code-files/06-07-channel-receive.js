// Create a channel and receive streamed data
async function startStreaming() {
    // Create a new channel
    const channel = new VeloxChannel();

    // Handle incoming messages
    channel.onmessage = (msg) => {
        switch (msg.event) {
            case 'data':
                console.log('Received value:', msg.data);
                updateDisplay(msg.data);
                break;
            case 'end':
                console.log('Stream ended');
                showComplete();
                break;
        }
    };

    // Handle channel close
    channel.onclose = () => {
        console.log('Channel closed');
    };

    // Handle errors
    channel.onerror = (error) => {
        console.error('Channel error:', error);
    };

    // Start the stream, passing the channel
    await window.Velox.invoke('start_stream', { onData: channel });
}

// Controllable stream example
let activeChannel = null;

async function startControllableStream() {
    // Create channel
    activeChannel = new VeloxChannel();

    const values = [];

    activeChannel.onmessage = (msg) => {
        if (msg.event === 'data') {
            values.push(msg.data);
            renderChart(values);
        } else if (msg.event === 'end') {
            console.log('Stream ended with', values.length, 'values');
            activeChannel = null;
            updateButton('Start');
        }
    };

    // Start streaming
    await window.Velox.invoke('start_controllable_stream', {
        onData: activeChannel
    });

    updateButton('Stop');
}

async function stopStream() {
    if (activeChannel) {
        await window.Velox.invoke('stop_stream', {
            channelId: activeChannel.id
        });
    }
}

// Toggle button
document.getElementById('stream-btn').addEventListener('click', () => {
    if (activeChannel) {
        stopStream();
    } else {
        startControllableStream();
    }
});
