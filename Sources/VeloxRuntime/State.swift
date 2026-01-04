// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - State Container

/// A type-safe container for managing application state.
/// Similar to Tauri's `tauri::State<T>`.
public final class StateContainer: @unchecked Sendable {
  private var states: [ObjectIdentifier: Any] = [:]
  private var keyedStates: [AnyHashable: Any] = [:]
  private let lock = NSLock()

  public init() {}

  /// Register a state value of type T.
  /// If state of this type already exists, it will be replaced.
  @discardableResult
  public func manage<T>(_ state: T) -> Self {
    lock.lock()
    defer { lock.unlock() }
    states[ObjectIdentifier(T.self)] = state
    return self
  }

  /// Get state of type T.
  /// Returns nil if state of this type hasn't been registered.
  public func get<T>() -> T? {
    lock.lock()
    defer { lock.unlock() }
    return states[ObjectIdentifier(T.self)] as? T
  }

  /// Get state of type T, or crash if not registered.
  /// Use this when you're certain the state has been registered.
  public func require<T>() -> T {
    guard let state: T = get() else {
      fatalError("State of type \(T.self) has not been registered. Call manage() first.")
    }
    return state
  }

  /// Check if state of type T has been registered.
  public func has<T>(_: T.Type) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return states[ObjectIdentifier(T.self)] != nil
  }

  /// Remove state of type T.
  @discardableResult
  public func remove<T>(_: T.Type) -> T? {
    lock.lock()
    defer { lock.unlock() }
    return states.removeValue(forKey: ObjectIdentifier(T.self)) as? T
  }

  /// Remove all registered state.
  public func clear() {
    lock.lock()
    defer { lock.unlock() }
    states.removeAll()
    keyedStates.removeAll()
  }

  // MARK: - Keyed State Storage (for plugins)

  /// Register state with a custom hashable key.
  /// Used internally for plugin-scoped state.
  @discardableResult
  internal func manageKeyed<K: Hashable, V>(key: K, value: V) -> Self {
    lock.lock()
    defer { lock.unlock() }
    keyedStates[AnyHashable(key)] = value
    return self
  }

  /// Get state by custom hashable key.
  /// Used internally for plugin-scoped state.
  internal func getKeyed<K: Hashable, V>(key: K) -> V? {
    lock.lock()
    defer { lock.unlock() }
    return keyedStates[AnyHashable(key)] as? V
  }

  /// Check if keyed state exists.
  internal func hasKeyed<K: Hashable>(key: K) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return keyedStates[AnyHashable(key)] != nil
  }

  /// Remove keyed state.
  @discardableResult
  internal func removeKeyed<K: Hashable, V>(key: K) -> V? {
    lock.lock()
    defer { lock.unlock() }
    return keyedStates.removeValue(forKey: AnyHashable(key)) as? V
  }
}

// MARK: - State Wrapper

/// A wrapper that provides access to managed state of type T.
/// Similar to Tauri's `State<'_, T>` parameter in commands.
@propertyWrapper
public struct ManagedState<T> {
  private let container: StateContainer

  public init(_ container: StateContainer) {
    self.container = container
  }

  public var wrappedValue: T {
    container.require()
  }

  public var projectedValue: T? {
    container.get()
  }
}

// MARK: - Convenience Extensions

public extension StateContainer {
  /// Register multiple states at once using a builder pattern.
  static func build(_ builder: (StateContainer) -> Void) -> StateContainer {
    let container = StateContainer()
    builder(container)
    return container
  }
}

// MARK: - State Protocol

/// Protocol for types that can provide access to managed state.
public protocol StateProvider: Sendable {
  /// The state container
  var stateContainer: StateContainer { get }
}

public extension StateProvider {
  /// Get state of type T.
  func state<T>() -> T? {
    stateContainer.get()
  }

  /// Get state of type T, or crash if not registered.
  func requireState<T>() -> T {
    stateContainer.require()
  }

  /// Register a state value.
  @discardableResult
  func manage<T>(_ state: T) -> Self {
    stateContainer.manage(state)
    return self
  }
}
