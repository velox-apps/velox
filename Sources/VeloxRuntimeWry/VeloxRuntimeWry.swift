import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import VeloxRuntime
import VeloxRuntimeWryFFI

typealias VeloxCustomProtocolHandlerBridge =
  @convention(c) (
    UnsafePointer<VeloxCustomProtocolRequest>?,
    UnsafeMutablePointer<VeloxCustomProtocolResponse>?,
    UnsafeMutableRawPointer?
  ) -> Bool

typealias VeloxCustomProtocolResponseBridge =
  @convention(c) (UnsafeMutableRawPointer?) -> Void

@_silgen_name("velox_custom_protocol_handler_bridge")
private let velox_custom_protocol_handler_bridge_c: VeloxCustomProtocolHandlerBridge

@_silgen_name("velox_custom_protocol_response_bridge")
private let velox_custom_protocol_response_bridge_c: VeloxCustomProtocolResponseBridge

final class VeloxEventStreamMultiplexer<Value> {
  private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
  private let lock = NSLock()

  func add(_ continuation: AsyncStream<Value>.Continuation) -> UUID {
    let token = UUID()
    lock.lock()
    continuations[token] = continuation
    lock.unlock()
    return token
  }

  func remove(_ token: UUID) {
    lock.lock()
    continuations.removeValue(forKey: token)
    lock.unlock()
  }

  func yield(_ value: Value) {
    lock.lock()
    let snapshots = Array(continuations.values)
    lock.unlock()
    for continuation in snapshots {
      continuation.yield(value)
    }
  }

  func finishAll() {
    lock.lock()
    let snapshots = Array(continuations.values)
    continuations.removeAll()
    lock.unlock()
    for continuation in snapshots {
      continuation.finish()
    }
  }

  var isEmpty: Bool {
    lock.lock()
    let empty = continuations.isEmpty
    lock.unlock()
    return empty
  }
}

/// The Velox runtime implementation backed by Tao (windowing) and Wry (webview).
///
/// This namespace provides Swift wrappers around the Rust FFI for creating
/// desktop applications with native windows and webviews.
///
/// The main types are:
/// - ``EventLoop``: The main event loop for processing window events
/// - ``Window``: A native window that can host webviews
/// - ``Webview``: A web content view for rendering HTML/CSS/JavaScript
/// - ``Runtime``: A higher-level wrapper implementing ``VeloxRuntime``
///
/// Example usage:
/// ```swift
/// let eventLoop = VeloxRuntimeWry.EventLoop()!
/// let window = eventLoop.makeWindow(
///   configuration: .init(width: 800, height: 600, title: "My App")
/// )!
/// let webview = window.makeWebview(url: "https://example.com")
/// eventLoop.run()
/// ```
public enum VeloxRuntimeWry {
  /// Errors that can occur during runtime operations.
  public enum RuntimeError: Swift.Error {
    /// The requested operation is not supported on this platform.
    case unsupported
  }

  /// Version information for the Velox runtime components.
  public struct Version: Sendable, Hashable {
    /// The version of the Velox runtime library.
    public let runtime: String

    /// The version of the underlying webview implementation.
    public let webview: String

    /// Creates a version info instance.
    public init(runtime: String, webview: String) {
      self.runtime = runtime
      self.webview = webview
    }
  }

  /// The canonical module name used when interacting with the Rust side.
  public static var moduleName: String {
    string(from: velox_runtime_wry_library_name())
  }

  /// Version information for the Swift-facing runtime.
  public static var version: Version {
    Version(
      runtime: string(from: velox_runtime_wry_crate_version()),
      webview: string(from: velox_runtime_wry_webview_version())
    )
  }

  /// Control flow hints returned by event loop callbacks.
  ///
  /// These values control the behavior of the event loop after handling an event.
  public enum ControlFlow: Int32, Sendable {
    /// Continue immediately without waiting for new events.
    case poll = 0
    /// Wait for the next event before continuing.
    case wait = 1
    /// Exit the event loop.
    case exit = 2
  }

  /// Configuration for creating a new window.
  public struct WindowConfiguration: Sendable {
    /// Initial width of the window in logical pixels.
    public var width: UInt32
    /// Initial height of the window in logical pixels.
    public var height: UInt32
    /// The window title displayed in the title bar.
    public var title: String

    /// Creates a window configuration.
    ///
    /// - Parameters:
    ///   - width: Initial width in logical pixels (default: 0 for system default).
    ///   - height: Initial height in logical pixels (default: 0 for system default).
    ///   - title: The window title (default: empty string).
    public init(width: UInt32 = 0, height: UInt32 = 0, title: String = "") {
      self.width = width
      self.height = height
      self.title = title
    }
  }

  /// A custom URL protocol handler for intercepting webview requests.
  ///
  /// Custom protocols allow you to serve content from Swift code when the webview
  /// navigates to URLs with your custom scheme.
  ///
  /// Example:
  /// ```swift
  /// let protocol = CustomProtocol(scheme: "app") { request in
  ///   let html = "<html><body>Hello from Swift!</body></html>"
  ///   return CustomProtocol.Response(
  ///     status: 200,
  ///     headers: ["Content-Type": "text/html"],
  ///     body: Data(html.utf8)
  ///   )
  /// }
  /// ```
  public struct CustomProtocol: Sendable {
    /// An incoming request to the custom protocol handler.
    public struct Request: Sendable {
      /// The full URL being requested (e.g., "app://localhost/page.html").
      public let url: String
      /// The HTTP method (GET, POST, etc.).
      public let method: String
      /// Request headers.
      public let headers: [String: String]
      /// The request body data.
      public let body: Data
      /// The identifier of the webview making the request.
      public let webviewIdentifier: String

      /// Creates a request.
      public init(
        url: String,
        method: String,
        headers: [String: String],
        body: Data,
        webviewIdentifier: String
      ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.webviewIdentifier = webviewIdentifier
      }
    }

    /// A response from the custom protocol handler.
    public struct Response: Sendable {
      /// HTTP status code (e.g., 200, 404).
      public var status: Int
      /// Response headers.
      public var headers: [String: String]
      /// The MIME type of the response body.
      public var mimeType: String?
      /// The response body data.
      public var body: Data

      /// Creates a response.
      ///
      /// - Parameters:
      ///   - status: HTTP status code (default: 200).
      ///   - headers: Response headers (default: empty).
      ///   - mimeType: MIME type of the body (default: nil).
      ///   - body: Response body data (default: empty).
      public init(
        status: Int = 200,
        headers: [String: String] = [:],
        mimeType: String? = nil,
        body: Data = Data()
      ) {
        self.status = status
        self.headers = headers
        self.mimeType = mimeType
        self.body = body
      }
    }

    /// A closure that handles custom protocol requests.
    ///
    /// Return `nil` to indicate the request was not handled.
    public typealias Handler = @Sendable (Request) -> Response?

    /// The URL scheme this handler responds to (e.g., "app", "ipc").
    public let scheme: String
    let handler: Handler

    /// Creates a custom protocol handler.
    ///
    /// - Parameters:
    ///   - scheme: The URL scheme to handle.
    ///   - handler: The closure that processes requests.
    public init(scheme: String, handler: @escaping Handler) {
      self.scheme = scheme
      self.handler = handler
    }
  }

