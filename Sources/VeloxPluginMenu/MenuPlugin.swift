// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime
import VeloxRuntimeWry

#if os(macOS)
public final class MenuPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "menu"

  private var menuEventToken: UUID?
  private var state: MenuState?

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let registry: ResourceRegistry = context.stateContainer.get() ?? {
      let registry = ResourceRegistry()
      context.stateContainer.manage(registry)
      return registry
    }()

    let menuState = MenuState(
      registry: registry,
      eventManager: context.eventEmitter as? VeloxEventManager,
      config: context.config
    )
    state = menuState

    let token = MenuEventMonitor.shared.addHandler { [weak menuState] menuId in
      menuState?.channels.send(menuId: menuId)
    }
    menuEventToken = token
    menuState.menuEventToken = token

    let commands = context.commands(for: name)

    commands.register("new") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleNew(context: context, state: state)
    }

    commands.register("append") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleAppend(context: context, state: state)
    }

    commands.register("prepend") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handlePrepend(context: context, state: state)
    }

    commands.register("insert") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleInsert(context: context, state: state)
    }

    commands.register("remove") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleRemove(context: context, state: state)
    }

    commands.register("remove_at") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleRemoveAt(context: context, state: state)
    }

    commands.register("items") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleItems(context: context, state: state)
    }

    commands.register("get") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleGet(context: context, state: state)
    }

    commands.register("popup") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handlePopup(context: context, state: state)
    }

    commands.register("create_default") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleCreateDefault(context: context, state: state)
    }

    commands.register("set_as_app_menu") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetAsAppMenu(context: context, state: state)
    }

    commands.register("set_as_window_menu") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetAsWindowMenu(context: context, state: state)
    }

    commands.register("text") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleText(context: context, state: state)
    }

    commands.register("set_text") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetText(context: context, state: state)
    }

    commands.register("is_enabled") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleIsEnabled(context: context, state: state)
    }

    commands.register("set_enabled") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetEnabled(context: context, state: state)
    }

    commands.register("set_accelerator") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetAccelerator(context: context, state: state)
    }

    commands.register("set_as_windows_menu_for_nsapp") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetAsWindowsMenuForNSApp(context: context, state: state)
    }

    commands.register("set_as_help_menu_for_nsapp") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetAsHelpMenuForNSApp(context: context, state: state)
    }

    commands.register("is_checked") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleIsChecked(context: context, state: state)
    }

    commands.register("set_checked") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetChecked(context: context, state: state)
    }

    commands.register("set_icon") { [weak self] context in
      guard let state = self?.state else {
        return .err(code: "MenuError", message: "Menu state not available")
      }
      return Self.handleSetIcon(context: context, state: state)
    }
  }

  public func onDrop() {
    if let token = menuEventToken {
      MenuEventMonitor.shared.removeHandler(token)
    }
    state?.channels.clear()
    state = nil
  }
}
#else
public final class MenuPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "menu"

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)
    let unsupported: () -> CommandResult = {
      .err(code: "Unsupported", message: "Menu plugin is only supported on macOS")
    }

    commands.register("new") { _ in unsupported() }
    commands.register("append") { _ in unsupported() }
    commands.register("prepend") { _ in unsupported() }
    commands.register("insert") { _ in unsupported() }
    commands.register("remove") { _ in unsupported() }
    commands.register("remove_at") { _ in unsupported() }
    commands.register("items") { _ in unsupported() }
    commands.register("get") { _ in unsupported() }
    commands.register("popup") { _ in unsupported() }
    commands.register("create_default") { _ in unsupported() }
    commands.register("set_as_app_menu") { _ in unsupported() }
    commands.register("set_as_window_menu") { _ in unsupported() }
    commands.register("text") { _ in unsupported() }
    commands.register("set_text") { _ in unsupported() }
    commands.register("is_enabled") { _ in unsupported() }
    commands.register("set_enabled") { _ in unsupported() }
    commands.register("set_accelerator") { _ in unsupported() }
    commands.register("set_as_windows_menu_for_nsapp") { _ in unsupported() }
    commands.register("set_as_help_menu_for_nsapp") { _ in unsupported() }
    commands.register("is_checked") { _ in unsupported() }
    commands.register("set_checked") { _ in unsupported() }
    commands.register("set_icon") { _ in unsupported() }
  }
}
#endif

#if os(macOS)
private final class MenuState: @unchecked Sendable {
  let registry: ResourceRegistry
  let channels = MenuChannels()
  weak var eventManager: VeloxEventManager?
  let config: VeloxConfig
  var menuEventToken: UUID?

  private let lock = NSLock()
  private var appMenuRid: Int?
  private var windowMenus: [String: Int] = [:]

  init(registry: ResourceRegistry, eventManager: VeloxEventManager?, config: VeloxConfig) {
    self.registry = registry
    self.eventManager = eventManager
    self.config = config
  }

  func setAppMenu(rid: Int?) -> MenuDescriptor? {
    lock.lock()
    let previous = appMenuRid
    appMenuRid = rid
    lock.unlock()

    guard let previous,
          let resource = registry.get(previous, as: MenuResource.self)
    else {
      return nil
    }
    return MenuDescriptor(rid: resource.rid, id: resource.id)
  }

