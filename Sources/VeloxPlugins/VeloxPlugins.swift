// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

/// VeloxPlugins provides built-in plugins for common desktop application functionality.
///
/// This umbrella module re-exports all individual plugin modules for convenience.
/// You can also import individual plugins directly for smaller binary size.
///
/// ## Available Plugins
///
/// - ``DialogPlugin`` - Native file dialogs and message boxes
/// - ``ClipboardPlugin`` - System clipboard read/write
/// - ``NotificationPlugin`` - Native notifications
/// - ``ShellPlugin`` - Execute system commands
/// - ``OSInfoPlugin`` - Operating system information
/// - ``ProcessPlugin`` - Current process management
/// - ``OpenerPlugin`` - Open files/URLs with external apps
///
/// ## Usage
///
/// Import all plugins at once:
/// ```swift
/// import VeloxPlugins
///
/// VeloxAppBuilder(config: config)
///   .plugin(DialogPlugin())
///   .plugin(ClipboardPlugin())
///   .build()
/// ```
///
/// Or import individual plugins:
/// ```swift
/// import VeloxPluginDialog
/// import VeloxPluginClipboard
///
/// VeloxAppBuilder(config: config)
///   .plugin(DialogPlugin())
///   .plugin(ClipboardPlugin())
///   .build()
/// ```

@_exported import VeloxPluginDialog
@_exported import VeloxPluginClipboard
@_exported import VeloxPluginNotification
@_exported import VeloxPluginShell
@_exported import VeloxPluginOS
@_exported import VeloxPluginProcess
@_exported import VeloxPluginOpener
