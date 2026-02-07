// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

#if os(macOS)
import UserNotifications
#endif

/// Built-in Notification plugin for sending native notifications.
///
/// This plugin exposes the following commands:
/// - `plugin:notification|isPermissionGranted` - Check if notifications are allowed
/// - `plugin:notification|requestPermission` - Request notification permission
/// - `plugin:notification|sendNotification` - Send a notification
///
/// Example frontend usage:
/// ```javascript
/// // Check permission
/// const granted = await invoke('plugin:notification|isPermissionGranted');
///
/// // Request permission if needed
/// if (!granted) {
///   const permission = await invoke('plugin:notification|requestPermission');
/// }
///
/// // Send notification
/// await invoke('plugin:notification|sendNotification', {
///   title: 'Hello',
///   body: 'This is a notification',
///   icon: 'path/to/icon.png'
/// });
/// ```
public final class NotificationPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "notification"

  public init() {}

  #if os(macOS)
  private func notificationCenter() -> UNUserNotificationCenter? {
    // UNUserNotificationCenter requires a valid app bundle; skip when running from a CLI build dir.
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      return nil
    }
    if Thread.isMainThread {
      return UNUserNotificationCenter.current()
    }
    var center: UNUserNotificationCenter?
    DispatchQueue.main.sync {
      center = UNUserNotificationCenter.current()
    }
    return center
  }

  private func notificationCenterOrThrow() throws -> UNUserNotificationCenter {
    guard let center = notificationCenter() else {
      throw CommandError(
        code: "NotificationsUnavailable",
        message: "Notifications require a bundled .app. Current bundle: \(Bundle.main.bundleURL.path)"
      )
    }
    return center
  }
  #endif

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Check if permission is granted
    commands.register("isPermissionGranted", returning: Bool.self) { _ in
      #if os(macOS)
      let semaphore = DispatchSemaphore(value: 0)
      var result = false
      let center = try self.notificationCenterOrThrow()
      center.getNotificationSettings { settings in
        result = settings.authorizationStatus == .authorized
        semaphore.signal()
      }
      semaphore.wait()
      return result
      #else
      return false
      #endif
    }

    // Request permission
    commands.register("requestPermission", returning: String.self) { _ in
      #if os(macOS)
      let semaphore = DispatchSemaphore(value: 0)
      var result = "denied"
      let center = try self.notificationCenterOrThrow()
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        result = granted ? "granted" : "denied"
        semaphore.signal()
      }
      semaphore.wait()
      return result
      #else
      return "denied"
      #endif
    }

    // Send notification
    commands.register("sendNotification", args: NotificationArgs.self, returning: Bool.self) { args, _ in
      #if os(macOS)
      let content = UNMutableNotificationContent()
      content.title = args.title
      if let body = args.body {
        content.body = body
      }
      if let sound = args.sound {
        if sound == "default" {
          content.sound = .default
        } else {
          content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        }
      }

      let request = UNNotificationRequest(
        identifier: args.id ?? UUID().uuidString,
        content: content,
        trigger: nil
      )

      let semaphore = DispatchSemaphore(value: 0)
      var result = false
      let center = try self.notificationCenterOrThrow()
      center.add(request) { error in
        result = error == nil
        semaphore.signal()
      }
      semaphore.wait()
      return result
      #else
      return false
      #endif
    }

    // Remove pending notifications
    commands.register("removeAllPending", returning: EmptyResponse.self) { _ in
      #if os(macOS)
      let center = try self.notificationCenterOrThrow()
      center.removeAllPendingNotificationRequests()
      #endif
      return EmptyResponse()
    }

    // Remove delivered notifications
    commands.register("removeAllDelivered", returning: EmptyResponse.self) { _ in
      #if os(macOS)
      let center = try self.notificationCenterOrThrow()
      center.removeAllDeliveredNotifications()
      #endif
      return EmptyResponse()
    }
  }

  // MARK: - Argument Types

  struct NotificationArgs: Codable, Sendable {
    var id: String?
    let title: String
    var body: String?
    var icon: String?
    var sound: String?
  }

  struct EmptyResponse: Codable, Sendable {}
}