  func setWindowMenu(label: String, rid: Int?) -> MenuDescriptor? {
    lock.lock()
    let previous = windowMenus[label]
    if let rid {
      windowMenus[label] = rid
    } else {
      windowMenus.removeValue(forKey: label)
    }
    lock.unlock()

    guard let previous,
          let resource = registry.get(previous, as: MenuResource.self)
    else {
      return nil
    }
    return MenuDescriptor(rid: resource.rid, id: resource.id)
  }
}

private final class MenuChannels: @unchecked Sendable {
  private var channels: [String: Channel<String>] = [:]
  private let lock = NSLock()

  func register(menuId: String, channel: Channel<String>) {
    lock.lock()
    channels[menuId] = channel
    lock.unlock()
  }

  func remove(menuId: String) {
    lock.lock()
    channels.removeValue(forKey: menuId)
    lock.unlock()
  }

  func send(menuId: String) {
    lock.lock()
    let channel = channels[menuId]
    lock.unlock()
    _ = channel?.send(menuId)
  }

  func clear() {
    lock.lock()
    channels.removeAll()
    lock.unlock()
  }
}

private enum MenuItemKind: String, Codable {
  case menu = "Menu"
  case menuItem = "MenuItem"
  case predefined = "Predefined"
  case submenu = "Submenu"
  case check = "Check"
  case icon = "Icon"
}

private struct MenuDescriptor: Encodable, Sendable {
  let rid: Int
  let id: String

  func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(rid)
    try container.encode(id)
  }
}

private struct MenuItemDescriptor: Encodable, Sendable {
  let rid: Int
  let id: String
  let kind: MenuItemKind

  func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(rid)
    try container.encode(id)
    try container.encode(kind.rawValue)
  }
}

private final class MenuResource: @unchecked Sendable {
  var rid: Int = 0
  let id: String
  let kind: MenuItemKind
  let value: AnyObject
  var items: [MenuItemDescriptor]

  init(id: String, kind: MenuItemKind, value: AnyObject, items: [MenuItemDescriptor] = []) {
    self.id = id
    self.kind = kind
    self.value = value
    self.items = items
  }

  var descriptor: MenuItemDescriptor {
    MenuItemDescriptor(rid: rid, id: id, kind: kind)
  }
}

private enum MenuItemPayload {
  case existing(rid: Int, kind: MenuItemKind)
  case menuItem(MenuItemOptions)
  case check(CheckItemOptions)
  case icon(IconItemOptions)
  case predefined(PredefinedItemOptions)
  case submenu(SubmenuOptions)
}

private struct MenuItemOptions {
  let handler: Channel<String>?
  let id: String?
  let text: String
  let enabled: Bool
  let accelerator: String?
}

private struct CheckItemOptions {
  let handler: Channel<String>?
  let id: String?
  let text: String
  let enabled: Bool
  let checked: Bool
  let accelerator: String?
}

private struct IconItemOptions {
  let handler: Channel<String>?
  let id: String?
  let text: String
  let enabled: Bool
  let accelerator: String?
  let nativeIcon: String
}

private struct PredefinedItemOptions {
  let item: VeloxRuntimeWry.PredefinedMenuItem.Item
  let text: String?
  let aboutMetadata: VeloxRuntimeWry.PredefinedMenuItem.AboutMetadata?
}

private struct SubmenuOptions {
  let id: String?
  let text: String
  let enabled: Bool
  let items: [MenuItemPayload]
  let nativeIcon: String?
}

private struct MenuItemAttachment {
  let resource: MenuResource
  let descriptor: MenuItemDescriptor
}

private func parseMenuItemKind(_ value: Any?) -> MenuItemKind? {
  guard let raw = value as? String else { return nil }
  return MenuItemKind(rawValue: raw)
}

private func parseBool(_ value: Any?, defaultValue: Bool) -> Bool {
  value as? Bool ?? defaultValue
}

private func parseString(_ value: Any?) -> String? {
  value as? String
}

private func parseIcon(_ value: Any?) -> String? {
  value as? String
}

private func parsePosition(_ value: Any?) -> (x: Double, y: Double, isLogical: Bool)? {
  guard let dict = value as? [String: Any] else { return nil }
  if let logical = dict["Logical"] as? [String: Any] {
    let x = logical["x"] as? Double ?? 0
    let y = logical["y"] as? Double ?? 0
    return (x, y, true)
  }
  if let physical = dict["Physical"] as? [String: Any] {
    let x = physical["x"] as? Double ?? 0
    let y = physical["y"] as? Double ?? 0
    return (x, y, false)
  }
  if let x = dict["x"] as? Double, let y = dict["y"] as? Double {
    return (x, y, true)
  }
  return nil
}

private func parseAboutMetadata(_ value: Any?) -> VeloxRuntimeWry.PredefinedMenuItem.AboutMetadata? {
  guard let dict = value as? [String: Any] else { return nil }
  return VeloxRuntimeWry.PredefinedMenuItem.AboutMetadata(
    name: dict["name"] as? String,
    version: dict["version"] as? String,
    shortVersion: dict["shortVersion"] as? String,
    authors: dict["authors"] as? [String],
    comments: dict["comments"] as? String,
    copyright: dict["copyright"] as? String,
    license: dict["license"] as? String,
    website: dict["website"] as? String,
    websiteLabel: dict["websiteLabel"] as? String,
    credits: dict["credits"] as? String
  )
}

