document.addEventListener('DOMContentLoaded', async () => {
    const counterDisplay = document.getElementById('counter');
    const incrementBtn = document.getElementById('increment-btn');
    const decrementBtn = document.getElementById('decrement-btn');
    const resetBtn = document.getElementById('reset-btn');

    // Helper to update the display
    function updateDisplay(value) {
        counterDisplay.textContent = value;
    }

    // Load initial counter value from backend state
    async function loadCounter() {
        try {
            const response = await window.Velox.invoke('counter:get');
            updateDisplay(response.value);
        } catch (error) {
            console.error('Failed to load counter:', error);
        }
    }

    // Increment handler
    incrementBtn.addEventListener('click', async () => {
        try {
            const response = await window.Velox.invoke('counter:increment');
            updateDisplay(response.value);
        } catch (error) {
            console.error('Failed to increment:', error);
        }
    });

    // Decrement handler
    decrementBtn.addEventListener('click', async () => {
        try {
            const response = await window.Velox.invoke('counter:decrement');
            updateDisplay(response.value);
        } catch (error) {
            console.error('Failed to decrement:', error);
        }
    });

    // Reset handler
    resetBtn.addEventListener('click', async () => {
        try {
            const response = await window.Velox.invoke('counter:reset');
            updateDisplay(response.value);
        } catch (error) {
            console.error('Failed to reset:', error);
        }
    });

    // Keyboard shortcuts
    document.addEventListener('keydown', async (e) => {
        if (e.key === 'ArrowUp' || e.key === '+') {
            incrementBtn.click();
        } else if (e.key === 'ArrowDown' || e.key === '-') {
            decrementBtn.click();
        } else if (e.key === 'r' || e.key === 'R') {
            resetBtn.click();
        }
    });

    // Load initial value
    await loadCounter();
});
