// Velox CommandsManual - Frontend JavaScript

async function invoke(command, args = {}) {
  const response = await fetch(`ipc://localhost/${command}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  return response.json();
}

async function runCommand(command, args) {
  const responseEl = document.getElementById('response');
  responseEl.className = 'response-box';
  responseEl.textContent = `Calling ${command}...`;

  try {
    const result = await invoke(command, args);
    if (result.error) {
      responseEl.className = 'response-box error';
      responseEl.textContent = `Error: ${result.error}\n${result.message || ''}`;
    } else {
      responseEl.className = 'response-box success';
      responseEl.textContent = `Command: ${command}\nResult: ${JSON.stringify(result.result, null, 2)}`;
    }
  } catch (err) {
    responseEl.className = 'response-box error';
    responseEl.textContent = `Fetch Error: ${err.message}`;
  }
}

console.log('CommandsManual example loaded - using manual switch routing');