  static func duplicateCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    string.withCString { source -> UnsafeMutablePointer<CChar>? in
#if canImport(Darwin)
      guard let duplicated = Darwin.strdup(source) else { return nil }
      return duplicated
#else
      guard let duplicated = Glibc.strdup(source) else { return nil }
      return duplicated
#endif
    }
  }

  static func stringFromNullablePointer(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    return String(cString: pointer)
  }

  /// Webview configuration subset mirrored from `wry::WebViewBuilder`.
  public struct WebviewConfiguration: Sendable {
    public var url: String
    public var customProtocols: [CustomProtocol]
    /// If true, create as a child webview with specific bounds instead of filling the window.
    public var isChild: Bool
    /// X position for child webview (logical pixels).
    public var x: Double
    /// Y position for child webview (logical pixels).
    public var y: Double
    /// Width for child webview (logical pixels).
    public var width: Double
    /// Height for child webview (logical pixels).
    public var height: Double

    public init(
      url: String = "",
      customProtocols: [CustomProtocol] = [],
      isChild: Bool = false,
      x: Double = 0,
      y: Double = 0,
      width: Double = 0,
      height: Double = 0
    ) {
      self.url = url
      self.customProtocols = customProtocols
      self.isChild = isChild
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }

  public enum Dialog {
    public struct Filter: Sendable {
      public var label: String
      public var extensions: [String]

      public init(label: String, extensions: [String]) {
        self.label = label
        self.extensions = extensions
      }
    }

    public struct OpenOptions: Sendable {
      public var title: String?
      public var defaultURL: URL?
      public var filters: [Filter]
      public var allowDirectories: Bool
      public var allowMultiple: Bool

      public init(
        title: String? = nil,
        defaultURL: URL? = nil,
        filters: [Filter] = [],
        allowDirectories: Bool = false,
        allowMultiple: Bool = false
      ) {
        self.title = title
        self.defaultURL = defaultURL
        self.filters = filters
        self.allowDirectories = allowDirectories
        self.allowMultiple = allowMultiple
      }
    }

    public struct SaveOptions: Sendable {
      public var title: String?
      public var defaultURL: URL?
      public var defaultFileName: String?
      public var filters: [Filter]

      public init(
        title: String? = nil,
        defaultURL: URL? = nil,
        defaultFileName: String? = nil,
        filters: [Filter] = []
      ) {
        self.title = title
        self.defaultURL = defaultURL
        self.defaultFileName = defaultFileName
        self.filters = filters
      }
    }

    public enum MessageLevel: Sendable {
      case info
      case warning
      case error
    }

    public enum MessageButtons: Sendable {
      case ok
      case okCustom(String)
      case okCancel
      case okCancelCustom(ok: String, cancel: String)
      case yesNo
      case yesNoCancel
      case yesNoCancelCustom(yes: String, no: String, cancel: String)
    }

    public struct MessageOptions: Sendable {
      public var title: String?
      public var message: String
      public var level: MessageLevel
      public var buttons: MessageButtons

      public init(
        title: String? = nil,
        message: String,
        level: MessageLevel = .info,
        buttons: MessageButtons = .ok
      ) {
        self.title = title
        self.message = message
        self.level = level
        self.buttons = buttons
      }
    }

    public struct PromptOptions: Sendable {
      public var title: String?
      public var message: String
      public var placeholder: String?
      public var defaultValue: String?
      public var okLabel: String?
      public var cancelLabel: String?

      public init(
        title: String? = nil,
        message: String,
        placeholder: String? = nil,
        defaultValue: String? = nil,
        okLabel: String? = nil,
        cancelLabel: String? = nil
      ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.okLabel = okLabel
        self.cancelLabel = cancelLabel
      }
    }

    public struct AskOptions: Sendable {
      public var title: String?
      public var level: MessageLevel
      public var yesLabel: String?
      public var noLabel: String?

      public init(
        title: String? = nil,
        level: MessageLevel = .info,
        yesLabel: String? = nil,
        noLabel: String? = nil
      ) {
        self.title = title
        self.level = level
        self.yesLabel = yesLabel
        self.noLabel = noLabel
      }
    }

    public struct ConfirmOptions: Sendable {
      public var title: String?
      public var level: MessageLevel
      public var okLabel: String?
      public var cancelLabel: String?

      public init(
        title: String? = nil,
        level: MessageLevel = .info,
        okLabel: String? = nil,
        cancelLabel: String? = nil
      ) {
        self.title = title
        self.level = level
        self.okLabel = okLabel
        self.cancelLabel = cancelLabel
      }
    }

    public static func open(_ options: OpenOptions = .init()) -> [URL] {
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let defaultPathPointer = options.defaultURL.flatMap { VeloxRuntimeWry.duplicateCString($0.path) }

      var filterDefinitions: [VeloxDialogFilter] = []
      var filterLabelPointers: [UnsafeMutablePointer<CChar>?] = []
      var filterExtensionBlocks: [UnsafeMutablePointer<UnsafePointer<CChar>?>?] = []
      var filterExtensionStorage: [[UnsafeMutablePointer<CChar>?]] = []

      for filter in options.filters {
        guard let labelPointer = VeloxRuntimeWry.duplicateCString(filter.label) else {
          continue
        }
        filterLabelPointers.append(labelPointer)

        var extensionPointers: [UnsafeMutablePointer<CChar>?] = []
        extensionPointers.reserveCapacity(filter.extensions.count)
        for ext in filter.extensions {
          if let pointer = VeloxRuntimeWry.duplicateCString(ext) {
            extensionPointers.append(pointer)
          }
        }
        filterExtensionStorage.append(extensionPointers)

        let extensionBlock: UnsafeMutablePointer<UnsafePointer<CChar>?>?
        if extensionPointers.isEmpty {
          extensionBlock = nil
        } else {
          let block = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: extensionPointers.count)
          for (index, pointer) in extensionPointers.enumerated() {
            block[index] = pointer.map { UnsafePointer($0) }
          }
          extensionBlock = block
        }
        filterExtensionBlocks.append(extensionBlock)

        filterDefinitions.append(
          VeloxDialogFilter(
            label: UnsafePointer(labelPointer),
            extensions: extensionBlock.map { UnsafePointer($0) },
            extension_count: extensionPointers.count
          )
        )
      }

      defer {
        if let titlePointer { free(titlePointer) }
        if let defaultPathPointer { free(defaultPathPointer) }
        for pointer in filterLabelPointers {
          if let pointer { free(pointer) }
        }
        for (index, block) in filterExtensionBlocks.enumerated() {
          if let block { block.deallocate() }
          for pointer in filterExtensionStorage[index] {
            if let pointer { free(pointer) }
          }
        }
      }

      var ffiOptions = VeloxDialogOpenOptions(
        title: titlePointer,
        default_path: defaultPathPointer,
        filters: nil,
        filter_count: 0,
        allow_directories: options.allowDirectories,
        allow_multiple: options.allowMultiple
      )

      return filterDefinitions.withUnsafeBufferPointer { buffer in
        if let baseAddress = buffer.baseAddress, buffer.count > 0 {
          ffiOptions.filters = baseAddress
          ffiOptions.filter_count = buffer.count
        }

        return withUnsafeMutablePointer(to: &ffiOptions) { pointer in
          let selection = velox_dialog_open(pointer)
          defer { velox_dialog_selection_free(selection) }
          return urls(from: selection)
        }
      }
    }

    public static func save(_ options: SaveOptions = .init()) -> URL? {
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let defaultPathPointer = options.defaultURL.flatMap { VeloxRuntimeWry.duplicateCString($0.path) }
      let defaultNamePointer = options.defaultFileName.flatMap { VeloxRuntimeWry.duplicateCString($0) }

      var filterDefinitions: [VeloxDialogFilter] = []
      var filterLabelPointers: [UnsafeMutablePointer<CChar>?] = []
      var filterExtensionBlocks: [UnsafeMutablePointer<UnsafePointer<CChar>?>?] = []
      var filterExtensionStorage: [[UnsafeMutablePointer<CChar>?]] = []

      for filter in options.filters {
        guard let labelPointer = VeloxRuntimeWry.duplicateCString(filter.label) else {
          continue
        }
        filterLabelPointers.append(labelPointer)

        var extensionPointers: [UnsafeMutablePointer<CChar>?] = []
        for ext in filter.extensions {
          if let pointer = VeloxRuntimeWry.duplicateCString(ext) {
            extensionPointers.append(pointer)
          }
        }
        filterExtensionStorage.append(extensionPointers)

        let extensionBlock: UnsafeMutablePointer<UnsafePointer<CChar>?>?
        if extensionPointers.isEmpty {
          extensionBlock = nil
        } else {
          let block = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: extensionPointers.count)
          for (index, pointer) in extensionPointers.enumerated() {
            block[index] = pointer.map { UnsafePointer($0) }
          }
          extensionBlock = block
        }
        filterExtensionBlocks.append(extensionBlock)

        filterDefinitions.append(
          VeloxDialogFilter(
            label: UnsafePointer(labelPointer),
            extensions: extensionBlock.map { UnsafePointer($0) },
            extension_count: extensionPointers.count
          )
        )
      }

      defer {
        if let titlePointer { free(titlePointer) }
        if let defaultPathPointer { free(defaultPathPointer) }
        if let defaultNamePointer { free(defaultNamePointer) }
        for pointer in filterLabelPointers {
          if let pointer { free(pointer) }
        }
        for (index, block) in filterExtensionBlocks.enumerated() {
          if let block { block.deallocate() }
          for pointer in filterExtensionStorage[index] {
            if let pointer { free(pointer) }
          }
        }
      }

      var ffiOptions = VeloxDialogSaveOptions(
        title: titlePointer,
        default_path: defaultPathPointer,
        default_name: defaultNamePointer,
        filters: nil,
        filter_count: 0
      )

      let selections = filterDefinitions.withUnsafeBufferPointer { buffer -> [URL] in
        if let baseAddress = buffer.baseAddress, buffer.count > 0 {
          ffiOptions.filters = baseAddress
          ffiOptions.filter_count = buffer.count
        }

        return withUnsafeMutablePointer(to: &ffiOptions) { pointer in
          let selection = velox_dialog_save(pointer)
          defer { velox_dialog_selection_free(selection) }
          return urls(from: selection)
        }
      }

      return selections.first
    }

    public static func saveAsync(_ options: SaveOptions = .init()) async -> URL? {
      await runOnMain { save(options) }
    }

    public static func openAsync(_ options: OpenOptions = .init()) async -> [URL] {
      await runOnMain { open(options) }
    }

    @discardableResult
    public static func message(_ options: MessageOptions) -> Bool {
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      guard let messagePointer = VeloxRuntimeWry.duplicateCString(options.message) else {
        return false
      }

      defer {
        if let titlePointer { free(titlePointer) }
        free(messagePointer)
      }

      let level = ffiLevel(from: options.level)

      var okLabelPointer: UnsafeMutablePointer<CChar>?
      var cancelLabelPointer: UnsafeMutablePointer<CChar>?
      var yesLabelPointer: UnsafeMutablePointer<CChar>?
      var noLabelPointer: UnsafeMutablePointer<CChar>?

      let buttons: VeloxMessageDialogButtons
      switch options.buttons {
      case .ok:
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_OK
      case let .okCustom(okLabel):
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_OK
        okLabelPointer = VeloxRuntimeWry.duplicateCString(okLabel)
      case .okCancel:
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_OK_CANCEL
      case let .okCancelCustom(okLabel, cancelLabel):
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_OK_CANCEL
        okLabelPointer = VeloxRuntimeWry.duplicateCString(okLabel)
        cancelLabelPointer = VeloxRuntimeWry.duplicateCString(cancelLabel)
      case .yesNo:
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_YES_NO
      case .yesNoCancel:
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_YES_NO_CANCEL
      case let .yesNoCancelCustom(yesLabel, noLabel, cancelLabel):
        buttons = VELOX_MESSAGE_DIALOG_BUTTONS_YES_NO_CANCEL
        yesLabelPointer = VeloxRuntimeWry.duplicateCString(yesLabel)
        noLabelPointer = VeloxRuntimeWry.duplicateCString(noLabel)
        cancelLabelPointer = VeloxRuntimeWry.duplicateCString(cancelLabel)
      }

      defer {
        if let okLabelPointer { free(okLabelPointer) }
        if let cancelLabelPointer { free(cancelLabelPointer) }
        if let yesLabelPointer { free(yesLabelPointer) }
        if let noLabelPointer { free(noLabelPointer) }
      }

      var ffiOptions = VeloxMessageDialogOptions(
        title: titlePointer,
        message: UnsafePointer(messagePointer),
        level: level,
        buttons: buttons,
        ok_label: okLabelPointer.map { UnsafePointer($0) },
        cancel_label: cancelLabelPointer.map { UnsafePointer($0) },
        yes_label: yesLabelPointer.map { UnsafePointer($0) },
        no_label: noLabelPointer.map { UnsafePointer($0) }
      )

      return withUnsafePointer(to: &ffiOptions) { pointer in
        velox_dialog_message(pointer)
      }
    }

    @discardableResult
    public static func messageAsync(_ options: MessageOptions) async -> Bool {
      await runOnMain { message(options) }
    }

    public static func prompt(_ options: PromptOptions) -> String? {
      guard let messagePointer = VeloxRuntimeWry.duplicateCString(options.message) else {
        return nil
      }
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let placeholderPointer = options.placeholder.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let defaultValuePointer = options.defaultValue.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let okLabelPointer = options.okLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let cancelLabelPointer = options.cancelLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }

      defer {
        free(messagePointer)
        if let titlePointer { free(titlePointer) }
        if let placeholderPointer { free(placeholderPointer) }
        if let defaultValuePointer { free(defaultValuePointer) }
        if let okLabelPointer { free(okLabelPointer) }
        if let cancelLabelPointer { free(cancelLabelPointer) }
      }

      var ffiOptions = VeloxPromptDialogOptions(
        title: titlePointer,
        message: UnsafePointer(messagePointer),
        placeholder: placeholderPointer.flatMap { UnsafePointer($0) },
        default_value: defaultValuePointer.flatMap { UnsafePointer($0) },
        ok_label: okLabelPointer.flatMap { UnsafePointer($0) },
        cancel_label: cancelLabelPointer.flatMap { UnsafePointer($0) }
      )

      let result = withUnsafePointer(to: &ffiOptions) { pointer in
        velox_dialog_prompt(pointer)
      }

      defer {
        velox_dialog_prompt_result_free(result)
      }

      guard result.accepted, let valuePointer = result.value else {
        return nil
      }
      return String(cString: valuePointer)
    }

    public static func promptAsync(_ options: PromptOptions) async -> String? {
      await runOnMain { prompt(options) }
    }

    @discardableResult
    public static func ask(_ message: String, options: AskOptions = .init()) -> Bool {
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      guard let messagePointer = VeloxRuntimeWry.duplicateCString(message) else {
        if let titlePointer { free(titlePointer) }
        return false
      }
      let yesLabelPointer = options.yesLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let noLabelPointer = options.noLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }

      defer {
        if let titlePointer { free(titlePointer) }
        free(messagePointer)
        if let yesLabelPointer { free(yesLabelPointer) }
        if let noLabelPointer { free(noLabelPointer) }
      }

      var ffiOptions = VeloxAskDialogOptions(
        title: titlePointer,
        message: UnsafePointer(messagePointer),
        level: ffiLevel(from: options.level),
        yes_label: yesLabelPointer.flatMap { UnsafePointer($0) },
        no_label: noLabelPointer.flatMap { UnsafePointer($0) }
      )

      return withUnsafePointer(to: &ffiOptions) { pointer in
        velox_dialog_ask(pointer)
      }
    }

    @discardableResult
    public static func askAsync(_ message: String, options: AskOptions = .init()) async -> Bool {
      await runOnMain { ask(message, options: options) }
    }

    @discardableResult
    public static func confirm(_ message: String, options: ConfirmOptions = .init()) -> Bool {
      let titlePointer = options.title.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      guard let messagePointer = VeloxRuntimeWry.duplicateCString(message) else {
        if let titlePointer { free(titlePointer) }
        return false
      }
      let okLabelPointer = options.okLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }
      let cancelLabelPointer = options.cancelLabel.flatMap { VeloxRuntimeWry.duplicateCString($0) }

      defer {
        if let titlePointer { free(titlePointer) }
        free(messagePointer)
        if let okLabelPointer { free(okLabelPointer) }
        if let cancelLabelPointer { free(cancelLabelPointer) }
      }

      var ffiOptions = VeloxConfirmDialogOptions(
        title: titlePointer,
        message: UnsafePointer(messagePointer),
        level: ffiLevel(from: options.level),
        ok_label: okLabelPointer.flatMap { UnsafePointer($0) },
        cancel_label: cancelLabelPointer.flatMap { UnsafePointer($0) }
      )

      return withUnsafePointer(to: &ffiOptions) { pointer in
        velox_dialog_confirm(pointer)
      }
    }

    @discardableResult
    public static func confirmAsync(_ message: String, options: ConfirmOptions = .init()) async -> Bool {
      await runOnMain { confirm(message, options: options) }
    }

    private static func ffiLevel(from level: MessageLevel) -> VeloxMessageDialogLevel {
      switch level {
      case .info: return VELOX_MESSAGE_DIALOG_LEVEL_INFO
      case .warning: return VELOX_MESSAGE_DIALOG_LEVEL_WARNING
      case .error: return VELOX_MESSAGE_DIALOG_LEVEL_ERROR
      }
    }

    private static func runOnMain<T>(_ work: @escaping () -> T) async -> T {
      await withCheckedContinuation { continuation in
        if Thread.isMainThread {
          continuation.resume(returning: work())
        } else {
          DispatchQueue.main.async {
            continuation.resume(returning: work())
          }
        }
      }
    }

    private static func urls(from selection: VeloxDialogSelection) -> [URL] {
      guard selection.count > 0, let base = selection.paths else {
        return []
      }

      let buffer = UnsafeBufferPointer(start: base, count: Int(selection.count))
      return buffer.compactMap { pointer in
        guard let pointer else { return nil }
        return URL(fileURLWithPath: String(cString: pointer))
      }
    }
}

}

