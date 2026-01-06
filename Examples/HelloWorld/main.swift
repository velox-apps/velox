// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

struct GreetArgs: Codable, Sendable {
  let name: String
}

let htmlContent = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Welcome to Velox!</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        max-width: 600px;
        margin: 50px auto;
        padding: 20px;
        text-align: center;
      }
      h1 {
        color: #333;
      }
      form {
        margin: 20px 0;
      }
      input {
        padding: 10px;
        font-size: 16px;
        border: 1px solid #ccc;
        border-radius: 4px;
        margin-right: 10px;
      }
      button {
        padding: 10px 20px;
        font-size: 16px;
        background-color: #007AFF;
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
      }
      button:hover {
        background-color: #0056b3;
      }
      #message {
        margin-top: 20px;
        padding: 15px;
        background-color: #f0f0f0;
        border-radius: 4px;
        min-height: 20px;
      }
    </style>
  </head>
  <body>
    <h1>Welcome to Velox!</h1>

    <form id="form">
      <input id="name" placeholder="Enter a name..." />
      <button type="submit">Greet</button>
    </form>

    <p id="message"></p>

    <script>
      async function invoke(command, args = {}) {
        if (window.Velox && typeof window.Velox.invoke === 'function') {
          return window.Velox.invoke(command, args);
        }
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

      const form = document.querySelector('#form');
      const nameEl = document.querySelector('#name');
      const messageEl = document.querySelector('#message');

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
    </script>
  </body>
</html>
"""

func main() {
  guard Thread.isMainThread else {
    fatalError("HelloWorld must run on the main thread")
  }

  let exampleDir = URL(fileURLWithPath: #file).deletingLastPathComponent()

  let registry = commands {
    command("greet", args: GreetArgs.self, returning: String.self) { args, _ in
      "Hello \(args.name), You have been greeted from Swift!"
    }
  }

  do {
    let app = try VeloxAppBuilder(directory: exampleDir)
      .registerAppProtocol { _ in htmlContent }
      .registerCommands(registry)
    try app.run()
  } catch {
    fatalError("HelloWorld failed to start: \(error)")
  }
}

main()
