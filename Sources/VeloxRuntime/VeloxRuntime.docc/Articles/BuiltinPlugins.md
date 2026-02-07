# Built-in Plugins

Use Velox's ready-made plugins for common functionality.

## Overview

Velox includes eight built-in plugins that provide access to system features. Import them from `VeloxPlugins` or individually.

## Using Built-in Plugins

### Import All Plugins

```swift
import VeloxPlugins

let app = try VeloxAppBuilder(directory: projectDir)
    .plugins(VeloxPlugins.all)
    .registerCommands(appCommands)
```

### Import Individual Plugins

```swift
import VeloxPluginDialog
import VeloxPluginClipboard

let app = try VeloxAppBuilder(directory: projectDir)
    .plugin(DialogPlugin())
    .plugin(ClipboardPlugin())
```

## Dialog Plugin

**Module:** `VeloxPluginDialog`

Native file dialogs and message boxes.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:dialog|open` | `OpenDialogArgs` | Show file open dialog |
| `plugin:dialog|save` | `SaveDialogArgs` | Show file save dialog |
| `plugin:dialog|message` | `MessageArgs` | Show message box |
| `plugin:dialog|ask` | `AskArgs` | Show yes/no dialog |
| `plugin:dialog|confirm` | `ConfirmArgs` | Show OK/Cancel dialog |

### Examples

```javascript
// Open file dialog
const files = await window.Velox.invoke('plugin:dialog|open', {
    title: 'Select Files',
    multiple: true,
    filters: [
        { name: 'Images', extensions: ['png', 'jpg', 'gif'] },
        { name: 'All Files', extensions: ['*'] }
    ]
});

// Save file dialog
const path = await window.Velox.invoke('plugin:dialog|save', {
    title: 'Save Document',
    defaultPath: 'document.txt',
    filters: [
        { name: 'Text Files', extensions: ['txt'] }
    ]
});

// Message box
await window.Velox.invoke('plugin:dialog|message', {
    title: 'Success',
    message: 'File saved successfully!',
    type: 'info'  // 'info', 'warning', 'error'
});

// Confirmation dialog
const confirmed = await window.Velox.invoke('plugin:dialog|confirm', {
    title: 'Confirm Delete',
    message: 'Are you sure you want to delete this file?',
    okLabel: 'Delete',
    cancelLabel: 'Keep'
});
```

## Clipboard Plugin

**Module:** `VeloxPluginClipboard`

Read and write system clipboard.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:clipboard|read` | None | Read clipboard text |
| `plugin:clipboard|write` | `WriteArgs` | Write text to clipboard |

### Examples

```javascript
// Read clipboard
const text = await window.Velox.invoke('plugin:clipboard|read');
console.log('Clipboard contains:', text);

// Write to clipboard
await window.Velox.invoke('plugin:clipboard|write', {
    text: 'Hello from Velox!'
});
```

## Notification Plugin

**Module:** `VeloxPluginNotification`

System notifications.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:notification|send` | `NotificationArgs` | Send a notification |
| `plugin:notification|requestPermission` | None | Request notification permission |

### Examples

```javascript
// Request permission first
const permission = await window.Velox.invoke('plugin:notification|requestPermission');

if (permission.granted) {
    // Send notification
    await window.Velox.invoke('plugin:notification|send', {
        title: 'Download Complete',
        body: 'Your file has been downloaded.',
        icon: 'app://localhost/icons/download.png'
    });
}
```

## Shell Plugin

**Module:** `VeloxPluginShell`

Execute system commands.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:shell|execute` | `ExecuteArgs` | Run command and wait |
| `plugin:shell|spawn` | `SpawnArgs` | Start background process |
| `plugin:shell|kill` | `KillArgs` | Terminate a process |

### Examples

```javascript
// Execute command and get output
const result = await window.Velox.invoke('plugin:shell|execute', {
    program: 'ls',
    args: ['-la', '/Users']
});
console.log('Output:', result.stdout);
console.log('Exit code:', result.code);

// Spawn background process
const process = await window.Velox.invoke('plugin:shell|spawn', {
    program: 'tail',
    args: ['-f', '/var/log/system.log']
});

// Listen for output
window.Velox.listen(`shell:stdout:${process.pid}`, (e) => {
    console.log('Output:', e.payload);
});

// Kill the process later
await window.Velox.invoke('plugin:shell|kill', { pid: process.pid });
```

> Warning: Shell commands can be dangerous. Only expose to trusted frontends with proper permission controls.

## OS Info Plugin

**Module:** `VeloxPluginOS`

System information.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:os|version` | None | Get OS version string |
| `plugin:os|arch` | None | Get CPU architecture |
| `plugin:os|hostname` | None | Get machine hostname |
| `plugin:os|locale` | None | Get system locale |

### Examples

```javascript
const version = await window.Velox.invoke('plugin:os|version');
const arch = await window.Velox.invoke('plugin:os|arch');
const hostname = await window.Velox.invoke('plugin:os|hostname');
const locale = await window.Velox.invoke('plugin:os|locale');