public extension VeloxRuntimeWry {
  /// Swift-native runtime adapter that drives the tao event loop without relying on tauri-runtime.
  final class Runtime: VeloxRuntime {
    public typealias Event = VeloxRuntimeWry.Event
    public typealias Handle = Runtime
    public typealias EventLoopProxyType = EventLoopProxyAdapter

    private struct WindowState {
      let label: String
      let taoIdentifier: String
      let window: Window
      var webview: Webview?
    }

    private let eventLoop: EventLoop
    private let eventLoopProxy: EventLoopProxy?
    private let stateLock = NSLock()
    private var windows: [ObjectIdentifier: WindowState] = [:]
    private var windowsByLabel: [String: ObjectIdentifier] = [:]
    private var windowsByTaoIdentifier: [String: ObjectIdentifier] = [:]
    private var windowEventStreams: [ObjectIdentifier: VeloxEventStreamMultiplexer<WindowEvent>] = [:]
    private var webviewEventStreams: [ObjectIdentifier: VeloxEventStreamMultiplexer<WebviewEvent>] = [:]
    private let menuEventStream = VeloxEventStreamMultiplexer<MenuEvent>()
    private let trayEventStream = VeloxEventStreamMultiplexer<TrayEventNotification>()

    public static func make(args _: VeloxRuntimeInitArgs) throws -> Runtime {
      guard Thread.isMainThread else {
        throw VeloxRuntimeError.failed(description: "VeloxRuntimeWry.Runtime must be created on the main thread")
      }
      guard let eventLoop = EventLoop() else {
        throw VeloxRuntimeError.unsupported
      }
      return Runtime(eventLoop: eventLoop)
    }

    public convenience init?() {
      guard Thread.isMainThread else {
        return nil
      }
      guard let eventLoop = EventLoop() else {
        return nil
      }
      self.init(eventLoop: eventLoop)
    }

    private init(eventLoop: EventLoop) {
      self.eventLoop = eventLoop
      self.eventLoopProxy = eventLoop.makeProxy()
    }

    public func handle() -> Runtime { self }

    public func createProxy() throws -> EventLoopProxyAdapter {
      guard let proxy = eventLoopProxy else {
        throw VeloxRuntimeError.unsupported
      }
      return EventLoopProxyAdapter(proxy: proxy)
    }

    public func createWindow(
      pending: VeloxPendingWindow<Event>
    ) throws -> VeloxDetachedWindow<Event, Window, Webview> {
      guard let window = eventLoop.makeWindow(configuration: .init(title: pending.label)) else {
        throw VeloxRuntimeError.unsupported
      }
      return registerWindow(window, label: pending.label)
    }

    public func createWebview(
      window identifier: ObjectIdentifier,
      pending _: VeloxPendingWebview<Event>
    ) throws -> Webview {
      let state: WindowState? = {
        stateLock.lock()
        defer { stateLock.unlock() }
        return windows[identifier]
      }()

      guard let state else {
        throw VeloxRuntimeError.failed(description: "window not found")
      }

      guard let webview = state.window.makeWebview() else {
        throw VeloxRuntimeError.unsupported
      }

      stateLock.lock()
      var updated = state
      updated.webview = webview
      windows[identifier] = updated
      stateLock.unlock()

      webview.register(owner: self, windowIdentifier: identifier)

      return webview
    }

    public func runIteration(
      handler: @Sendable @escaping (VeloxRunEvent<Event>) -> VeloxControlFlow
    ) {
      eventLoop.pump { event in
        self.route(event)
        let flow = handler(self.toRunEvent(from: event))
        switch flow {
        case .poll: return ControlFlow.poll
        case .wait: return ControlFlow.wait
        case .exit: return ControlFlow.exit
        }
      }
    }

    public func requestExit(code: Int32) throws {
      guard let proxy = eventLoopProxy else {
        throw VeloxRuntimeError.unsupported
      }
      guard proxy.requestExit() else {
        throw VeloxRuntimeError.failed(description: "failed to signal event loop exit")
      }
    }

    @discardableResult
    public func requestExitIfPossible(code: Int32 = 0) -> Bool {
      (try? requestExit(code: code)) != nil
    }

    @discardableResult
    public func createWindow(
      configuration: WindowConfiguration? = nil,
      label: String? = nil
    ) throws -> VeloxDetachedWindow<Event, Window, Webview> {
      guard let window = eventLoop.makeWindow(configuration: configuration) else {
        throw VeloxRuntimeError.unsupported
      }
      let resolvedLabel = label ?? configuration?.title ?? makeDefaultLabel(for: window)
      return registerWindow(window, label: resolvedLabel)
    }

    public func windowIdentifier(forLabel label: String) -> ObjectIdentifier? {
      stateLock.lock()
      defer { stateLock.unlock() }
      return windowsByLabel[label]
    }

    public func window(for label: String) -> Window? {
      stateLock.lock()
      defer { stateLock.unlock() }
      guard let identifier = windowsByLabel[label], let state = windows[identifier] else {
        return nil
      }
      return state.window
    }

    private func registerWindow(
      _ window: Window,
      label: String,
      webview: Webview? = nil
    ) -> VeloxDetachedWindow<Event, Window, Webview> {
      let identifier = ObjectIdentifier(window)
      let taoIdentifier = window.taoIdentifier
      let state = WindowState(label: label, taoIdentifier: taoIdentifier, window: window, webview: webview)
      stateLock.lock()
      windows[identifier] = state
      windowsByLabel[label] = identifier
      windowsByTaoIdentifier[taoIdentifier] = identifier
      stateLock.unlock()
      window.register(owner: self)
      return VeloxDetachedWindow(id: identifier, label: label, dispatcher: window, webview: webview)
    }

