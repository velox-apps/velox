// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

// MARK: - VeloxAppBuilder Plugin Extension

public extension VeloxAppBuilder {
  /// The plugin manager for this app.
  /// Created lazily on first access.
  var pluginManager: PluginManager {
    if let existing: PluginManager = stateContainer.get() {
      return existing
    }
    let manager = PluginManager()
    stateContainer.manage(manager)
    return manager
  }

  /// Register a plugin with the app.
  ///
  /// - Parameter plugin: The plugin to register.
  /// - Returns: Self for chaining.
  ///
  /// Example:
  /// ```swift
  /// let builder = try VeloxAppBuilder()
  ///     .plugin(AnalyticsPlugin())
  ///     .plugin(AuthPlugin())
  /// ```
  @discardableResult
  func plugin(_ plugin: VeloxPlugin) -> Self {
    pluginManager.register(plugin)
    return self
  }

  /// Register multiple plugins.
  ///
  /// - Parameter plugins: The plugins to register.
  /// - Returns: Self for chaining.
  @discardableResult
  func plugins(_ plugins: VeloxPlugin...) -> Self {
    for plugin in plugins {
      pluginManager.register(plugin)
    }
    return self
  }

  /// Register plugins using a result builder.
  ///
  /// Example:
  /// ```swift
  /// let builder = try VeloxAppBuilder()
  ///     .plugins {
  ///         AnalyticsPlugin()
  ///         AuthPlugin()
  ///         if isDebug {
  ///             DevToolsPlugin()
  ///         }
  ///     }
  /// ```
  @discardableResult
  func plugins(@PluginBuilder _ builder: () -> [VeloxPlugin]) -> Self {
    let plugins = builder()
    for plugin in plugins {
      pluginManager.register(plugin)
    }
    return self
  }
}

// MARK: - Plugin Result Builder

/// Result builder for declarative plugin registration.
@resultBuilder
public struct PluginBuilder {
  public static func buildBlock(_ components: [VeloxPlugin]...) -> [VeloxPlugin] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [VeloxPlugin]?) -> [VeloxPlugin] {
    component ?? []
  }

  public static func buildEither(first component: [VeloxPlugin]) -> [VeloxPlugin] {
    component
  }

  public static func buildEither(second component: [VeloxPlugin]) -> [VeloxPlugin] {
    component
  }

  public static func buildArray(_ components: [[VeloxPlugin]]) -> [VeloxPlugin] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ plugin: VeloxPlugin) -> [VeloxPlugin] {
    [plugin]
  }
}
