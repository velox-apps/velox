// Velox Commands - Frontend JavaScript

async function invoke(command, args = {}) {
  if (window.Velox && typeof window.Velox.invoke === 'function') {
    try {
      const result = await window.Velox.invoke(command, args);
      return { result };
    } catch (e) {
      return {
        error: e && e.code ? e.code : 'Error',
        message: e && e.message ? e.message : String(e)
      };
    }
  }
  const response = await fetch('ipc://localhost/' + command, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  return response.json();
}

function showResult(id, data) {
  const el = document.getElementById(id);
  if (data.error) {
    el.className = 'result error';
    el.textContent = 'Error: ' + data.error + '\n' + (data.message || '');
  } else {
    el.className = 'result success';
    el.textContent = JSON.stringify(data.result, null, 2);
  }
}

async function greet() {
  const name = document.getElementById('greet-name').value || 'World';
  const result = await invoke('greet', { name });
  showResult('greet-result', result);
}

async function add() {
  const a = parseInt(document.getElementById('add-a').value) || 0;
  const b = parseInt(document.getElementById('add-b').value) || 0;
  const result = await invoke('add', { a, b });
  showResult('add-result', result);
}

async function divide() {
  const numerator = parseFloat(document.getElementById('div-num').value) || 0;
  const denominator = parseFloat(document.getElementById('div-den').value) || 0;
  const result = await invoke('divide', { numerator, denominator });
  showResult('div-result', result);
}

async function person() {
  const name = document.getElementById('person-name').value;
  const age = parseInt(document.getElementById('person-age').value) || 0;
  const email = document.getElementById('person-email').value || null;
  const result = await invoke('person', { name, age, email });
  showResult('person-result', result);
}

async function increment() {
  const result = await invoke('increment');
  showResult('counter-result', result);
}

async function getCounter() {
  const result = await invoke('get_counter');
  showResult('counter-result', result);
}

async function ping() {
  const result = await invoke('ping');
  showResult('ping-result', result);
}

async function delayedEcho() {
  const message = document.getElementById('deferred-message').value || 'Hello later';
  const delayMs = parseInt(document.getElementById('deferred-delay').value, 10);
  const result = await invoke('delayed_echo', {
    message,
    delayMs: Number.isFinite(delayMs) ? delayMs : 800
  });
  showResult('deferred-result', result);
}

// Binary response test - fetch image directly
async function getImage() {
  const resultEl = document.getElementById('image-result');
  const imgEl = document.getElementById('image-preview');
  try {
    const response = await fetch('ipc://localhost/get_image', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}'
    });

    if (!response.ok) {
      resultEl.className = 'result error';
      resultEl.textContent = 'Error: ' + response.status;
      imgEl.style.display = 'none';
      return;
    }

    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    imgEl.src = url;
    imgEl.style.display = 'block';
    resultEl.className = 'result success';
    resultEl.innerHTML = 'Received ' + blob.size + ' bytes (' + blob.type + ')<br>';
    resultEl.appendChild(imgEl);
  } catch (e) {
    resultEl.className = 'result error';
    resultEl.textContent = 'Error: ' + e.message;
    imgEl.style.display = 'none';
  }
}

// Webview injection test - command calls JavaScript in webview
async function showAlert() {
  const message = document.getElementById('alert-message').value || 'Hello!';
  const result = await invoke('show_alert', { message });
  showResult('alert-result', result);
}

console.log('Commands loaded - using @VeloxCommand macro');
