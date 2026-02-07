// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

/// Built-in Resources plugin for closing resource handles.
///
/// This plugin exposes the following command:
/// - `plugin:resources|close` - Close and remove a resource by ID
public final class ResourcesPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "resources"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    if context.stateContainer.get() as ResourceRegistry? == nil {
      context.stateContainer.manage(ResourceRegistry())
    }

    let commands = context.commands(for: name)
    commands.register("close", args: CloseArgs.self) { args, context in
      guard let registry: ResourceRegistry = context.stateContainer.get() else {
        return .ok
      }
      _ = registry.remove(args.rid)
      return .ok
    }
  }

  private struct CloseArgs: Codable, Sendable {
    let rid: Int
  }
}
