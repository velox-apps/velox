// Velox Commands - Frontend JavaScript

async function invoke(command, args = {}) {
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

console.log('Commands loaded - using @VeloxCommand macro');