    public func menuEvents(
      bufferingPolicy: AsyncStream<MenuEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<MenuEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = self.menuEventStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.menuEventStream.remove(token)
        }
      }
    }

    public func trayEvents(
      bufferingPolicy: AsyncStream<TrayEventNotification>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<TrayEventNotification> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token = self.trayEventStream.add(continuation)
        continuation.onTermination = { [weak self] _ in
          self?.trayEventStream.remove(token)
        }
      }
    }

    private func makeDefaultLabel(for window: Window) -> String {
      "window-\(window.taoIdentifier)"
    }

    private func label(forWindowIdentifier identifier: String) -> String {
      stateLock.lock()
      defer { stateLock.unlock() }
      if let objectIdentifier = windowsByTaoIdentifier[identifier], let state = windows[objectIdentifier] {
        return state.label
      }
      return identifier
    }

    private func removeWindow(forWindowIdentifier identifier: String) -> String? {
      var label: String?
      var windowStream: VeloxEventStreamMultiplexer<WindowEvent>?
      var webviewStream: VeloxEventStreamMultiplexer<WebviewEvent>?

      stateLock.lock()
      if let objectIdentifier = windowsByTaoIdentifier.removeValue(forKey: identifier),
        let state = windows.removeValue(forKey: objectIdentifier)
      {
        windowsByLabel.removeValue(forKey: state.label)
        label = state.label
        windowStream = windowEventStreams.removeValue(forKey: objectIdentifier)
        webviewStream = webviewEventStreams.removeValue(forKey: objectIdentifier)
      }
      stateLock.unlock()

      windowStream?.finishAll()
      webviewStream?.finishAll()

      return label
    }

    fileprivate func windowEventStream(
      for identifier: ObjectIdentifier,
      bufferingPolicy: AsyncStream<WindowEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<WindowEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token: UUID = {
          stateLock.lock()
          defer { stateLock.unlock() }
          let sink = windowEventStreams[identifier] ?? VeloxEventStreamMultiplexer<WindowEvent>()
          let token = sink.add(continuation)
          windowEventStreams[identifier] = sink
          return token
        }()

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.stateLock.lock()
          if let sink = self.windowEventStreams[identifier] {
            sink.remove(token)
            if sink.isEmpty {
              self.windowEventStreams.removeValue(forKey: identifier)
            }
          }
          self.stateLock.unlock()
        }
      }
    }

    fileprivate func webviewEventStream(
      for identifier: ObjectIdentifier,
      bufferingPolicy: AsyncStream<WebviewEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<WebviewEvent> {
      AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let token: UUID = {
          stateLock.lock()
          defer { stateLock.unlock() }
          let sink = webviewEventStreams[identifier] ?? VeloxEventStreamMultiplexer<WebviewEvent>()
          let token = sink.add(continuation)
          webviewEventStreams[identifier] = sink
          return token
        }()

        continuation.onTermination = { [weak self] _ in
          guard let self else { return }
          self.stateLock.lock()
          if let sink = self.webviewEventStreams[identifier] {
            sink.remove(token)
            if sink.isEmpty {
              self.webviewEventStreams.removeValue(forKey: identifier)
            }
          }
          self.stateLock.unlock()
        }
      }
    }

    private func route(_ event: Event) {
      switch event {
      case .windowCloseRequested(let windowId),
        .windowDestroyed(let windowId),
        .windowResized(let windowId, _),
        .windowMoved(let windowId, _),
        .windowFocused(let windowId, _),
        .windowScaleFactorChanged(let windowId, _, _),
        .windowKeyboardInput(let windowId, _),
        .windowImeText(let windowId, _),
        .windowModifiersChanged(let windowId, _),
        .windowCursorMoved(let windowId, _),
        .windowCursorEntered(let windowId, _),
        .windowCursorLeft(let windowId, _),
        .windowMouseInput(let windowId, _),
        .windowMouseWheel(let windowId, _, _),
        .windowDroppedFile(let windowId, _),
        .windowHoveredFile(let windowId, _),
        .windowHoveredFileCancelled(let windowId),
        .windowThemeChanged(let windowId, _),
        .windowEvent(let windowId, _),
        .windowRedrawRequested(let windowId):
        deliverWindowEvent(windowIdentifier: windowId, event: event)
      case .webviewEvent(let label, _):
        deliverWebviewEvent(label: label, event: event)
      case .loopDestroyed, .exit, .userExit:
        finishAllStreams()
      case .menuEvent(let identifier):
        menuEventStream.yield(.activated(identifier: identifier))
      case .trayEvent(let trayEvent):
        trayEventStream.yield(.init(identifier: trayEvent.identifier, event: trayEvent))
      default:
        break
      }
    }

    private func deliverWindowEvent(windowIdentifier: String, event: Event) {
      var sink: VeloxEventStreamMultiplexer<WindowEvent>?
      var label: String?
      stateLock.lock()
      if let objectIdentifier = windowsByTaoIdentifier[windowIdentifier],
        let state = windows[objectIdentifier]
      {
        sink = windowEventStreams[objectIdentifier]
        label = state.label
      }
      stateLock.unlock()

      if let sink, let label {
        let payload = VeloxRuntimeWry.makeWindowEvent(label: label, event: event)
        sink.yield(payload)
      }
    }

    private func deliverWebviewEvent(label: String, event: Event) {
      var sink: VeloxEventStreamMultiplexer<WebviewEvent>?
      stateLock.lock()
      if let objectIdentifier = windowsByLabel[label] {
        sink = webviewEventStreams[objectIdentifier]
      }
      stateLock.unlock()

      if let sink {
        let payload = VeloxRuntimeWry.makeWebviewEvent(label: label, event: event)
        sink.yield(payload)
      }
    }

    private func finishAllStreams() {
      let windowSinks: [VeloxEventStreamMultiplexer<WindowEvent>]
      let webviewSinks: [VeloxEventStreamMultiplexer<WebviewEvent>]

      stateLock.lock()
      windowSinks = Array(windowEventStreams.values)
      webviewSinks = Array(webviewEventStreams.values)
      windowEventStreams.removeAll()
      webviewEventStreams.removeAll()
      stateLock.unlock()

      windowSinks.forEach { $0.finishAll() }
      webviewSinks.forEach { $0.finishAll() }
      menuEventStream.finishAll()
      trayEventStream.finishAll()
    }

    private func toRunEvent(from event: Event) -> VeloxRunEvent<Event> {
      switch event {
      case .ready:
        return .ready
      case .loopDestroyed, .userExit:
        return .exit
      case let .exitRequested(code):
        return .exitRequested(code: code)
      case let .webviewEvent(label, _):
        return .webviewEvent(label: label)
      case .windowDestroyed(let windowId):
        let label = removeWindow(forWindowIdentifier: windowId) ?? windowId
        return .windowEvent(label: label)
      case .windowCloseRequested(let windowId),
        .windowResized(let windowId, _),
        .windowMoved(let windowId, _),
        .windowFocused(let windowId, _),
        .windowScaleFactorChanged(let windowId, _, _),
        .windowKeyboardInput(let windowId, _),
        .windowImeText(let windowId, _),
        .windowModifiersChanged(let windowId, _),
        .windowCursorMoved(let windowId, _),
        .windowCursorEntered(let windowId, _),
        .windowCursorLeft(let windowId, _),
        .windowMouseInput(let windowId, _),
        .windowMouseWheel(let windowId, _, _),
        .windowDroppedFile(let windowId, _),
        .windowHoveredFile(let windowId, _),
        .windowHoveredFileCancelled(let windowId),
        .windowThemeChanged(let windowId, _),
        .windowEvent(let windowId, _):
        let label = label(forWindowIdentifier: windowId)
        return .windowEvent(label: label)
      case let .raw(description):
        return .raw(description: description)
      case .menuEvent:
        return .userEvent(event)
      default:
        return .userEvent(event)
      }
    }
  }

  /// Wrapper around `tao::event_loop::EventLoop` exposing a pump-based processing model.
  final class EventLoop {
    private var raw: UnsafeMutablePointer<VeloxEventLoopHandle>?

    public init?() {
      guard let handle = velox_event_loop_new() else {
        return nil
      }
      raw = handle
    }

    deinit {
      if let raw {
        velox_event_loop_free(raw)
      }
    }

    /// Releases the underlying Tao event loop handle immediately. Further usage is undefined.
    public func shutdown() {
      if let raw {
        velox_event_loop_free(raw)
        self.raw = nil
      }
    }

    /// Runs a single event loop iteration via `EventLoopExtRunReturn`, invoking the callback for
    /// every Tao event processed before exiting. Return `.exit` from the callback (or send an exit
    /// request through the proxy) to break the loop.
    public func pump(_ handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
      guard let raw else {
        return
      }

      let box = EventLoopCallback(handler: handler)
      let unmanaged = Unmanaged.passRetained(box)
      velox_event_loop_pump(raw, EventLoop.callback, unmanaged.toOpaque())
      unmanaged.release()
    }

    /// Runs the event loop until `.exit` is returned by the handler.
    public func run(_ handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
      pump(handler)
    }

    /// Runs the event loop with a default handler that exits on close requests.
    public func run() {
      pump { event in
        switch event {
        case .windowCloseRequested, .userExit, .exitRequested, .exit:
          return .exit
        default:
          return .wait
        }
      }
    }

    /// Creates a proxy that can be used to send user events such as exit requests.
    public func makeProxy() -> EventLoopProxy? {
      guard let raw else {
        return nil
      }
      guard let handle = velox_event_loop_create_proxy(raw) else {
        return nil
      }
      return EventLoopProxy(raw: handle)
    }

    /// Convenience to build a Tao window using the underlying event loop.
    public func makeWindow(configuration: WindowConfiguration? = nil) -> Window? {
      guard let raw else {
        return nil
      }

      if let configuration {
        return withOptionalCString(configuration.title) { titlePointer in
          var native = VeloxWindowConfig(width: configuration.width, height: configuration.height, title: titlePointer)
          return withUnsafePointer(to: &native) { pointer in
            guard let handle = velox_window_build(raw, pointer) else {
              return nil
            }
            return Window(raw: handle)
          }
        }
      } else {
        guard let handle = velox_window_build(raw, nil) else {
          return nil
        }
        return Window(raw: handle)
      }
    }

#if os(macOS)
    public enum ActivationPolicy {
      case regular
      case accessory
      case prohibited
    }

    @discardableResult
    public func setActivationPolicy(_ policy: ActivationPolicy) -> Bool {
      guard let raw else {
        return false
      }

      let ffiPolicy: VeloxActivationPolicy
      switch policy {
      case .regular: ffiPolicy = VELOX_ACTIVATION_POLICY_REGULAR
      case .accessory: ffiPolicy = VELOX_ACTIVATION_POLICY_ACCESSORY
      case .prohibited: ffiPolicy = VELOX_ACTIVATION_POLICY_PROHIBITED
      }
      return velox_event_loop_set_activation_policy(raw, ffiPolicy)
    }

    @discardableResult
    public func setDockVisibility(_ visible: Bool) -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_set_dock_visibility(raw, visible)
    }

    @discardableResult
    public func hideApplication() -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_hide_application(raw)
    }

    @discardableResult
    public func showApplication() -> Bool {
      guard let raw else {
        return false
      }
      return velox_event_loop_show_application(raw)
    }
