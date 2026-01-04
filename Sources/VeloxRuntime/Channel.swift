// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Channel

/// A channel for streaming data from backend to frontend.
///
/// Channels provide fast, ordered data delivery optimized for streaming operations
/// like download progress, file transfers, and real-time updates.
///
/// Usage in command handlers:
/// ```swift
/// registry.register("download") { ctx in
///   guard let channel: Channel<DownloadEvent> = ctx.channel("onProgress") else {
///     return .err("Missing onProgress channel")
///   }
///
///   // Send progress updates
///   channel.send(.started(url: url, size: 1000))
///   channel.send(.progress(bytes: 500))
///   channel.send(.finished)
///
///   return .ok
/// }
/// ```
public final class Channel<T: Encodable & Sendable>: @unchecked Sendable {
  /// The unique channel identifier
  public let id: String

  /// The webview handle for sending messages
  private let webview: WebviewHandle?

  /// Callback function name on the frontend
  private let callbackName: String

  /// Whether the channel has been closed
  private var isClosed = false
  private let lock = NSLock()

  /// Message sequence number for ordering
  private var sequenceNumber: UInt64 = 0

  /// Create a channel with an identifier and webview handle
  public init(id: String, webview: WebviewHandle?, callbackName: String = "__VELOX_CHANNEL_CALLBACK__") {
    self.id = id
    self.webview = webview
    self.callbackName = callbackName
  }

  /// Send a message through the channel
  ///
  /// - Parameter message: The message to send (must be Encodable)
  /// - Returns: true if the message was sent, false if the channel is closed or send failed
  @discardableResult
  public func send(_ message: T) -> Bool {
    lock.lock()
    guard !isClosed else {
      lock.unlock()
      return false
    }
    let seq = sequenceNumber
    sequenceNumber += 1
    lock.unlock()

    guard let webview = webview else {
      return false
    }

    // Encode the message
    let encoder = JSONEncoder()
    guard let messageData = try? encoder.encode(message),
          let messageJSON = String(data: messageData, encoding: .utf8)
    else {
      return false
    }

    // Create the callback invocation
    let script = """
      (function() {
        if (typeof \(callbackName) === 'function') {
          \(callbackName)('\(id)', \(seq), \(messageJSON));
        } else if (typeof window.__veloxChannels !== 'undefined' && window.__veloxChannels['\(id)']) {
          window.__veloxChannels['\(id)'].receive(\(seq), \(messageJSON));
        }
      })();
      """

    return webview.evaluate(script: script)
  }

  /// Close the channel, preventing further messages
  public func close() {
    lock.lock()
    isClosed = true
    lock.unlock()

    // Notify frontend that channel is closed
    _ = webview?.evaluate(script: """
      (function() {
        if (typeof window.__veloxChannels !== 'undefined' && window.__veloxChannels['\(id)']) {
          window.__veloxChannels['\(id)'].close();
          delete window.__veloxChannels['\(id)'];
        }
      })();
      """)
  }

  /// Check if the channel is closed
  public var closed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isClosed
  }
}

// MARK: - Channel Reference

/// A lightweight reference to a channel, used for decoding from frontend requests.
/// This is what gets deserialized from the `{ "__channelId": "..." }` format.
public struct ChannelRef: Codable, Sendable, Equatable {
  /// The channel identifier
  public let channelId: String

  enum CodingKeys: String, CodingKey {
    case channelId = "__channelId"
  }

  public init(channelId: String) {
    self.channelId = channelId
  }
}

// MARK: - Channel Registry

/// A thread-safe registry for managing active channels within a command context.
///
/// The registry tracks channels by their unique identifiers and provides
/// type-safe retrieval and lifecycle management.
///
/// Example:
/// ```swift
/// let registry = ChannelRegistry()
/// let channel = Channel<ProgressEvent>(id: "ch_123", webview: handle)
/// registry.register(channel)
///
/// // Later, retrieve by ID
/// if let ch = registry.get("ch_123", as: ProgressEvent.self) {
///   ch.send(ProgressEvent(current: 50, total: 100))
/// }
/// ```
public final class ChannelRegistry: @unchecked Sendable {
  private var channels: [String: Any] = [:]
  private let lock = NSLock()

