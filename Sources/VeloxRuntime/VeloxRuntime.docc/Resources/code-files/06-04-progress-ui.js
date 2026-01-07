// Progress bar UI handler
const progressBar = document.getElementById('progress-bar');
const progressText = document.getElementById('progress-text');
const progressPercent = document.getElementById('progress-percent');
const startBtn = document.getElementById('start-btn');

// Listen for progress events
Velox.event.listen('progress', (event) => {
    const { current, total, message, percent } = event.payload;

    // Update progress bar width
    progressBar.style.width = `${percent}%`;

    // Update text displays
    progressText.textContent = message;
    progressPercent.textContent = `${Math.round(percent)}%`;

    // Update aria attributes for accessibility
    progressBar.setAttribute('aria-valuenow', percent);

    // Handle completion
    if (percent >= 100) {
        progressBar.classList.add('complete');
        startBtn.disabled = false;
        startBtn.textContent = 'Start Again';
    }
});

// Start processing
startBtn.addEventListener('click', async () => {
    // Reset UI
    progressBar.style.width = '0%';
    progressBar.classList.remove('complete');
    progressText.textContent = 'Initializing...';
    progressPercent.textContent = '0%';
    startBtn.disabled = true;
    startBtn.textContent = 'Processing...';

    try {
        const result = await window.Velox.invoke('process_files');
        console.log('Result:', result);
    } catch (error) {
        progressText.textContent = `Error: ${error.message}`;
        startBtn.disabled = false;
        startBtn.textContent = 'Retry';
    }
});