private func parsePredefinedItem(_ value: Any?) -> PredefinedItemOptions? {
  if let raw = value as? String, let item = VeloxRuntimeWry.PredefinedMenuItem.Item(rawValue: raw) {
    return PredefinedItemOptions(item: item, text: nil, aboutMetadata: nil)
  }
  guard let dict = value as? [String: Any] else { return nil }
  for (key, val) in dict {
    if key == "About" {
      return PredefinedItemOptions(item: .about, text: nil, aboutMetadata: parseAboutMetadata(val))
    }
    if let item = VeloxRuntimeWry.PredefinedMenuItem.Item(rawValue: key) {
      return PredefinedItemOptions(item: item, text: nil, aboutMetadata: nil)
    }
  }
  return nil
}

private func parseChannel(_ value: Any?, context: CommandContext) -> Channel<String>? {
  guard let webview = context.webview else { return nil }
  if let dict = value as? [String: Any], let channelId = dict["__channelId"] as? String {
    return Channel<String>(id: channelId, webview: webview)
  }
  if let channelString = value as? String, channelString.hasPrefix("__CHANNEL__:") {
    let channelId = String(channelString.dropFirst("__CHANNEL__:".count))
    return Channel<String>(id: channelId, webview: webview, callbackStyle: .tauri)
  }
  return nil
}

private func parseMenuItemPayload(
  _ value: Any,
  context: CommandContext
) -> MenuItemPayload? {
  if let array = value as? [Any], array.count >= 2 {
    let rid = array[0] as? Int
    let kind = parseMenuItemKind(array[1])
    if let rid, let kind {
      return .existing(rid: rid, kind: kind)
    }
  }

  guard let dict = value as? [String: Any] else { return nil }

  if let item = dict["item"] {
    let predefined = parsePredefinedItem(item)
    let text = dict["text"] as? String
    if let predefined {
      return .predefined(
        PredefinedItemOptions(
          item: predefined.item,
          text: text,
          aboutMetadata: predefined.aboutMetadata
        )
      )
    }
  }

  if let items = dict["items"] as? [Any] {
    let submenuItems = items.compactMap { parseMenuItemPayload($0, context: context) }
    return .submenu(
      SubmenuOptions(
        id: dict["id"] as? String,
        text: dict["text"] as? String ?? "",
        enabled: parseBool(dict["enabled"], defaultValue: true),
        items: submenuItems,
        nativeIcon: parseIcon(dict["icon"])
      )
    )
  }

  if dict["checked"] != nil {
    return .check(
      CheckItemOptions(
        handler: parseChannel(dict["handler"], context: context) ?? parseChannel(dict["action"], context: context),
        id: dict["id"] as? String,
        text: dict["text"] as? String ?? "",
        enabled: parseBool(dict["enabled"], defaultValue: true),
        checked: parseBool(dict["checked"], defaultValue: false),
        accelerator: dict["accelerator"] as? String
      )
    )
  }

  if let icon = parseIcon(dict["icon"]) {
    return .icon(
      IconItemOptions(
        handler: parseChannel(dict["handler"], context: context) ?? parseChannel(dict["action"], context: context),
        id: dict["id"] as? String,
        text: dict["text"] as? String ?? "",
        enabled: parseBool(dict["enabled"], defaultValue: true),
        accelerator: dict["accelerator"] as? String,
        nativeIcon: icon
      )
    )
  }

  return .menuItem(
    MenuItemOptions(
      handler: parseChannel(dict["handler"], context: context) ?? parseChannel(dict["action"], context: context),
      id: dict["id"] as? String,
      text: dict["text"] as? String ?? "",
      enabled: parseBool(dict["enabled"], defaultValue: true),
      accelerator: dict["accelerator"] as? String
    )
  )
}

private func registerResource(_ resource: MenuResource, state: MenuState) -> MenuResource {
  let rid = state.registry.add(resource)
  resource.rid = rid
  return resource
}