  /// Create a new empty channel registry
  public init() {}

  /// Register a channel with the registry.
  ///
  /// - Parameter channel: The channel to register
  public func register<T: Encodable & Sendable>(_ channel: Channel<T>) {
    lock.lock()
    defer { lock.unlock() }
    channels[channel.id] = channel
  }

  /// Retrieve a channel by its unique identifier.
  ///
  /// - Parameters:
  ///   - id: The channel identifier
  ///   - type: The event type the channel sends
  /// - Returns: The channel if found and type matches, nil otherwise
  public func get<T: Encodable & Sendable>(_ id: String, as type: T.Type) -> Channel<T>? {
    lock.lock()
    defer { lock.unlock() }
    return channels[id] as? Channel<T>
  }

  /// Remove a channel from the registry without closing it.
  ///
  /// - Parameter id: The channel identifier to remove
  public func remove(_ id: String) {
    lock.lock()
    defer { lock.unlock() }
    channels.removeValue(forKey: id)
  }

  /// Close all registered channels and clear the registry.
  ///
  /// This is typically called during cleanup when a webview is destroyed.
  public func closeAll() {
    lock.lock()
    let allChannels = channels
    channels.removeAll()
    lock.unlock()

    // Close each channel
    for (_, channel) in allChannels {
      if let closable = channel as? ChannelClosable {
        closable.closeChannel()
      }
    }
  }
}

/// Protocol for closing channels (type-erased)
private protocol ChannelClosable {
  func closeChannel()
}

extension Channel: ChannelClosable {
  func closeChannel() {
    close()
  }
}

// MARK: - CommandContext Channel Extensions

public extension CommandContext {
  /// Extract a channel reference from the request arguments
  ///
  /// - Parameter key: The argument key containing the channel reference
  /// - Returns: A Channel if the argument contains a valid channel reference
  func channel<T: Encodable & Sendable>(_ key: String, as type: T.Type = T.self) -> Channel<T>? {
    let args = decodeArgs()

    // Check if the argument is a channel reference
    guard let channelData = args[key] as? [String: Any],
          let channelId = channelData["__channelId"] as? String
    else {
      return nil
    }

    // Create a channel with the webview handle
    return Channel<T>(id: channelId, webview: webview)
  }

  /// Check if an argument is a channel reference
  func hasChannel(_ key: String) -> Bool {
    let args = decodeArgs()
    guard let channelData = args[key] as? [String: Any] else {
      return false
    }
    return channelData["__channelId"] != nil
  }
}

// MARK: - Frontend JavaScript API

/// JavaScript code that implements the frontend Channel API.
///
/// This script is automatically injected into webviews and provides the `VeloxChannel` class
/// that frontend code uses to create channels for streaming data from the backend.
///
/// Frontend usage:
/// ```javascript
/// const channel = new VeloxChannel();
/// channel.onmessage = (msg) => console.log('Received:', msg);
/// channel.onclose = () => console.log('Channel closed');
///
/// // Pass channel to backend command
/// await invoke('download', { url: 'https://...', onProgress: channel });
/// ```
///
/// The channel automatically handles:
/// - Unique ID generation
/// - Message ordering (buffering out-of-order messages)
/// - JSON serialization for IPC
/// - Cleanup on close
public let channelFrontendScript = """
(function() {
  // Channel storage
  window.__veloxChannels = window.__veloxChannels || {};

  // Channel class
  class Channel {
    constructor() {
      this.id = 'ch_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
      this.onmessage = null;
      this.onclose = null;
      this._buffer = [];
      this._nextSeq = 0;
      this._closed = false;

      // Register globally
      window.__veloxChannels[this.id] = this;
    }

    // Receive a message (called by backend)
    receive(seq, data) {
      if (this._closed) return;

      // Buffer for out-of-order messages
      this._buffer.push({ seq, data });
      this._buffer.sort((a, b) => a.seq - b.seq);

      // Deliver in-order messages
      while (this._buffer.length > 0 && this._buffer[0].seq === this._nextSeq) {
        const msg = this._buffer.shift();
        this._nextSeq++;
        if (this.onmessage) {
          try {
            this.onmessage(msg.data);
          } catch (e) {
            console.error('Channel message handler error:', e);
          }
        }
      }
    }

    // Close the channel
    close() {
      if (this._closed) return;
      this._closed = true;
      delete window.__veloxChannels[this.id];
      if (this.onclose) {
        try {
          this.onclose();
        } catch (e) {
          console.error('Channel close handler error:', e);
        }
      }
    }

    // Check if closed
    get closed() {
      return this._closed;
    }

    // Serialize for IPC (only send the ID)
    toJSON() {
      return { __channelId: this.id };
    }
  }

  // Export to window
  window.VeloxChannel = Channel;

  // Also export as part of Velox namespace if it exists
  if (typeof window.Velox !== 'undefined') {
    window.Velox.Channel = Channel;
  }
})();
"""

