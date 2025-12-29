// Velox IPC: invoke commands via custom protocol
async function invoke(command, args = {}) {
  const response = await fetch(`ipc://localhost/${command}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  const data = await response.json();
  if (data.error) {
    throw new Error(data.error);
  }
  return data.result;
}

// DOM elements
const form = document.querySelector('#form');
const nameEl = document.querySelector('#name');
const messageEl = document.querySelector('#message');

// Handle form submission
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    const name = nameEl.value || 'World';
    const message = await invoke('greet', { name });
    messageEl.textContent = message;
  } catch (err) {
    messageEl.textContent = 'Error: ' + err.message;
  }
});

// Log that the app has loaded
console.log('Velox HelloWorld2 app loaded from bundled assets!');