#endif

    private final class EventLoopCallback {
      let handler: @Sendable (_ event: Event) -> ControlFlow

      init(handler: @escaping @Sendable (_ event: Event) -> ControlFlow) {
        self.handler = handler
      }
    }

    private static let callback: @convention(c) (
      UnsafePointer<CChar>?,
      UnsafeMutableRawPointer?
    ) -> VeloxRuntimeWryFFI.VeloxEventLoopControlFlow = { event, userData in
      guard let userData else {
        return VELOX_CONTROL_FLOW_EXIT
      }

      let box = Unmanaged<EventLoopCallback>.fromOpaque(userData).takeUnretainedValue()
      let json = event.map { String(cString: $0) } ?? "{}"
      let parsedEvent = Event(fromJSON: json)
      let flow = box.handler(parsedEvent)
      return VeloxRuntimeWryFFI.VeloxEventLoopControlFlow(rawValue: UInt32(flow.rawValue))
    }
  }

  /// Handle to a Tao `EventLoopProxy` enabling exit requests from other threads.
  final class EventLoopProxy {
    private let raw: UnsafeMutablePointer<VeloxEventLoopProxyHandle>

    fileprivate init?(raw: UnsafeMutablePointer<VeloxEventLoopProxyHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_event_loop_proxy_free(raw)
    }

    /// Sends a termination request into the event loop.
    @discardableResult
    public func requestExit() -> Bool {
      velox_event_loop_proxy_request_exit(raw)
    }

    /// Sends a custom user event payload into the event loop.
    @discardableResult
    public func sendUserEvent(_ payload: String) -> Bool {
      withOptionalCString(payload) { pointer in
        velox_event_loop_proxy_send_user_event(raw, pointer)
      }
    }

    @discardableResult
    public func sendUserEvent<T: Encodable>(
      _ payload: T,
      encoder: JSONEncoder = JSONEncoder()
    ) -> Bool {
      guard let encoded = try? VeloxRuntimeWry.UserDefinedPayload(encoding: payload, encoder: encoder) else {
        return false
      }
      return sendUserEvent(encoded.rawValue)
    }
  }

  /// Handle wrapper mirroring Tao's `Window`.
  final class Window {
    fileprivate let raw: UnsafeMutablePointer<VeloxWindowHandle>
    private weak var owner: Runtime?

    public enum AttentionType: Int32, Sendable {
      case informational = 0
      case critical = 1
    }

    public enum ResizeDirection: Int32, Sendable {
      case east = 0
      case north = 1
      case northEast = 2
      case northWest = 3
      case south = 4
      case southEast = 5
      case southWest = 6
      case west = 7
    }

    public struct Color: Sendable, Equatable {
      public var red: Double
      public var green: Double
      public var blue: Double
      public var alpha: Double

      public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
      }

      fileprivate func toFFI() -> VeloxColor {
        func clamp(_ value: Double) -> UInt8 {
          let clamped = min(max(value, 0.0), 1.0)
          return UInt8((clamped * 255.0).rounded())
        }
        return VeloxColor(
          red: clamp(red),
          green: clamp(green),
          blue: clamp(blue),
          alpha: clamp(alpha)
        )
      }
    }

    public enum Theme: Sendable, Equatable {
      case light
      case dark
    }

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWindowHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_window_free(raw)
    }

    fileprivate var taoIdentifier: String {
      string(from: velox_window_identifier(raw))
    }

    fileprivate func register(owner: Runtime) {
      self.owner = owner
    }

  /// Builds a Wry webview attached to the window.
  public func makeWebview(configuration: WebviewConfiguration? = nil) -> Webview? {
    if let configuration {
      var handlerBoxes: [VeloxCustomProtocolHandlerBox] = []
      var schemePointers: [UnsafeMutablePointer<CChar>?] = []
      var definitions: [VeloxCustomProtocolDefinition] = []

      for custom in configuration.customProtocols {
        guard !custom.scheme.isEmpty, let schemePointer = VeloxRuntimeWry.duplicateCString(custom.scheme) else {
          continue
        }

        let box = VeloxCustomProtocolHandlerBox(handler: custom.handler)
        handlerBoxes.append(box)
        schemePointers.append(schemePointer)

        var definition = VeloxCustomProtocolDefinition()
        definition.scheme = UnsafePointer(schemePointer)
        definition.handler = velox_custom_protocol_handler_bridge_c
        definition.user_data = Unmanaged.passUnretained(box).toOpaque()
        definitions.append(definition)
      }

      defer {
        for pointer in schemePointers {
          if let pointer { free(pointer) }
        }
      }

      return withOptionalCString(configuration.url) { urlPointer in
        var native = VeloxWebviewConfig(
          url: urlPointer,
          custom_protocols: VeloxCustomProtocolList(protocols: nil, count: 0),
          is_child: configuration.isChild,
          x: configuration.x,
          y: configuration.y,
          width: configuration.width,
          height: configuration.height
        )

        return definitions.withUnsafeBufferPointer { buffer in
          if let baseAddress = buffer.baseAddress, buffer.count > 0 {
            native.custom_protocols = VeloxCustomProtocolList(
              protocols: baseAddress,
              count: buffer.count
            )
          }

          return withUnsafePointer(to: native) { pointer in
            guard let handle = velox_webview_build(raw, pointer) else {
              return nil
            }
            guard let webview = Webview(raw: handle) else {
              return nil
            }
            webview.installCustomProtocolHandlers(handlerBoxes)
            return register(webview: webview)
          }
        }
      }
    } else {
      guard let handle = velox_webview_build(raw, nil) else {
        return nil
      }
      let webview = Webview(raw: handle)
        return register(webview: webview)
      }
    }

    private func register(webview: Webview?) -> Webview? {
      guard let webview else {
        return nil
      }
      if let owner {
        webview.register(owner: owner, windowIdentifier: ObjectIdentifier(self))
      }
      return webview
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      return title.withCString { velox_window_set_title(raw, $0) }
    }

    public func title() -> String {
      string(from: velox_window_title(raw))
    }

    @discardableResult
    public func setFullscreen(_ isFullscreen: Bool) -> Bool {
      return velox_window_set_fullscreen(raw, isFullscreen)
    }

    public func isFullscreen() -> Bool {
      velox_window_is_fullscreen(raw)
    }

    @discardableResult
    public func setDecorations(_ decorations: Bool) -> Bool {
      velox_window_set_decorations(raw, decorations)
    }

    @discardableResult
    public func setResizable(_ resizable: Bool) -> Bool {
      return velox_window_set_resizable(raw, resizable)
    }

    @discardableResult
    public func setAlwaysOnTop(_ onTop: Bool) -> Bool {
      return velox_window_set_always_on_top(raw, onTop)
    }

    @discardableResult
    public func setAlwaysOnBottom(_ onBottom: Bool) -> Bool {
      velox_window_set_always_on_bottom(raw, onBottom)
    }

    @discardableResult
    public func setVisibleOnAllWorkspaces(_ visible: Bool) -> Bool {
      velox_window_set_visible_on_all_workspaces(raw, visible)
    }

    @discardableResult
    public func setContentProtected(_ protected: Bool) -> Bool {
      velox_window_set_content_protected(raw, protected)
    }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
      return velox_window_set_visible(raw, visible)
    }

    @discardableResult
    public func setMaximized(_ maximized: Bool) -> Bool {
      velox_window_set_maximized(raw, maximized)
    }

    @discardableResult
    public func setMinimized(_ minimized: Bool) -> Bool {
      velox_window_set_minimized(raw, minimized)
    }

    @discardableResult
    public func setMinimizable(_ minimizable: Bool) -> Bool {
      velox_window_set_minimizable(raw, minimizable)
    }

    @discardableResult
    public func setMaximizable(_ maximizable: Bool) -> Bool {
      velox_window_set_maximizable(raw, maximizable)
    }

    @discardableResult
    public func setClosable(_ closable: Bool) -> Bool {
      velox_window_set_closable(raw, closable)
    }

    @discardableResult
    public func setSkipTaskbar(_ skip: Bool) -> Bool {
      velox_window_set_skip_taskbar(raw, skip)
    }

    @discardableResult
    public func setBackgroundColor(_ color: Color?) -> Bool {
      if let value = color {
        var ffiColor = value.toFFI()
        return withUnsafePointer(to: &ffiColor) { pointer in
          velox_window_set_background_color(raw, pointer)
        }
      } else {
        return velox_window_set_background_color(raw, nil)
      }
    }

    @discardableResult
    public func setTheme(_ theme: Theme?) -> Bool {
      let ffiTheme: VeloxWindowTheme
      switch theme {
      case .some(.light): ffiTheme = VELOX_WINDOW_THEME_LIGHT
      case .some(.dark): ffiTheme = VELOX_WINDOW_THEME_DARK
      case .none: ffiTheme = VELOX_WINDOW_THEME_UNSPECIFIED
      }
      return velox_window_set_theme(raw, ffiTheme)
    }

    public func currentMonitor() -> MonitorInfo? {
      decodeMonitorInfo(from: velox_window_current_monitor(raw))
    }

    public func primaryMonitor() -> MonitorInfo? {
      decodeMonitorInfo(from: velox_window_primary_monitor(raw))
    }

    public func availableMonitors() -> [MonitorInfo] {
      decodeMonitorInfoList(from: velox_window_available_monitors(raw))
    }

    public func monitor(at position: WindowPosition) -> MonitorInfo? {
      let point = VeloxPoint(x: position.x, y: position.y)
      return decodeMonitorInfo(from: velox_window_monitor_from_point(raw, point))
    }

    public func cursorPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_cursor_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func isMaximized() -> Bool {
      velox_window_is_maximized(raw)
    }

    public func isMinimized() -> Bool {
      velox_window_is_minimized(raw)
    }

    public func isVisible() -> Bool {
      velox_window_is_visible(raw)
    }

    public func isResizable() -> Bool {
      velox_window_is_resizable(raw)
    }

    public func isDecorated() -> Bool {
      velox_window_is_decorated(raw)
    }

    public func isAlwaysOnTop() -> Bool {
      velox_window_is_always_on_top(raw)
    }

    public func isMinimizable() -> Bool {
      velox_window_is_minimizable(raw)
    }

    public func isMaximizable() -> Bool {
      velox_window_is_maximizable(raw)
    }

    public func isClosable() -> Bool {
      velox_window_is_closable(raw)
    }

    public func scaleFactor() -> Double? {
      var value: Double = 0
      guard velox_window_scale_factor(raw, &value) else {
        return nil
      }
      return value
    }

    public func innerPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_inner_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func outerPosition() -> WindowPosition? {
      var point = VeloxPoint(x: 0, y: 0)
      guard velox_window_outer_position(raw, &point) else {
        return nil
      }
      return WindowPosition(x: point.x, y: point.y)
    }

    public func innerSize() -> WindowSize? {
      var size = VeloxSize(width: 0, height: 0)
      guard velox_window_inner_size(raw, &size) else {
        return nil
      }
          return WindowSize(width: size.width, height: size.height)
    }

    public func outerSize() -> WindowSize? {
      var size = VeloxSize(width: 0, height: 0)
      guard velox_window_outer_size(raw, &size) else {
        return nil
      }
      return WindowSize(width: size.width, height: size.height)
    }

    public func isFocused() -> Bool {
      velox_window_is_focused(raw)
    }

    public func events(
      bufferingPolicy: AsyncStream<WindowEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<WindowEvent> {
      guard let owner else {
        return AsyncStream { continuation in
          continuation.finish()
        }
      }
      return owner.windowEventStream(for: ObjectIdentifier(self), bufferingPolicy: bufferingPolicy)
    }

    @discardableResult
    public func focus() -> Bool {
      velox_window_focus(raw)
    }

    @discardableResult
    public func setFocusable(_ focusable: Bool) -> Bool {
      velox_window_set_focusable(raw, focusable)
    }

    @discardableResult
    public func requestRedraw() -> Bool {
      return velox_window_request_redraw(raw)
    }

    @discardableResult
    public func setSize(width: Double, height: Double) -> Bool {
      return velox_window_set_size(raw, width, height)
    }

    @discardableResult
    public func setPosition(x: Double, y: Double) -> Bool {
      return velox_window_set_position(raw, x, y)
    }

    @discardableResult
    public func setMinimumSize(width: Double, height: Double) -> Bool {
      return velox_window_set_min_size(raw, width, height)
    }

    @discardableResult
    public func setMaximumSize(width: Double, height: Double) -> Bool {
      return velox_window_set_max_size(raw, width, height)
    }

    @discardableResult
    public func requestUserAttention(_ type: AttentionType) -> Bool {
      let ffiType = VeloxUserAttentionType(rawValue: UInt32(type.rawValue))
      return velox_window_request_user_attention(raw, ffiType)
    }

    @discardableResult
    public func clearUserAttention() -> Bool {
      velox_window_clear_user_attention(raw)
    }

    @discardableResult
    public func startDragging() -> Bool {
      velox_window_start_dragging(raw)
    }

    @discardableResult
    public func startResizeDragging(_ direction: ResizeDirection) -> Bool {
      let ffiDirection = VeloxResizeDirection(rawValue: UInt32(direction.rawValue))
      return velox_window_start_resize_dragging(raw, ffiDirection)
    }

    @discardableResult
    public func setCursorGrab(_ grab: Bool) -> Bool {
      velox_window_set_cursor_grab(raw, grab)
    }

    @discardableResult
    public func setCursorVisible(_ visible: Bool) -> Bool {
      velox_window_set_cursor_visible(raw, visible)
    }

    @discardableResult
    public func setCursorPosition(x: Double, y: Double) -> Bool {
      velox_window_set_cursor_position(raw, x, y)
    }

    @discardableResult
    public func setIgnoreCursorEvents(_ ignore: Bool) -> Bool {
      velox_window_set_ignore_cursor_events(raw, ignore)
    }
  }

  /// Handle wrapper mirroring Wry's `WebView`.
  final class Webview {
    private let raw: UnsafeMutablePointer<VeloxWebviewHandle>
    private weak var owner: Runtime?
    private var windowIdentifier: ObjectIdentifier?
    private var customProtocolHandlers: [VeloxCustomProtocolHandlerBox] = []

    /// The internal webview identifier used by wry for custom protocol callbacks
    public private(set) lazy var identifier: String = {
      guard let ptr = velox_webview_identifier(raw) else {
        return ""
      }
      let str = String(cString: ptr)
      free(UnsafeMutablePointer(mutating: ptr))
      return str
    }()

    fileprivate init?(raw: UnsafeMutablePointer<VeloxWebviewHandle>?) {
      guard let raw else {
        return nil
      }
      self.raw = raw
    }

    deinit {
      velox_webview_free(raw)
    }

    fileprivate func register(owner: Runtime, windowIdentifier: ObjectIdentifier) {
      self.owner = owner
      self.windowIdentifier = windowIdentifier
    }

    func installCustomProtocolHandlers(_ handlers: [VeloxCustomProtocolHandlerBox]) {
      customProtocolHandlers = handlers
    }

    public func events(
      bufferingPolicy: AsyncStream<WebviewEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<WebviewEvent> {
      guard let owner, let windowIdentifier else {
        return AsyncStream { continuation in
          continuation.finish()
        }
      }
      return owner.webviewEventStream(for: windowIdentifier, bufferingPolicy: bufferingPolicy)
    }

    @discardableResult
    public func navigate(to url: String) -> Bool {
      url.withCString { velox_webview_navigate(raw, $0) }
    }

    @discardableResult
    public func reload() -> Bool {
      velox_webview_reload(raw)
    }

    @discardableResult
    public func evaluate(script: String) -> Bool {
      script.withCString { velox_webview_evaluate_script(raw, $0) }
    }

    @discardableResult
    public func setZoom(_ scale: Double) -> Bool {
      velox_webview_set_zoom(raw, scale)
    }

    @discardableResult
    public func show() -> Bool {
      velox_webview_show(raw)
    }

    @discardableResult
    public func hide() -> Bool {
      velox_webview_hide(raw)
    }

    @discardableResult
    public func clearBrowsingData() -> Bool {
      velox_webview_clear_browsing_data(raw)
    }

    /// Set the bounds of a child webview.
    @discardableResult
    public func setBounds(x: Double, y: Double, width: Double, height: Double) -> Bool {
      velox_webview_set_bounds(raw, x, y, width, height)
    }
  }
}

