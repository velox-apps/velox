document.addEventListener('DOMContentLoaded', () => {
    // Greet form handler
    const greetForm = document.getElementById('greet-form');
    const greetResult = document.getElementById('greet-result');

    greetForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const name = document.getElementById('name').value.trim() || 'World';

        try {
            const response = await window.Velox.invoke('greet', { name });
            greetResult.textContent = response.message;
            greetResult.className = 'result success';
        } catch (error) {
            greetResult.textContent = `Error: ${error.message}`;
            greetResult.className = 'result error';
        }
    });

    // Math operations
    const mathResult = document.getElementById('math-result');
    const buttons = document.querySelectorAll('[data-op]');

    buttons.forEach(button => {
        button.addEventListener('click', async () => {
            const a = parseFloat(document.getElementById('num-a').value) || 0;
            const b = parseFloat(document.getElementById('num-b').value) || 0;
            const operation = button.dataset.op;

            try {
                let response;
                if (operation === 'add') {
                    response = await window.Velox.invoke('add', { a, b });
                } else if (operation === 'multiply') {
                    response = await window.Velox.invoke('multiply', { a, b });
                } else if (operation === 'divide') {
                    response = await window.Velox.invoke('divide', {
                        numerator: a,
                        denominator: b
                    });
                }

                mathResult.textContent = `Result: ${response.result} (${response.operation})`;
                mathResult.className = 'result success';
            } catch (error) {
                // Handle errors like division by zero
                mathResult.textContent = `Error: ${error.message}`;
                mathResult.className = 'result error';
            }
        });
    });
});