private func buildItemAttachment(
  payload: MenuItemPayload,
  context: CommandContext,
  state: MenuState
) -> MenuItemAttachment? {
  switch payload {
  case let .existing(rid, kind):
    guard let resource = state.registry.get(rid, as: MenuResource.self), resource.kind == kind else {
      return nil
    }
    return MenuItemAttachment(resource: resource, descriptor: resource.descriptor)

  case let .menuItem(options):
    guard let item = VeloxRuntimeWry.MenuItem(
      identifier: options.id,
      title: options.text,
      isEnabled: options.enabled,
      accelerator: options.accelerator
    ) else {
      return nil
    }
    let resource = registerResource(MenuResource(id: item.identifier, kind: .menuItem, value: item), state: state)
    if let handler = options.handler {
      state.channels.register(menuId: resource.id, channel: handler)
    }
    return MenuItemAttachment(resource: resource, descriptor: resource.descriptor)

  case let .check(options):
    guard let item = VeloxRuntimeWry.CheckMenuItem(
      identifier: options.id,
      title: options.text,
      isEnabled: options.enabled,
      isChecked: options.checked,
      accelerator: options.accelerator
    ) else {
      return nil
    }
    let resource = registerResource(MenuResource(id: item.identifier, kind: .check, value: item), state: state)
    if let handler = options.handler {
      state.channels.register(menuId: resource.id, channel: handler)
    }
    return MenuItemAttachment(resource: resource, descriptor: resource.descriptor)

  case let .icon(options):
    guard let item = VeloxRuntimeWry.IconMenuItem(
      identifier: options.id,
      title: options.text,
      nativeIcon: options.nativeIcon,
      isEnabled: options.enabled,
      accelerator: options.accelerator
    ) else {
      return nil
    }
    let resource = registerResource(MenuResource(id: item.identifier, kind: .icon, value: item), state: state)
    if let handler = options.handler {
      state.channels.register(menuId: resource.id, channel: handler)
    }
    return MenuItemAttachment(resource: resource, descriptor: resource.descriptor)

  case let .predefined(options):
    guard let item = VeloxRuntimeWry.PredefinedMenuItem(
      item: options.item,
      title: options.text,
      aboutMetadata: options.aboutMetadata
    ) else {
      return nil
    }
    let resource = registerResource(MenuResource(id: item.identifier, kind: .predefined, value: item), state: state)
    return MenuItemAttachment(resource: resource, descriptor: resource.descriptor)

  case let .submenu(options):
    guard let submenu = VeloxRuntimeWry.Submenu(
      title: options.text,
      identifier: options.id,
      isEnabled: options.enabled
    ) else {
      return nil
    }
    if let icon = options.nativeIcon {
      _ = submenu.setNativeIcon(icon)
    }
    let submenuResource = registerResource(MenuResource(id: submenu.identifier, kind: .submenu, value: submenu), state: state)

    var descriptors: [MenuItemDescriptor] = []
    for itemPayload in options.items {
      guard let attachment = buildItemAttachment(payload: itemPayload, context: context, state: state) else {
        continue
      }
      let success = applyAppend(to: submenuResource, item: attachment.resource)
      if success {
        descriptors.append(attachment.descriptor)
      }
    }
    submenuResource.items = descriptors
    return MenuItemAttachment(resource: submenuResource, descriptor: submenuResource.descriptor)
  }
}