public extension VeloxRuntimeWry {
  struct WindowSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
    }
  }

  struct WindowPosition: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  struct MonitorInfo: Sendable, Equatable {
    public var name: String
    public var position: WindowPosition
    public var size: WindowSize
    public var scaleFactor: Double

    public init(name: String, position: WindowPosition, size: WindowSize, scaleFactor: Double) {
      self.name = name
      self.position = position
      self.size = size
      self.scaleFactor = scaleFactor
    }
  }

  struct TrayRect: Sendable, Equatable {
    public var origin: WindowPosition
    public var size: WindowSize

    public init(origin: WindowPosition, size: WindowSize) {
      self.origin = origin
      self.size = size
    }
  }

  struct TrayEvent: Sendable, Equatable {
    public enum EventType: String, Sendable, Equatable {
      case click
      case doubleClick = "double-click"
      case enter
      case move
      case leave
      case unknown
    }

    public var identifier: String
    public var type: EventType
    public var button: String?
    public var buttonState: String?
    public var position: WindowPosition?
    public var rect: TrayRect?

    public init(
      identifier: String,
      type: EventType,
      button: String?,
      buttonState: String?,
      position: WindowPosition?,
      rect: TrayRect?
    ) {
      self.identifier = identifier
      self.type = type
      self.button = button
      self.buttonState = buttonState
      self.position = position
      self.rect = rect
    }
  }

  struct KeyboardInput: Sendable, Equatable {
    public var state: String
    public var logicalKey: String
    public var physicalKey: String
    public var text: String?
    public var isRepeat: Bool
    public var location: String
    public var isSynthetic: Bool

    public init(
      state: String,
      logicalKey: String,
      physicalKey: String,
      text: String?,
      isRepeat: Bool,
      location: String,
      isSynthetic: Bool
    ) {
      self.state = state
      self.logicalKey = logicalKey
      self.physicalKey = physicalKey
      self.text = text
      self.isRepeat = isRepeat
      self.location = location
      self.isSynthetic = isSynthetic
    }
  }

  struct Modifiers: Sendable, Equatable {
    public var shift: Bool
    public var control: Bool
    public var alt: Bool
    public var superKey: Bool

    public init(shift: Bool, control: Bool, alt: Bool, superKey: Bool) {
      self.shift = shift
      self.control = control
      self.alt = alt
      self.superKey = superKey
    }
  }

  struct MouseInput: Sendable, Equatable {
    public var state: String
    public var button: String

    public init(state: String, button: String) {
      self.state = state
      self.button = button
    }
  }

  struct MouseWheelDelta: Sendable, Equatable {
    public enum Unit: String, Sendable, Equatable {
      case line
      case pixel
      case unknown
    }

    public var unit: Unit
    public var x: Double?
    public var y: Double?

    public init(unit: Unit, x: Double?, y: Double?) {
      self.unit = unit
      self.x = x
      self.y = y
    }
  }

  struct UserDefinedPayload: Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONEncoder()) throws {
      let data = try encoder.encode(value)
      guard let string = String(data: data, encoding: .utf8) else {
        throw VeloxRuntimeError.failed(description: "Unable to encode user event payload as UTF-8")
      }
      self.rawValue = string
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
      guard let data = rawValue.data(using: .utf8) else {
        return nil
      }
      return try? decoder.decode(T.self, from: data)
    }
  }

  enum Event: Sendable, Equatable {
    case ready
    case newEvents(cause: String)
    case mainEventsCleared
    case redrawEventsCleared
    case loopDestroyed
    case exit
    case suspended
    case resumed
    case windowRedrawRequested(windowId: String)
    case userExit
    case exitRequested(code: Int32?)
    case deviceEvent(deviceId: String, description: String)
    case opened(urls: [String])
    case reopen(hasVisibleWindows: Bool)
    case windowCloseRequested(windowId: String)
    case windowDestroyed(windowId: String)
    case windowResized(windowId: String, size: WindowSize)
    case windowMoved(windowId: String, position: WindowPosition)
    case windowFocused(windowId: String, isFocused: Bool)
    case windowScaleFactorChanged(windowId: String, scaleFactor: Double, size: WindowSize)
    case windowKeyboardInput(windowId: String, input: KeyboardInput)
    case windowImeText(windowId: String, text: String)
    case windowModifiersChanged(windowId: String, modifiers: Modifiers)
    case windowCursorMoved(windowId: String, position: WindowPosition)
    case windowCursorEntered(windowId: String, deviceId: String)
    case windowCursorLeft(windowId: String, deviceId: String)
    case windowMouseInput(windowId: String, input: MouseInput)
    case windowMouseWheel(windowId: String, delta: MouseWheelDelta, phase: String)
    case webviewEvent(label: String, description: String)
    case windowDroppedFile(windowId: String, path: String)
    case windowHoveredFile(windowId: String, path: String)
    case windowHoveredFileCancelled(windowId: String)
    case windowThemeChanged(windowId: String, theme: String)
    case windowEvent(windowId: String, description: String)
    case userDefined(payload: UserDefinedPayload)
    case menuEvent(menuId: String)
    case trayEvent(event: TrayEvent)
    case raw(description: String)
    case unknown(json: String)

    init(fromJSON json: String) {
      guard
        let data = json.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let type = VeloxEventDecoder.string(object["type"])
      else {
        self = .unknown(json: json)
        return
      }

      switch type {
      case "ready":
        self = .ready
      case "new-events":
        let cause = VeloxEventDecoder.string(object["cause"]) ?? "unknown"
        self = .newEvents(cause: cause)
      case "main-events-cleared":
        self = .mainEventsCleared
      case "redraw-events-cleared":
        self = .redrawEventsCleared
      case "loop-destroyed":
        self = .loopDestroyed
      case "exit":
        self = .exit
      case "suspended":
        self = .suspended
      case "resumed":
        self = .resumed
      case "window-redraw-requested":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowRedrawRequested(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "user-exit":
        self = .userExit
      case "exit-requested":
        let codeValue = VeloxEventDecoder.double(object["code"]).map { Int32($0) }
        self = .exitRequested(code: codeValue)
      case "device-event":
        if
          let deviceId = VeloxEventDecoder.string(object["device_id"]),
          let description = VeloxEventDecoder.string(object["event"])
        {
          self = .deviceEvent(deviceId: deviceId, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "opened":
        let urls = VeloxEventDecoder.array(object["urls"])?.compactMap { VeloxEventDecoder.string($0) } ?? []
        self = .opened(urls: urls)
      case "reopen":
        let hasVisible = VeloxEventDecoder.bool(object["has_visible_windows"]) ?? false
        self = .reopen(hasVisibleWindows: hasVisible)
      case "window-close-requested":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowCloseRequested(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-destroyed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowDestroyed(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-resized":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let size = Event.decodeSize(VeloxEventDecoder.dictionary(object["size"])) ?? WindowSize(width: 0, height: 0)
          self = .windowResized(windowId: windowId, size: size)
        } else {
          self = .unknown(json: json)
        }
      case "window-moved":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"])) ?? WindowPosition(x: 0, y: 0)
          self = .windowMoved(windowId: windowId, position: position)
        } else {
          self = .unknown(json: json)
        }
      case "window-focused":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let focused = VeloxEventDecoder.bool(object["focused"]) ?? false
          self = .windowFocused(windowId: windowId, isFocused: focused)
        } else {
          self = .unknown(json: json)
        }
      case "window-scale-factor-changed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let scale = VeloxEventDecoder.double(object["scale_factor"]) ?? 1
          let size = Event.decodeSize(VeloxEventDecoder.dictionary(object["size"])) ?? WindowSize(width: 0, height: 0)
          self = .windowScaleFactorChanged(windowId: windowId, scaleFactor: scale, size: size)
        } else {
          self = .unknown(json: json)
        }
      case "window-keyboard-input":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let input = KeyboardInput(
            state: VeloxEventDecoder.string(object["state"]) ?? "unknown",
            logicalKey: VeloxEventDecoder.string(object["logical_key"]) ?? "unknown",
            physicalKey: VeloxEventDecoder.string(object["physical_key"]) ?? "unknown",
            text: VeloxEventDecoder.string(object["text"]),
            isRepeat: VeloxEventDecoder.bool(object["repeat"]) ?? false,
            location: VeloxEventDecoder.string(object["location"]) ?? "unknown",
            isSynthetic: VeloxEventDecoder.bool(object["is_synthetic"]) ?? false
          )
          self = .windowKeyboardInput(windowId: windowId, input: input)
        } else {
          self = .unknown(json: json)
        }
      case "window-ime-text":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let text = VeloxEventDecoder.string(object["text"])
        {
          self = .windowImeText(windowId: windowId, text: text)
        } else {
          self = .unknown(json: json)
        }
      case "window-modifiers-changed":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let modifiersObject = VeloxEventDecoder.dictionary(object["modifiers"]) ?? [:]
          let modifiers = Modifiers(
            shift: VeloxEventDecoder.bool(modifiersObject["shift"]) ?? false,
            control: VeloxEventDecoder.bool(modifiersObject["control"]) ?? false,
            alt: VeloxEventDecoder.bool(modifiersObject["alt"]) ?? false,
            superKey: VeloxEventDecoder.bool(modifiersObject["super_key"]) ?? false
          )
          self = .windowModifiersChanged(windowId: windowId, modifiers: modifiers)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-moved":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"])) ?? WindowPosition(x: 0, y: 0)
          self = .windowCursorMoved(windowId: windowId, position: position)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-entered":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let deviceId = VeloxEventDecoder.string(object["device_id"])
        {
          self = .windowCursorEntered(windowId: windowId, deviceId: deviceId)
        } else {
          self = .unknown(json: json)
        }
      case "window-cursor-left":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let deviceId = VeloxEventDecoder.string(object["device_id"])
        {
          self = .windowCursorLeft(windowId: windowId, deviceId: deviceId)
        } else {
          self = .unknown(json: json)
        }
      case "window-mouse-input":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let input = MouseInput(
            state: VeloxEventDecoder.string(object["state"]) ?? "unknown",
            button: VeloxEventDecoder.string(object["button"]) ?? "unknown"
          )
          self = .windowMouseInput(windowId: windowId, input: input)
        } else {
          self = .unknown(json: json)
        }
      case "window-mouse-wheel":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          let deltaObject = VeloxEventDecoder.dictionary(object["delta"]) ?? [:]
          let unitString = VeloxEventDecoder.string(deltaObject["unit"]) ?? MouseWheelDelta.Unit.unknown.rawValue
          let delta = MouseWheelDelta(
            unit: MouseWheelDelta.Unit(rawValue: unitString) ?? .unknown,
            x: VeloxEventDecoder.double(deltaObject["x"]),
            y: VeloxEventDecoder.double(deltaObject["y"])
          )
          let phase = VeloxEventDecoder.string(object["phase"]) ?? "unknown"
          self = .windowMouseWheel(windowId: windowId, delta: delta, phase: phase)
        } else {
          self = .unknown(json: json)
        }
      case "webview-event":
        if
          let label = VeloxEventDecoder.string(object["label"]),
          let description = VeloxEventDecoder.string(object["event"])
        {
          self = .webviewEvent(label: label, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "window-dropped-file":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let path = VeloxEventDecoder.string(object["path"])
        {
          self = .windowDroppedFile(windowId: windowId, path: path)
        } else {
          self = .unknown(json: json)
        }
      case "window-hovered-file":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let path = VeloxEventDecoder.string(object["path"])
        {
          self = .windowHoveredFile(windowId: windowId, path: path)
        } else {
          self = .unknown(json: json)
        }
      case "window-hovered-file-cancelled":
        if let windowId = VeloxEventDecoder.string(object["window_id"]) {
          self = .windowHoveredFileCancelled(windowId: windowId)
        } else {
          self = .unknown(json: json)
        }
      case "window-theme-changed":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let theme = VeloxEventDecoder.string(object["theme"])
        {
          self = .windowThemeChanged(windowId: windowId, theme: theme)
        } else {
          self = .unknown(json: json)
        }
      case "window-event":
        if
          let windowId = VeloxEventDecoder.string(object["window_id"]),
          let description = VeloxEventDecoder.string(object["kind"])
        {
          self = .windowEvent(windowId: windowId, description: description)
        } else {
          self = .unknown(json: json)
        }
      case "user-event":
        if VeloxEventDecoder.string(object["event"])?.lowercased() == "exit" {
          self = .userExit
        } else {
          let payload = VeloxEventDecoder.string(object["payload"]) ?? ""
          self = .userDefined(payload: UserDefinedPayload(rawValue: payload))
        }
      case "menu-event":
        if let menuId = VeloxEventDecoder.string(object["menu_id"]) {
          self = .menuEvent(menuId: menuId)
        } else {
          self = .unknown(json: json)
        }
      case "tray-event":
        let identifier = VeloxEventDecoder.string(object["tray_id"]) ?? ""
        let eventTypeString = VeloxEventDecoder.string(object["event_type"]) ?? "unknown"
        let eventType = TrayEvent.EventType(rawValue: eventTypeString) ?? .unknown
        let position = Event.decodePosition(VeloxEventDecoder.dictionary(object["position"]))
        let rect = Event.decodeTrayRect(VeloxEventDecoder.dictionary(object["rect"]))
        let button = VeloxEventDecoder.string(object["button"])
        let buttonState = VeloxEventDecoder.string(object["button_state"])
        self = .trayEvent(
          event: TrayEvent(
            identifier: identifier,
            type: eventType,
            button: button,
            buttonState: buttonState,
            position: position,
            rect: rect
          )
        )
      case "raw":
        let description = VeloxEventDecoder.string(object["debug"]) ?? json
        self = .raw(description: description)
      default:
        self = .unknown(json: json)
      }
    }

  private static func decodeSize(_ dictionary: [String: Any]?) -> WindowSize? {
    guard let dictionary else { return nil }
    guard
      let width = VeloxEventDecoder.double(dictionary["width"]),
      let height = VeloxEventDecoder.double(dictionary["height"])
      else {
        return nil
      }
      return WindowSize(width: width, height: height)
    }

  private static func decodePosition(_ dictionary: [String: Any]?) -> WindowPosition? {
    guard let dictionary else { return nil }
    guard
      let x = VeloxEventDecoder.double(dictionary["x"]),
      let y = VeloxEventDecoder.double(dictionary["y"])
    else {
      return nil
    }
    return WindowPosition(x: x, y: y)
  }

  private static func decodeTrayRect(_ dictionary: [String: Any]?) -> TrayRect? {
    guard
      let dictionary,
      let x = VeloxEventDecoder.double(dictionary["x"]),
      let y = VeloxEventDecoder.double(dictionary["y"]),
      let width = VeloxEventDecoder.double(dictionary["width"]),
      let height = VeloxEventDecoder.double(dictionary["height"])
    else {
      return nil
    }
    return TrayRect(
      origin: WindowPosition(x: x, y: y),
      size: WindowSize(width: width, height: height)
    )
  }
  }
}