// MARK: - Common Channel Event Types

/// A progress event for streaming operations like file transfers or long-running tasks.
///
/// Use this struct to report progress updates through a channel:
/// ```swift
/// let channel: Channel<ProgressEvent> = ctx.channel("onProgress")!
/// for i in 0..<100 {
///   channel.send(ProgressEvent(current: UInt64(i), total: 100, message: "Processing..."))
/// }
/// ```
///
/// On the frontend, the event is received as:
/// ```javascript
/// channel.onmessage = (event) => {
///   console.log(`${event.current}/${event.total}: ${event.message}`);
/// };
/// ```
public struct ProgressEvent: Codable, Sendable {
  /// Current progress value (e.g., bytes transferred, items processed)
  public let current: UInt64

  /// Total expected value, if known (e.g., total bytes, total items)
  public let total: UInt64?

  /// Optional human-readable status message
  public let message: String?

  /// Create a progress event.
  ///
  /// - Parameters:
  ///   - current: Current progress value
  ///   - total: Total expected value (optional)
  ///   - message: Human-readable status message (optional)
  public init(current: UInt64, total: UInt64? = nil, message: String? = nil) {
    self.current = current
    self.total = total
    self.message = message
  }

  /// Calculate progress percentage (0-100).
  ///
  /// - Returns: Percentage if total is known and > 0, nil otherwise
  public var percentage: Double? {
    guard let total = total, total > 0 else { return nil }
    return Double(current) / Double(total) * 100.0
  }
}

/// Event type for file download operations with progress tracking.
///
/// Use this enum to stream download status through a channel:
/// ```swift
/// let channel: Channel<DownloadEvent> = ctx.channel("onProgress")!
///
/// // Signal download started
/// channel.send(.started(url: url, contentLength: fileSize))
///
/// // Report progress
/// channel.send(.progress(bytesReceived: downloaded, totalBytes: fileSize))
///
/// // Signal completion or failure
/// channel.send(.finished(path: localPath))
/// // or: channel.send(.failed(error: "Network error"))
/// ```
///
/// On the frontend:
/// ```javascript
/// channel.onmessage = (event) => {
///   switch (event.event) {
///     case 'started': console.log(`Downloading ${event.data.url}`); break;
///     case 'progress': updateProgressBar(event.data.bytesReceived, event.data.totalBytes); break;
///     case 'finished': console.log(`Saved to ${event.data.path}`); break;
///     case 'failed': console.error(event.data.error); break;
///   }
/// };
/// ```
public enum DownloadEvent: Codable, Sendable {
  /// Download has started
  case started(url: String, contentLength: UInt64?)
  /// Progress update with bytes received
  case progress(bytesReceived: UInt64, totalBytes: UInt64?)
  /// Download completed successfully
  case finished(path: String)
  /// Download failed with error message
  case failed(error: String)

  enum CodingKeys: String, CodingKey {
    case event
    case data
  }

  enum EventType: String, Codable {
    case started
    case progress
    case finished
    case failed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let eventType = try container.decode(EventType.self, forKey: .event)