private func applyAppend(to container: MenuResource, item: MenuResource) -> Bool {
  switch container.kind {
  case .menu:
    guard let menu = container.value as? VeloxRuntimeWry.MenuBar else { return false }
    switch item.kind {
    case .submenu:
      return menu.append(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return menu.append(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return menu.append(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return menu.append(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return menu.append(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  case .submenu:
    guard let submenu = container.value as? VeloxRuntimeWry.Submenu else { return false }
    switch item.kind {
    case .submenu:
      return submenu.append(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return submenu.append(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return submenu.append(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return submenu.append(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return submenu.append(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  default:
    return false
  }
}

private func applyPrepend(to container: MenuResource, item: MenuResource) -> Bool {
  switch container.kind {
  case .menu:
    guard let menu = container.value as? VeloxRuntimeWry.MenuBar else { return false }
    switch item.kind {
    case .submenu:
      return menu.prepend(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return menu.prepend(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return menu.prepend(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return menu.prepend(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return menu.prepend(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  case .submenu:
    guard let submenu = container.value as? VeloxRuntimeWry.Submenu else { return false }
    switch item.kind {
    case .submenu:
      return submenu.prepend(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return submenu.prepend(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return submenu.prepend(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return submenu.prepend(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return submenu.prepend(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  default:
    return false
  }
}

private func applyInsert(to container: MenuResource, item: MenuResource, position: Int) -> Bool {
  switch container.kind {
  case .menu:
    guard let menu = container.value as? VeloxRuntimeWry.MenuBar else { return false }
    switch item.kind {
    case .submenu:
      return menu.insert(item.value as! VeloxRuntimeWry.Submenu, position: position)
    case .menuItem:
      return menu.insert(item.value as! VeloxRuntimeWry.MenuItem, position: position)
    case .check:
      return menu.insert(item.value as! VeloxRuntimeWry.CheckMenuItem, position: position)
    case .icon:
      return menu.insert(item.value as! VeloxRuntimeWry.IconMenuItem, position: position)
    case .predefined:
      return menu.insert(item.value as! VeloxRuntimeWry.PredefinedMenuItem, position: position)
    case .menu:
      return false
    }

  case .submenu:
    guard let submenu = container.value as? VeloxRuntimeWry.Submenu else { return false }
    switch item.kind {
    case .submenu:
      return submenu.insert(item.value as! VeloxRuntimeWry.Submenu, position: position)
    case .menuItem:
      return submenu.insert(item.value as! VeloxRuntimeWry.MenuItem, position: position)
    case .check:
      return submenu.insert(item.value as! VeloxRuntimeWry.CheckMenuItem, position: position)
    case .icon:
      return submenu.insert(item.value as! VeloxRuntimeWry.IconMenuItem, position: position)
    case .predefined:
      return submenu.insert(item.value as! VeloxRuntimeWry.PredefinedMenuItem, position: position)
    case .menu:
      return false
    }

  default:
    return false
  }
}

private func applyRemove(from container: MenuResource, item: MenuResource) -> Bool {
  switch container.kind {
  case .menu:
    guard let menu = container.value as? VeloxRuntimeWry.MenuBar else { return false }
    switch item.kind {
    case .submenu:
      return menu.remove(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return menu.remove(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return menu.remove(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return menu.remove(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return menu.remove(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  case .submenu:
    guard let submenu = container.value as? VeloxRuntimeWry.Submenu else { return false }
    switch item.kind {
    case .submenu:
      return submenu.remove(item.value as! VeloxRuntimeWry.Submenu)
    case .menuItem:
      return submenu.remove(item.value as! VeloxRuntimeWry.MenuItem)
    case .check:
      return submenu.remove(item.value as! VeloxRuntimeWry.CheckMenuItem)
    case .icon:
      return submenu.remove(item.value as! VeloxRuntimeWry.IconMenuItem)
    case .predefined:
      return submenu.remove(item.value as! VeloxRuntimeWry.PredefinedMenuItem)
    case .menu:
      return false
    }

  default:
    return false
  }
}

private extension MenuPlugin {
  static func handleNew(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let kind = parseMenuItemKind(args["kind"]) else {
      return .err(code: "MenuError", message: "Missing or invalid kind")
    }

    let options = args["options"] as? [String: Any] ?? [:]
    let handler = parseChannel(args["handler"], context: context)

    switch kind {
    case .menu:
      guard let menu = VeloxRuntimeWry.MenuBar(identifier: options["id"] as? String) else {
        return .err(code: "MenuError", message: "Failed to create menu")
      }

      let resource = registerResource(MenuResource(id: menu.identifier, kind: .menu, value: menu), state: state)

      var descriptors: [MenuItemDescriptor] = []
      if let items = options["items"] as? [Any] {
        for item in items {
          guard let payload = parseMenuItemPayload(item, context: context),
                let attachment = buildItemAttachment(payload: payload, context: context, state: state)
          else {
            continue
          }
          if applyAppend(to: resource, item: attachment.resource) {
            descriptors.append(attachment.descriptor)
          } else {
            return .err(code: "MenuError", message: "Failed to append menu item")
          }
        }
      }
      resource.items = descriptors
      if let handler {
        state.channels.register(menuId: resource.id, channel: handler)
      }
      return .ok(MenuDescriptor(rid: resource.rid, id: resource.id))

    case .submenu:
      let text = options["text"] as? String ?? ""
      let enabled = parseBool(options["enabled"], defaultValue: true)
      guard let submenu = VeloxRuntimeWry.Submenu(title: text, identifier: options["id"] as? String, isEnabled: enabled) else {
        return .err(code: "MenuError", message: "Failed to create submenu")
      }
      if let icon = parseIcon(options["icon"]) {
        _ = submenu.setNativeIcon(icon)
      }
      let resource = registerResource(MenuResource(id: submenu.identifier, kind: .submenu, value: submenu), state: state)

      var descriptors: [MenuItemDescriptor] = []
      if let items = options["items"] as? [Any] {
        for item in items {
          guard let payload = parseMenuItemPayload(item, context: context),
                let attachment = buildItemAttachment(payload: payload, context: context, state: state)
          else {
            continue
          }
          if applyAppend(to: resource, item: attachment.resource) {
            descriptors.append(attachment.descriptor)
          } else {
            return .err(code: "MenuError", message: "Failed to append submenu item")
          }
        }
      }
      resource.items = descriptors
      if let handler {
        state.channels.register(menuId: resource.id, channel: handler)
      }
      return .ok(MenuDescriptor(rid: resource.rid, id: resource.id))

    case .menuItem:
      let options = MenuItemOptions(
        handler: handler,
        id: options["id"] as? String,
        text: options["text"] as? String ?? "",
        enabled: parseBool(options["enabled"], defaultValue: true),
        accelerator: options["accelerator"] as? String
      )
      guard let attachment = buildItemAttachment(payload: .menuItem(options), context: context, state: state) else {
        return .err(code: "MenuError", message: "Failed to create menu item")
      }
      return .ok(MenuDescriptor(rid: attachment.resource.rid, id: attachment.resource.id))

    case .check:
      let options = CheckItemOptions(
        handler: handler,
        id: options["id"] as? String,
        text: options["text"] as? String ?? "",
        enabled: parseBool(options["enabled"], defaultValue: true),
        checked: parseBool(options["checked"], defaultValue: false),
        accelerator: options["accelerator"] as? String
      )
      guard let attachment = buildItemAttachment(payload: .check(options), context: context, state: state) else {
        return .err(code: "MenuError", message: "Failed to create check menu item")
      }
      return .ok(MenuDescriptor(rid: attachment.resource.rid, id: attachment.resource.id))

    case .icon:
      let nativeIcon = parseIcon(options["icon"]) ?? "User"
      let options = IconItemOptions(
        handler: handler,
        id: options["id"] as? String,
        text: options["text"] as? String ?? "",
        enabled: parseBool(options["enabled"], defaultValue: true),
        accelerator: options["accelerator"] as? String,
        nativeIcon: nativeIcon
      )
      guard let attachment = buildItemAttachment(payload: .icon(options), context: context, state: state) else {
        return .err(code: "MenuError", message: "Failed to create icon menu item")
      }
      return .ok(MenuDescriptor(rid: attachment.resource.rid, id: attachment.resource.id))

    case .predefined:
      guard let itemPayload = parsePredefinedItem(options["item"]) else {
        return .err(code: "MenuError", message: "Missing predefined menu item")
      }
      let options = PredefinedItemOptions(
        item: itemPayload.item,
        text: options["text"] as? String,
        aboutMetadata: itemPayload.aboutMetadata
      )
      guard let attachment = buildItemAttachment(payload: .predefined(options), context: context, state: state) else {
        return .err(code: "MenuError", message: "Failed to create predefined menu item")
      }
      return .ok(MenuDescriptor(rid: attachment.resource.rid, id: attachment.resource.id))
    }
  }

  static func handleAppend(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let items = args["items"] as? [Any]
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    var descriptors: [MenuItemDescriptor] = []
    for item in items {
      guard let payload = parseMenuItemPayload(item, context: context),
            let attachment = buildItemAttachment(payload: payload, context: context, state: state)
      else {
        continue
      }
      if applyAppend(to: container, item: attachment.resource) {
        descriptors.append(attachment.descriptor)
      } else {
        return .err(code: "MenuError", message: "Failed to append menu item")
      }
    }

    container.items.append(contentsOf: descriptors)
    return .ok
  }

  static func handlePrepend(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let items = args["items"] as? [Any]
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    for item in items {
      guard let payload = parseMenuItemPayload(item, context: context),
            let attachment = buildItemAttachment(payload: payload, context: context, state: state)
      else {
        continue
      }
      if applyPrepend(to: container, item: attachment.resource) {
        container.items.insert(attachment.descriptor, at: 0)
      } else {
        return .err(code: "MenuError", message: "Failed to prepend menu item")
      }
    }

    return .ok
  }

  static func handleInsert(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let items = args["items"] as? [Any]
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    let position = args["position"] as? Int ?? 0

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    var insertIndex = max(0, position)
    for item in items {
      guard let payload = parseMenuItemPayload(item, context: context),
            let attachment = buildItemAttachment(payload: payload, context: context, state: state)
      else {
        continue
      }
      if applyInsert(to: container, item: attachment.resource, position: insertIndex) {
        let index = max(0, min(insertIndex, container.items.count))
        container.items.insert(attachment.descriptor, at: index)
        insertIndex += 1
      } else {
        return .err(code: "MenuError", message: "Failed to insert menu item")
      }
    }

    return .ok
  }

  static func handleRemove(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let item = args["item"] as? [Any],
          item.count >= 2
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    let itemRid = item[0] as? Int
    let itemKind = parseMenuItemKind(item[1])
    guard let itemRid, let itemKind else {
      return .err(code: "MenuError", message: "Invalid menu item reference")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind,
          let itemResource = state.registry.get(itemRid, as: MenuResource.self),
          itemResource.kind == itemKind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    if applyRemove(from: container, item: itemResource) {
      container.items.removeAll { $0.rid == itemRid }
      return .ok
    }

    return .err(code: "MenuError", message: "Failed to remove menu item")
  }

  static func handleRemoveAt(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"])
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    let position = args["position"] as? Int ?? 0

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    guard position >= 0, position < container.items.count else {
      return .ok(Optional<MenuItemDescriptor>.none)
    }

    let descriptor = container.items[position]
    guard let itemResource = state.registry.get(descriptor.rid, as: MenuResource.self) else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    let removed = applyRemove(from: container, item: itemResource)
    if removed {
      container.items.remove(at: position)
      return .ok(descriptor)
    }

    return .err(code: "MenuError", message: "Failed to remove menu item")
  }

  static func handleItems(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"])
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    return .ok(container.items)
  }

  static func handleGet(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let id = args["id"] as? String
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    let match = container.items.first { $0.id == id }
    return .ok(match)
  }

  static func handlePopup(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"])
    else {
      return .err(code: "MenuError", message: "Missing arguments")
    }

    guard let container = state.registry.get(rid, as: MenuResource.self),
          container.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    let windowLabel = (args["window"] as? String) ?? context.webviewId
    guard let window = state.eventManager?.window(for: windowLabel) else {
      return .err(code: "MenuError", message: "Window not found")
    }

    let position = parsePosition(args["at"])
    let success: Bool

    switch container.kind {
    case .menu:
      guard let menu = container.value as? VeloxRuntimeWry.MenuBar else {
        return .err(code: "MenuError", message: "Invalid menu")
      }
      success = menu.popup(in: window, at: position)
    case .submenu:
      guard let submenu = container.value as? VeloxRuntimeWry.Submenu else {
        return .err(code: "MenuError", message: "Invalid submenu")
      }
      success = submenu.popup(in: window, at: position)
    default:
      return .err(code: "MenuError", message: "Popup requires menu or submenu")
    }

    return success ? .ok : .err(code: "MenuError", message: "Failed to popup menu")
  }

  static func handleCreateDefault(context: CommandContext, state: MenuState) -> CommandResult {
    let config = state.config
    let productName = config.productName ?? "App"
    let version = config.version
    let authors = config.bundle?.publisher.map { [$0] }

    let aboutMetadata = VeloxRuntimeWry.PredefinedMenuItem.AboutMetadata(
      name: productName,
      version: version,
      authors: authors
    )

    guard let menu = VeloxRuntimeWry.MenuBar() else {
      return .err(code: "MenuError", message: "Failed to create default menu")
    }
    let menuResource = registerResource(MenuResource(id: menu.identifier, kind: .menu, value: menu), state: state)

    guard let appMenu = VeloxRuntimeWry.Submenu(title: productName, identifier: nil, isEnabled: true),
          let fileMenu = VeloxRuntimeWry.Submenu(title: "File", identifier: nil, isEnabled: true),
          let editMenu = VeloxRuntimeWry.Submenu(title: "Edit", identifier: nil, isEnabled: true),
          let viewMenu = VeloxRuntimeWry.Submenu(title: "View", identifier: nil, isEnabled: true),
          let windowMenu = VeloxRuntimeWry.Submenu(title: "Window", identifier: "__tauri_window_menu__", isEnabled: true),
          let helpMenu = VeloxRuntimeWry.Submenu(title: "Help", identifier: "__tauri_help_menu__", isEnabled: true)
    else {
      return .err(code: "MenuError", message: "Failed to create default menu")
    }

    let submenuResources = [
      MenuResource(id: appMenu.identifier, kind: .submenu, value: appMenu),
      MenuResource(id: fileMenu.identifier, kind: .submenu, value: fileMenu),
      MenuResource(id: editMenu.identifier, kind: .submenu, value: editMenu),
      MenuResource(id: viewMenu.identifier, kind: .submenu, value: viewMenu),
      MenuResource(id: windowMenu.identifier, kind: .submenu, value: windowMenu),
      MenuResource(id: helpMenu.identifier, kind: .submenu, value: helpMenu),
    ].map { registerResource($0, state: state) }

    func appendItems(_ items: [MenuItemPayload], to submenuResource: MenuResource) -> Bool {
      var descriptors: [MenuItemDescriptor] = []
      for item in items {
        guard let attachment = buildItemAttachment(payload: item, context: context, state: state) else { continue }
        if applyAppend(to: submenuResource, item: attachment.resource) {
          descriptors.append(attachment.descriptor)
        } else {
          return false
        }
      }
      submenuResource.items = descriptors
      return true
    }

    let appItems: [MenuItemPayload] = [
      .predefined(PredefinedItemOptions(item: .about, text: nil, aboutMetadata: aboutMetadata)),
      .predefined(PredefinedItemOptions(item: .separator, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .services, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .separator, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .hide, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .hideOthers, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .separator, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .quit, text: nil, aboutMetadata: nil)),
    ]

    let fileItems: [MenuItemPayload] = [
      .predefined(PredefinedItemOptions(item: .closeWindow, text: nil, aboutMetadata: nil)),
    ]

    let editItems: [MenuItemPayload] = [
      .predefined(PredefinedItemOptions(item: .undo, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .redo, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .separator, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .cut, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .copy, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .paste, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .selectAll, text: nil, aboutMetadata: nil)),
    ]

    let viewItems: [MenuItemPayload] = [
      .predefined(PredefinedItemOptions(item: .fullscreen, text: nil, aboutMetadata: nil)),
    ]

    let windowItems: [MenuItemPayload] = [
      .predefined(PredefinedItemOptions(item: .minimize, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .maximize, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .separator, text: nil, aboutMetadata: nil)),
      .predefined(PredefinedItemOptions(item: .closeWindow, text: nil, aboutMetadata: nil)),
    ]

    guard appendItems(appItems, to: submenuResources[0]),
          appendItems(fileItems, to: submenuResources[1]),
          appendItems(editItems, to: submenuResources[2]),
          appendItems(viewItems, to: submenuResources[3]),
          appendItems(windowItems, to: submenuResources[4])
    else {
      return .err(code: "MenuError", message: "Failed to build default menu")
    }

    _ = (submenuResources[4].value as? VeloxRuntimeWry.Submenu)?.setAsWindowsMenuForNSApp()
    _ = (submenuResources[5].value as? VeloxRuntimeWry.Submenu)?.setAsHelpMenuForNSApp()

    var descriptors: [MenuItemDescriptor] = []
    for submenuResource in submenuResources {
      if let submenu = submenuResource.value as? VeloxRuntimeWry.Submenu, menu.append(submenu) {
        descriptors.append(submenuResource.descriptor)
      }
    }

    menuResource.items = descriptors

    return .ok(MenuDescriptor(rid: menuResource.rid, id: menuResource.id))
  }

  static func handleSetAsAppMenu(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .menu,
          let menu = resource.value as? VeloxRuntimeWry.MenuBar
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    guard menu.setAsApplicationMenu() else {
      return .err(code: "MenuError", message: "Failed to set app menu")
    }

    let previous = state.setAppMenu(rid: resource.rid)
    return .ok(previous)
  }

  static func handleSetAsWindowMenu(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .menu
    else {
      return .err(code: "MenuError", message: "Menu not found")
    }

    let windowLabel = (args["window"] as? String) ?? context.webviewId
    let previous = state.setWindowMenu(label: windowLabel, rid: resource.rid)
    return .ok(previous)
  }

  static func handleText(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    switch kind {
    case .menuItem:
      return .ok((resource.value as? VeloxRuntimeWry.MenuItem)?.title() ?? "")
    case .check:
      return .ok((resource.value as? VeloxRuntimeWry.CheckMenuItem)?.title() ?? "")
    case .icon:
      return .ok((resource.value as? VeloxRuntimeWry.IconMenuItem)?.title() ?? "")
    case .predefined:
      return .ok((resource.value as? VeloxRuntimeWry.PredefinedMenuItem)?.title() ?? "")
    case .submenu:
      return .ok((resource.value as? VeloxRuntimeWry.Submenu)?.text() ?? "")
    case .menu:
      return .err(code: "MenuError", message: "Menu has no text")
    }
  }

  static func handleSetText(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let text = args["text"] as? String,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    let success: Bool
    switch kind {
    case .menuItem:
      success = (resource.value as? VeloxRuntimeWry.MenuItem)?.setTitle(text) ?? false
    case .check:
      success = (resource.value as? VeloxRuntimeWry.CheckMenuItem)?.setTitle(text) ?? false
    case .icon:
      success = (resource.value as? VeloxRuntimeWry.IconMenuItem)?.setTitle(text) ?? false
    case .predefined:
      success = (resource.value as? VeloxRuntimeWry.PredefinedMenuItem)?.setTitle(text) ?? false
    case .submenu:
      success = (resource.value as? VeloxRuntimeWry.Submenu)?.setText(text) ?? false
    case .menu:
      success = false
    }

    return success ? .ok : .err(code: "MenuError", message: "Failed to set text")
  }

  static func handleIsEnabled(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    switch kind {
    case .menuItem:
      return .ok((resource.value as? VeloxRuntimeWry.MenuItem)?.isEnabled() ?? false)
    case .check:
      return .ok((resource.value as? VeloxRuntimeWry.CheckMenuItem)?.isEnabled() ?? false)
    case .icon:
      return .ok((resource.value as? VeloxRuntimeWry.IconMenuItem)?.isEnabled() ?? false)
    case .submenu:
      return .ok((resource.value as? VeloxRuntimeWry.Submenu)?.isEnabled() ?? false)
    case .predefined:
      return .ok(false)
    case .menu:
      return .err(code: "MenuError", message: "Menu has no enabled state")
    }
  }

  static func handleSetEnabled(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let enabled = args["enabled"] as? Bool,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    let success: Bool
    switch kind {
    case .menuItem:
      success = (resource.value as? VeloxRuntimeWry.MenuItem)?.setEnabled(enabled) ?? false
    case .check:
      success = (resource.value as? VeloxRuntimeWry.CheckMenuItem)?.setEnabled(enabled) ?? false
    case .icon:
      success = (resource.value as? VeloxRuntimeWry.IconMenuItem)?.setEnabled(enabled) ?? false
    case .submenu:
      success = (resource.value as? VeloxRuntimeWry.Submenu)?.setEnabled(enabled) ?? false
    case .predefined:
      success = false
    case .menu:
      success = false
    }

    return success ? .ok : .err(code: "MenuError", message: "Failed to set enabled")
  }

  static func handleSetAccelerator(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    let accelerator = args["accelerator"] as? String
    let success: Bool

    switch kind {
    case .menuItem:
      success = (resource.value as? VeloxRuntimeWry.MenuItem)?.setAccelerator(accelerator) ?? false
    case .check:
      success = (resource.value as? VeloxRuntimeWry.CheckMenuItem)?.setAccelerator(accelerator) ?? false
    case .icon:
      success = (resource.value as? VeloxRuntimeWry.IconMenuItem)?.setAccelerator(accelerator) ?? false
    default:
      success = false
    }

    return success ? .ok : .err(code: "MenuError", message: "Failed to set accelerator")
  }

  static func handleSetAsWindowsMenuForNSApp(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .submenu,
          let submenu = resource.value as? VeloxRuntimeWry.Submenu
    else {
      return .err(code: "MenuError", message: "Submenu not found")
    }

    return submenu.setAsWindowsMenuForNSApp() ? .ok : .err(code: "MenuError", message: "Failed to set windows menu")
  }

  static func handleSetAsHelpMenuForNSApp(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .submenu,
          let submenu = resource.value as? VeloxRuntimeWry.Submenu
    else {
      return .err(code: "MenuError", message: "Submenu not found")
    }

    return submenu.setAsHelpMenuForNSApp() ? .ok : .err(code: "MenuError", message: "Failed to set help menu")
  }

  static func handleIsChecked(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .check,
          let check = resource.value as? VeloxRuntimeWry.CheckMenuItem
    else {
      return .err(code: "MenuError", message: "Check menu item not found")
    }

    return .ok(check.isChecked())
  }

  static func handleSetChecked(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let checked = args["checked"] as? Bool,
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == .check,
          let check = resource.value as? VeloxRuntimeWry.CheckMenuItem
    else {
      return .err(code: "MenuError", message: "Check menu item not found")
    }

    return check.setChecked(checked) ? .ok : .err(code: "MenuError", message: "Failed to set checked")
  }

  static func handleSetIcon(context: CommandContext, state: MenuState) -> CommandResult {
    let args = context.decodeArgs()
    guard let rid = args["rid"] as? Int,
          let kind = parseMenuItemKind(args["kind"]),
          let resource = state.registry.get(rid, as: MenuResource.self),
          resource.kind == kind
    else {
      return .err(code: "MenuError", message: "Menu item not found")
    }

    let icon = parseIcon(args["icon"])
    let success: Bool

    switch kind {
    case .icon:
      success = (resource.value as? VeloxRuntimeWry.IconMenuItem)?.setNativeIcon(icon) ?? false
    case .submenu:
      success = (resource.value as? VeloxRuntimeWry.Submenu)?.setNativeIcon(icon) ?? false
    default:
      success = false
    }

    return success ? .ok : .err(code: "MenuError", message: "Failed to set icon")
  }
}
#endif