public extension VeloxRuntimeWry {
  enum WindowEvent: Sendable, Equatable {
    case closeRequested(label: String)
    case destroyed(label: String)
    case resized(label: String, size: WindowSize)
    case moved(label: String, position: WindowPosition)
    case focused(label: String, isFocused: Bool)
    case scaleFactorChanged(label: String, scaleFactor: Double, size: WindowSize)
    case keyboardInput(label: String, input: KeyboardInput)
    case imeText(label: String, text: String)
    case modifiersChanged(label: String, modifiers: Modifiers)
    case cursorMoved(label: String, position: WindowPosition)
    case cursorEntered(label: String, deviceId: String)
    case cursorLeft(label: String, deviceId: String)
    case mouseInput(label: String, input: MouseInput)
    case mouseWheel(label: String, delta: MouseWheelDelta, phase: String)
    case droppedFile(label: String, path: String)
    case hoveredFile(label: String, path: String)
    case hoveredFileCancelled(label: String)
    case themeChanged(label: String, theme: String)
    case raw(label: String, description: String)
    case redrawRequested(label: String)
    case other(label: String, event: VeloxRuntimeWry.Event)
  }

  enum WebviewEvent: Sendable, Equatable {
    case userEvent(label: String, description: String)
    case other(label: String, event: VeloxRuntimeWry.Event)
  }

  static func makeWindowEvent(label: String, event: VeloxRuntimeWry.Event) -> WindowEvent {
    switch event {
    case .windowCloseRequested:
      return .closeRequested(label: label)
    case .windowDestroyed:
      return .destroyed(label: label)
    case .windowResized(_, let size):
      return .resized(label: label, size: size)
    case .windowMoved(_, let position):
      return .moved(label: label, position: position)
    case .windowFocused(_, let isFocused):
      return .focused(label: label, isFocused: isFocused)
    case .windowScaleFactorChanged(_, let scaleFactor, let size):
      return .scaleFactorChanged(label: label, scaleFactor: scaleFactor, size: size)
    case .windowKeyboardInput(_, let input):
      return .keyboardInput(label: label, input: input)
    case .windowImeText(_, let text):
      return .imeText(label: label, text: text)
    case .windowModifiersChanged(_, let modifiers):
      return .modifiersChanged(label: label, modifiers: modifiers)
    case .windowCursorMoved(_, let position):
      return .cursorMoved(label: label, position: position)
    case .windowCursorEntered(_, let deviceId):
      return .cursorEntered(label: label, deviceId: deviceId)
    case .windowCursorLeft(_, let deviceId):
      return .cursorLeft(label: label, deviceId: deviceId)
    case .windowMouseInput(_, let input):
      return .mouseInput(label: label, input: input)
    case .windowMouseWheel(_, let delta, let phase):
      return .mouseWheel(label: label, delta: delta, phase: phase)
    case .windowDroppedFile(_, let path):
      return .droppedFile(label: label, path: path)
    case .windowHoveredFile(_, let path):
      return .hoveredFile(label: label, path: path)
    case .windowHoveredFileCancelled:
      return .hoveredFileCancelled(label: label)
    case .windowThemeChanged(_, let theme):
      return .themeChanged(label: label, theme: theme)
    case .windowEvent(_, let description):
      return .raw(label: label, description: description)
    case .windowRedrawRequested:
      return .redrawRequested(label: label)
    default:
      return .other(label: label, event: event)
    }
  }

  static func makeWebviewEvent(label: String, event: VeloxRuntimeWry.Event) -> WebviewEvent {
    switch event {
    case .webviewEvent(_, let description):
      return .userEvent(label: label, description: description)
    default:
      return .other(label: label, event: event)
    }
  }

  enum MenuEvent: Sendable, Equatable {
    case activated(identifier: String)
    case other(identifier: String, event: VeloxRuntimeWry.Event)
  }

  struct TrayEventNotification: Sendable, Equatable {
    public let identifier: String
    public let event: TrayEvent

    public init(identifier: String, event: TrayEvent) {
      self.identifier = identifier
      self.event = event
    }
  }
}

