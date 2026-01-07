// Dashboard state
const cpuHistory = [];
const memoryHistory = [];
const MAX_HISTORY = 60;  // Keep last 60 data points

// DOM elements
const cpuValue = document.getElementById('cpu-value');
const memoryValue = document.getElementById('memory-value');
const memoryStatus = document.getElementById('memory-status');
const cpuCanvas = document.getElementById('cpu-chart');
const memoryCanvas = document.getElementById('memory-chart');

// Chart contexts
const cpuCtx = cpuCanvas.getContext('2d');
const memoryCtx = memoryCanvas.getContext('2d');

// Format bytes to MB
function bytesToMB(bytes) {
    return Math.round(bytes / (1024 * 1024));
}

// Format bytes to GB
function bytesToGB(bytes) {
    return (bytes / (1024 * 1024 * 1024)).toFixed(1);
}

// Draw a simple line chart
function drawChart(ctx, data, maxValue, color) {
    const canvas = ctx.canvas;
    const width = canvas.width;
    const height = canvas.height;

    // Clear canvas
    ctx.clearRect(0, 0, width, height);

    if (data.length < 2) return;

    // Draw line
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;

    const step = width / (MAX_HISTORY - 1);

    data.forEach((value, index) => {
        const x = index * step;
        const y = height - (value / maxValue) * height;

        if (index === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    });

    ctx.stroke();

    // Fill area under line
    ctx.lineTo((data.length - 1) * step, height);
    ctx.lineTo(0, height);
    ctx.closePath();
    ctx.fillStyle = color + '20';  // Add transparency
    ctx.fill();
}

// Update displays
function updateDashboard(metrics) {
    // Update CPU
    const cpu = Math.round(metrics.cpuUsage);
    cpuValue.textContent = cpu;
    cpuHistory.push(cpu);
    if (cpuHistory.length > MAX_HISTORY) cpuHistory.shift();
    drawChart(cpuCtx, cpuHistory, 100, '#7dd3fc');

    // Update Memory
    const memMB = bytesToMB(metrics.memoryUsed);
    memoryValue.textContent = memMB;

    const memPercent = (metrics.memoryUsed / metrics.memoryTotal) * 100;
    memoryHistory.push(memPercent);
    if (memoryHistory.length > MAX_HISTORY) memoryHistory.shift();
    drawChart(memoryCtx, memoryHistory, 100, '#34C759');

    // Update status text
    memoryStatus.textContent = `${bytesToGB(metrics.memoryUsed)} / ${bytesToGB(metrics.memoryTotal)} GB`;
}

// Listen for metrics events from Swift
Velox.event.listen('metrics-update', (event) => {
    updateDashboard(event.payload);
});

// Initialize canvas sizes
function initCanvases() {
    [cpuCanvas, memoryCanvas].forEach(canvas => {
        const rect = canvas.parentElement.getBoundingClientRect();
        canvas.width = rect.width;
        canvas.height = rect.height;
    });
}

// Setup
document.addEventListener('DOMContentLoaded', () => {
    initCanvases();
    window.addEventListener('resize', initCanvases);
});