console.log(`Running on ${hostname}`);
console.log(`OS: ${version} (${arch})`);
console.log(`Locale: ${locale}`);
```

## Process Plugin

**Module:** `VeloxPluginProcess`

Application process control.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:process|exit` | `ExitArgs` | Exit the application |
| `plugin:process|relaunch` | None | Restart the application |
| `plugin:process|environment` | None | Get environment variables |

### Examples

```javascript
// Get environment variables
const env = await window.Velox.invoke('plugin:process|environment');
console.log('PATH:', env.PATH);
console.log('HOME:', env.HOME);

// Relaunch the app
await window.Velox.invoke('plugin:process|relaunch');

// Exit with code
await window.Velox.invoke('plugin:process|exit', { code: 0 });
```

## Menu Plugin

**Module:** `VeloxPluginMenu`

Native application and window menus, modeled after Tauri.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:menu|new` | `MenuArgs` | Create a new menu |
| `plugin:menu|create_default` | `DefaultMenuArgs` | Create the default application menu |
| `plugin:menu|append` | `MenuItemActionArgs` | Append an item to a menu or submenu |
| `plugin:menu|prepend` | `MenuItemActionArgs` | Prepend an item to a menu or submenu |
| `plugin:menu|insert` | `MenuItemActionArgs` | Insert an item at a position |
| `plugin:menu|remove` | `MenuItemActionArgs` | Remove an item |
| `plugin:menu|remove_at` | `MenuRemoveAtArgs` | Remove an item at a position |
| `plugin:menu|items` | `MenuItemsArgs` | List items for a menu or submenu |
| `plugin:menu|get` | `MenuGetArgs` | Get an item by id |
| `plugin:menu|popup` | `MenuPopupArgs` | Show a popup menu |
| `plugin:menu|set_as_app_menu` | `SetMenuAsAppMenuArgs` | Set menu as the application menu |
| `plugin:menu|set_as_window_menu` | `SetMenuAsWindowMenuArgs` | Set menu as a window menu |
| `plugin:menu|text` | `MenuItemTextArgs` | Read an item’s label |
| `plugin:menu|set_text` | `MenuItemTextArgs` | Update an item’s label |
| `plugin:menu|is_enabled` | `MenuItemEnabledArgs` | Check if an item is enabled |
| `plugin:menu|set_enabled` | `MenuItemEnabledArgs` | Enable or disable an item |
| `plugin:menu|set_accelerator` | `MenuItemAcceleratorArgs` | Set a keyboard shortcut |
| `plugin:menu|is_checked` | `MenuItemCheckedArgs` | Check if a check item is selected |
| `plugin:menu|set_checked` | `MenuItemCheckedArgs` | Set a check item |
| `plugin:menu|set_icon` | `MenuItemIconArgs` | Set a native icon for an item |

### Examples

```javascript
// Create a menu bar and set it as the app menu
const menu = await window.Velox.invoke('plugin:menu|new', { items: [] });
await window.Velox.invoke('plugin:menu|set_as_app_menu', { menu });

// Create a submenu and a menu item, then append it
const openItem = {
  id: 'open',
  kind: 'MenuItem',
  text: 'Open…',
  enabled: true,
  accelerator: 'CmdOrCtrl+O'
};

await window.Velox.invoke('plugin:menu|append', {
  menu,
  items: [openItem]
});

// Build the default application menu
const defaultMenu = await window.Velox.invoke('plugin:menu|create_default', {});
await window.Velox.invoke('plugin:menu|set_as_app_menu', { menu: defaultMenu });
```

## Opener Plugin

**Module:** `VeloxPluginOpener`

Open files and URLs with default applications.

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `plugin:opener|open` | `OpenArgs` | Open file or URL |

### Examples

```javascript
// Open URL in default browser
await window.Velox.invoke('plugin:opener|open', {
    path: 'https://velox.dev'
});

// Open file with default application
await window.Velox.invoke('plugin:opener|open', {
    path: '/Users/me/document.pdf'
});

// Open folder in Finder
await window.Velox.invoke('plugin:opener|open', {
    path: '/Users/me/Downloads'
});
```

## Security Considerations

Built-in plugins have powerful system access. Consider:

1. **Don't expose all plugins** — Only register plugins you need
2. **Validate inputs** — Especially for shell commands and file paths
3. **Use permissions** — Configure capability-based access control
4. **Audit shell commands** — Log and review shell plugin usage

```swift
// Only register what you need
let app = try VeloxAppBuilder(directory: projectDir)
    .plugin(ClipboardPlugin())  // Safe
    .plugin(OSInfoPlugin())     // Safe
    // .plugin(ShellPlugin())   // Dangerous - omit if not needed
```

## See Also

- <doc:BuildingPlugins>
- <doc:Configuration>