private enum VeloxEventDecoder {
  static func string(_ value: Any?) -> String? {
    if let string = value as? String {
      return string
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  static func double(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  static func bool(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
      return bool
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    if let string = value as? String {
      switch string.lowercased() {
      case "true", "1", "yes", "y":
        return true
      case "false", "0", "no", "n":
        return false
      default:
        return nil
      }
    }
    return nil
  }

  static func dictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  static func array(_ value: Any?) -> [Any]? {
    value as? [Any]
  }
}

extension VeloxRuntimeWry.Runtime: VeloxRuntimeHandle {
  public typealias WindowDispatcher = VeloxRuntimeWry.Window
  public typealias WebviewDispatcher = VeloxRuntimeWry.Webview
}

extension VeloxRuntimeWry.Window: VeloxWindowDispatcher {
  public typealias Event = VeloxRuntimeWry.Event
  public typealias Identifier = ObjectIdentifier
}

extension VeloxRuntimeWry.Webview: VeloxWebviewDispatcher {
  public typealias Event = VeloxRuntimeWry.Event
  public typealias Identifier = ObjectIdentifier
}

extension VeloxRuntimeWry.Event: VeloxUserEvent {}

public final class EventLoopProxyAdapter: VeloxEventLoopProxy {
  public typealias Event = VeloxRuntimeWry.Event

  private let proxy: VeloxRuntimeWry.EventLoopProxy

  init(proxy: VeloxRuntimeWry.EventLoopProxy) {
    self.proxy = proxy
  }

  public func send(event: VeloxRuntimeWry.Event) throws {
    switch event {
    case .userExit, .exitRequested(_):
      guard proxy.requestExit() else {
        throw VeloxRuntimeError.failed(description: "failed to signal event loop")
      }
    case .userDefined(let payload):
      guard proxy.sendUserEvent(payload.rawValue) else {
        throw VeloxRuntimeError.failed(description: "failed to send user event")
      }
    default:
      throw VeloxRuntimeError.unsupported
    }
  }

  public func sendUserEvent<T: Encodable>(
    _ payload: T,
    encoder: JSONEncoder = JSONEncoder()
  ) throws {
    let encoded = try VeloxRuntimeWry.UserDefinedPayload(encoding: payload, encoder: encoder)
    try send(event: .userDefined(payload: encoded))
  }
}

#if os(macOS)
public extension VeloxRuntimeWry {
  final class MenuBar: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxMenuBarHandle>
    private var retainedSubmenus: [Submenu] = []

    public let identifier: String

    public init?(identifier: String? = nil) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxMenuBarHandle>? = withOptionalCString(identifier ?? "") { idPointer in
        if let idPointer {
          velox_menu_bar_new_with_id(idPointer)
        } else {
          velox_menu_bar_new()
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_menu_bar_identifier(handle))
    }

    deinit {
      velox_menu_bar_free(raw)
    }

    @discardableResult
    public func append(_ submenu: Submenu) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_menu_bar_append_submenu(raw, submenu.raw) else {
        return false
      }
      retainedSubmenus.append(submenu)
      return true
    }

    @discardableResult
    public func setAsApplicationMenu() -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_menu_bar_set_app_menu(raw)
    }
  }

  final class Submenu: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxSubmenuHandle>
    private var retainedItems: [AnyObject] = []

    public let identifier: String

    public init?(title: String, identifier: String? = nil, isEnabled: Bool = true) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxSubmenuHandle>? = title.withCString { titlePointer in
        withOptionalCString(identifier ?? "") { idPointer in
          if let idPointer {
            velox_submenu_new_with_id(idPointer, titlePointer, isEnabled)
          } else {
            velox_submenu_new(titlePointer, isEnabled)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_submenu_identifier(handle))
    }

    deinit {
      velox_submenu_free(raw)
    }

    @discardableResult
    public func append(_ item: MenuItem) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_submenu_append_item(raw, item.raw) else {
        return false
      }
      retainedItems.append(item)
      return true
    }

    @discardableResult
    public func append(_ item: CheckMenuItem) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_submenu_append_check_item(raw, item.raw) else {
        return false
      }
      retainedItems.append(item)
      return true
    }

    @discardableResult
    public func append(_ separator: MenuSeparator) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      guard velox_submenu_append_separator(raw, separator.raw) else {
        return false
      }
      retainedItems.append(separator)
      return true
    }

    /// Convenience method to append a separator
    @discardableResult
    public func appendSeparator() -> Bool {
      guard let separator = MenuSeparator() else {
        return false
      }
      return append(separator)
    }
  }

  final class MenuItem: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxMenuItemHandle>
    public let identifier: String

    public init?(
      identifier: String? = nil,
      title: String,
      isEnabled: Bool = true,
      accelerator: String? = nil
    ) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxMenuItemHandle>? = title.withCString { titlePointer in
        withOptionalCString(identifier ?? "") { idPointer in
          withOptionalCString(accelerator ?? "") { acceleratorPointer in
            velox_menu_item_new(idPointer, titlePointer, isEnabled, acceleratorPointer)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_menu_item_identifier(handle))
    }

    deinit {
      velox_menu_item_free(raw)
    }

    public func title() -> String {
      guard Thread.isMainThread else {
        return ""
      }
      return string(from: velox_menu_item_text(raw))
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return title.withCString { pointer in
        velox_menu_item_set_text(raw, pointer)
      }
    }

    @discardableResult
    public func setEnabled(_ isEnabled: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_menu_item_set_enabled(raw, isEnabled)
    }

    public func isEnabled() -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_menu_item_is_enabled(raw)
    }

    @discardableResult
    public func setAccelerator(_ accelerator: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      if let accelerator {
        return accelerator.withCString { pointer in
          velox_menu_item_set_accelerator(raw, pointer)
        }
      }
      return velox_menu_item_set_accelerator(raw, nil)
    }
  }

  /// A separator menu item that displays a horizontal line in a menu
  final class MenuSeparator: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxSeparatorHandle>
    public let identifier: String

    public init?() {
      guard Thread.isMainThread else {
        return nil
      }

      guard let handle = velox_separator_new() else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_separator_identifier(handle))
    }

    deinit {
      velox_separator_free(raw)
    }
  }

  /// A menu item with a checkmark that can be toggled
  final class CheckMenuItem: @unchecked Sendable {
    fileprivate let raw: UnsafeMutablePointer<VeloxCheckMenuItemHandle>
    public let identifier: String

    public init?(
      identifier: String? = nil,
      title: String,
      isEnabled: Bool = true,
      isChecked: Bool = false,
      accelerator: String? = nil
    ) {
      guard Thread.isMainThread else {
        return nil
      }

      let handle: UnsafeMutablePointer<VeloxCheckMenuItemHandle>? = title.withCString { titlePointer in
        withOptionalCString(identifier ?? "") { idPointer in
          withOptionalCString(accelerator ?? "") { acceleratorPointer in
            velox_check_menu_item_new(idPointer, titlePointer, isEnabled, isChecked, acceleratorPointer)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_check_menu_item_identifier(handle))
    }

    deinit {
      velox_check_menu_item_free(raw)
    }

    public func title() -> String {
      guard Thread.isMainThread else {
        return ""
      }
      return string(from: velox_check_menu_item_text(raw))
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return title.withCString { pointer in
        velox_check_menu_item_set_text(raw, pointer)
      }
    }

    @discardableResult
    public func setEnabled(_ isEnabled: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_check_menu_item_set_enabled(raw, isEnabled)
    }

    public func isEnabled() -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_check_menu_item_is_enabled(raw)
    }

    public func isChecked() -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_check_menu_item_is_checked(raw)
    }

    @discardableResult
    public func setChecked(_ isChecked: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_check_menu_item_set_checked(raw, isChecked)
    }

    @discardableResult
    public func setAccelerator(_ accelerator: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      if let accelerator {
        return accelerator.withCString { pointer in
          velox_check_menu_item_set_accelerator(raw, pointer)
        }
      }
      return velox_check_menu_item_set_accelerator(raw, nil)
    }
  }

  final class TrayIcon: @unchecked Sendable {
    private let raw: UnsafeMutablePointer<VeloxTrayHandle>

    public let identifier: String

    public init?(
      identifier: String? = nil,
      title: String? = nil,
      tooltip: String? = nil,
      visible: Bool = true,
      showMenuOnLeftClick: Bool = true
    ) {
      guard Thread.isMainThread else {
        return nil
      }

      var config = VeloxTrayConfig(
        identifier: nil,
        title: nil,
        tooltip: nil,
        visible: visible,
        show_menu_on_left_click: showMenuOnLeftClick
      )

      let handle: UnsafeMutablePointer<VeloxTrayHandle>? = withOptionalCString(identifier ?? "") { identifierPointer in
        config.identifier = identifierPointer
        return withOptionalCString(title ?? "") { titlePointer in
          config.title = titlePointer
          return withOptionalCString(tooltip ?? "") { tooltipPointer in
            config.tooltip = tooltipPointer
            return velox_tray_new(&config)
          }
        }
      }

      guard let handle else {
        return nil
      }

      self.raw = handle
      self.identifier = string(from: velox_tray_identifier(handle))
    }

    deinit {
      velox_tray_free(raw)
    }

    @discardableResult
    public func setTitle(_ title: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return withOptionalCString(title ?? "") { pointer in
        velox_tray_set_title(raw, pointer)
      }
    }

    @discardableResult
    public func setTooltip(_ tooltip: String?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return withOptionalCString(tooltip ?? "") { pointer in
        velox_tray_set_tooltip(raw, pointer)
      }
    }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_visible(raw, visible)
    }

    @discardableResult
    public func setShowMenuOnLeftClick(_ enable: Bool) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_show_menu_on_left_click(raw, enable)
    }

    @discardableResult
    public func setMenu(_ menu: MenuBar?) -> Bool {
      guard Thread.isMainThread else {
        return false
      }
      return velox_tray_set_menu(raw, menu?.raw)
    }
  }
}
#endif

private func decodeMonitorInfo(from pointer: UnsafePointer<CChar>?) -> VeloxRuntimeWry.MonitorInfo? {
  guard let pointer else {
    return nil
  }

  let jsonString = String(cString: pointer)
  guard let data = jsonString.data(using: .utf8),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let monitor = decodeMonitorInfo(dictionary: object)
  else {
    return nil
  }
  return monitor
}

private func decodeMonitorInfoList(from pointer: UnsafePointer<CChar>?) -> [VeloxRuntimeWry.MonitorInfo] {
  guard let pointer else {
    return []
  }

  let jsonString = String(cString: pointer)
  guard let data = jsonString.data(using: .utf8),
    let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
  else {
    return []
  }

  return array.compactMap { element in
    guard let dictionary = element as? [String: Any] else {
      return nil
    }
    return decodeMonitorInfo(dictionary: dictionary)
  }
}

private func decodeMonitorInfo(dictionary: [String: Any]) -> VeloxRuntimeWry.MonitorInfo? {
  guard
    let scaleFactor = VeloxEventDecoder.double(dictionary["scale_factor"]),
    let positionDictionary = VeloxEventDecoder.dictionary(dictionary["position"]),
    let sizeDictionary = VeloxEventDecoder.dictionary(dictionary["size"])
  else {
    return nil
  }

  let position = VeloxRuntimeWry.WindowPosition(
    x: VeloxEventDecoder.double(positionDictionary["x"]) ?? 0,
    y: VeloxEventDecoder.double(positionDictionary["y"]) ?? 0
  )

  let size = VeloxRuntimeWry.WindowSize(
    width: VeloxEventDecoder.double(sizeDictionary["width"]) ?? 0,
    height: VeloxEventDecoder.double(sizeDictionary["height"]) ?? 0
  )

  let name = VeloxEventDecoder.string(dictionary["name"]) ?? ""

  return VeloxRuntimeWry.MonitorInfo(
    name: name,
    position: position,
    size: size,
    scaleFactor: scaleFactor
  )
}

private func string(from pointer: UnsafePointer<CChar>?) -> String {
  guard let pointer else {
    return ""
  }
  return String(cString: pointer)
}

private func withOptionalCString<R>(
  _ string: String,
  perform: (UnsafePointer<CChar>?) -> R
) -> R {
  if string.isEmpty {
    return perform(nil)
  }

  return string.withCString { pointer in
    perform(pointer)
  }
}