    switch eventType {
    case .started:
      var dataContainer = try container.nestedContainer(keyedBy: StartedKeys.self, forKey: .data)
      let url = try dataContainer.decode(String.self, forKey: .url)
      let contentLength = try dataContainer.decodeIfPresent(UInt64.self, forKey: .contentLength)
      self = .started(url: url, contentLength: contentLength)
    case .progress:
      var dataContainer = try container.nestedContainer(keyedBy: ProgressKeys.self, forKey: .data)
      let bytesReceived = try dataContainer.decode(UInt64.self, forKey: .bytesReceived)
      let totalBytes = try dataContainer.decodeIfPresent(UInt64.self, forKey: .totalBytes)
      self = .progress(bytesReceived: bytesReceived, totalBytes: totalBytes)
    case .finished:
      var dataContainer = try container.nestedContainer(keyedBy: FinishedKeys.self, forKey: .data)
      let path = try dataContainer.decode(String.self, forKey: .path)
      self = .finished(path: path)
    case .failed:
      var dataContainer = try container.nestedContainer(keyedBy: FailedKeys.self, forKey: .data)
      let error = try dataContainer.decode(String.self, forKey: .error)
      self = .failed(error: error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .started(let url, let contentLength):
      try container.encode(EventType.started, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: StartedKeys.self, forKey: .data)
      try dataContainer.encode(url, forKey: .url)
      try dataContainer.encodeIfPresent(contentLength, forKey: .contentLength)
    case .progress(let bytesReceived, let totalBytes):
      try container.encode(EventType.progress, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: ProgressKeys.self, forKey: .data)
      try dataContainer.encode(bytesReceived, forKey: .bytesReceived)
      try dataContainer.encodeIfPresent(totalBytes, forKey: .totalBytes)
    case .finished(let path):
      try container.encode(EventType.finished, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: FinishedKeys.self, forKey: .data)
      try dataContainer.encode(path, forKey: .path)
    case .failed(let error):
      try container.encode(EventType.failed, forKey: .event)
      var dataContainer = container.nestedContainer(keyedBy: FailedKeys.self, forKey: .data)
      try dataContainer.encode(error, forKey: .error)
    }
  }

  private enum StartedKeys: String, CodingKey { case url, contentLength }
  private enum ProgressKeys: String, CodingKey { case bytesReceived, totalBytes }
  private enum FinishedKeys: String, CodingKey { case path }
  private enum FailedKeys: String, CodingKey { case error }
}

/// A generic stream event for continuous data streaming operations.
///
/// Use this enum when you need to stream arbitrary typed data through a channel:
/// ```swift
/// let channel: Channel<StreamEvent<SensorReading>> = ctx.channel("onData")!
///
/// while isRunning {
///   let reading = sensor.read()
///   channel.send(.data(reading))
/// }
/// channel.send(.end)  // Signal stream completion
/// ```
///
/// On the frontend:
/// ```javascript
/// channel.onmessage = (event) => {
///   if (event.event === 'data') {
///     processReading(event.data);
///   } else if (event.event === 'end') {
///     console.log('Stream ended');
///   } else if (event.event === 'error') {
///     console.error('Stream error:', event.data);
///   }
/// };
/// ```
///
/// The generic parameter `T` defines the payload type for `.data` events.
public enum StreamEvent<T: Codable & Sendable>: Codable, Sendable {
  /// A data payload of type T
  case data(T)
  /// Stream has ended normally
  case end
  /// Stream encountered an error
  case error(String)

  enum CodingKeys: String, CodingKey {
    case event
    case data
  }

  enum EventType: String, Codable {
    case data
    case end
    case error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let eventType = try container.decode(EventType.self, forKey: .event)

    switch eventType {
    case .data:
      let value = try container.decode(T.self, forKey: .data)
      self = .data(value)
    case .end:
      self = .end
    case .error:
      let message = try container.decode(String.self, forKey: .data)
      self = .error(message)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .data(let value):
      try container.encode(EventType.data, forKey: .event)
      try container.encode(value, forKey: .data)
    case .end:
      try container.encode(EventType.end, forKey: .event)
    case .error(let message):
      try container.encode(EventType.error, forKey: .event)
      try container.encode(message, forKey: .data)
    }
  }
}
