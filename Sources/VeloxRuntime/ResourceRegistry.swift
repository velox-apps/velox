// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

/// A thread-safe registry for resources shared across plugins.
public final class ResourceRegistry: @unchecked Sendable {
  private var nextId: Int = 1
  private var resources: [Int: AnyObject] = [:]
  private let lock = NSLock()

  public init() {}

  /// Adds a resource and returns its assigned resource ID.
  @discardableResult
  public func add(_ resource: AnyObject) -> Int {
    lock.lock()
    let rid = nextId
    nextId += 1
    resources[rid] = resource
    lock.unlock()
    return rid
  }

  /// Retrieves a resource by ID.
  public func get<T: AnyObject>(_ rid: Int, as type: T.Type = T.self) -> T? {
    lock.lock()
    defer { lock.unlock() }
    return resources[rid] as? T
  }

  /// Removes a resource by ID.
  @discardableResult
  public func remove(_ rid: Int) -> AnyObject? {
    lock.lock()
    defer { lock.unlock() }
    return resources.removeValue(forKey: rid)
  }

  /// Returns whether a resource exists for the given ID.
  public func contains(_ rid: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return resources[rid] != nil
  }
}
