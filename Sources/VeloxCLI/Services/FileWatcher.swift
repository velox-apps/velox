import Foundation
import Logging
#if canImport(CoreServices)
import CoreServices
#endif

/// Describes what types of files changed
struct FileChangeResult: Sendable {
  let hasBackendChanges: Bool    // .swift files
  let hasFrontendChanges: Bool   // .html, .css, .js, etc.
  let hasConfigChanges: Bool     // velox.json
  let changedPaths: [String]

  /// True if only frontend assets changed (no rebuild needed)
  var isFrontendOnly: Bool {
    hasFrontendChanges && !hasBackendChanges && !hasConfigChanges
  }
}

#if canImport(CoreServices)
final class FileWatcher: @unchecked Sendable {
  private let paths: [String]
  private let debounceInterval: TimeInterval
  private var stream: FSEventStreamRef?
  private var continuation: CheckedContinuation<FileChangeResult, Never>?
  private var lastEventTime: Date = .distantPast
  private let queue = DispatchQueue(label: "com.velox.filewatcher")
  private var pendingChanges: [String] = []

  /// Patterns to ignore (simple suffix matching)
  private let ignorePatterns = [
    ".build/",
    ".git/",
    "node_modules/",
    ".DS_Store",
    ".swp",
    "~",
  ]

  init(paths: [String], debounceInterval: TimeInterval = 1.0) {
    self.paths = paths.map { path in
      if path.hasPrefix("/") {
        return path
      }
      return FileManager.default.currentDirectoryPath + "/" + path
    }
    self.debounceInterval = debounceInterval
  }

  deinit {
    stop()
  }

  /// Waits until a relevant file change is detected
  /// Returns information about what types of files changed
  func waitForChange() async -> FileChangeResult {
    logger.debug("Starting file watcher for paths: \(paths)")
    return await withCheckedContinuation { (cont: CheckedContinuation<FileChangeResult, Never>) in
      queue.async { [weak self] in
        self?.pendingChanges = []
        self?.continuation = cont
        self?.start()
        logger.debug("FSEvents stream started")
      }
    }
  }

  private func start() {
    guard stream == nil else {
      logger.debug("Stream already exists, skipping start")
      return
    }

    var context = FSEventStreamContext()
    context.info = Unmanaged.passUnretained(self).toOpaque()

    let callback: FSEventStreamCallback = {
      (
        streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds
      ) in
      guard let info = clientCallBackInfo else {
        logger.error("FSEvents clientCallBackInfo is nil")
        return
      }
      let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

      let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
      watcher.handleEvents(paths: paths)
    }

    let pathsToWatch = paths as CFArray
    logger.debug("Creating FSEventStream for: \(paths)")

    stream = FSEventStreamCreate(
      nil,
      callback,
      &context,
      pathsToWatch,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      debounceInterval,
      UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
    )

    if let stream = stream {
      FSEventStreamSetDispatchQueue(stream, queue)
      let started = FSEventStreamStart(stream)
      logger.debug("FSEventStream created and started: \(started)")
    } else {
      logger.error("Failed to create FSEventStream")
    }
  }

  private func stop() {
    queue.async { [weak self] in
      guard let self = self, let stream = self.stream else { return }
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
    }
  }

  private func handleEvents(paths: [String]) {
    logger.debug("FSEvents callback fired with \(paths.count) paths")

    // Filter out ignored paths
    let relevantPaths = paths.filter { path in
      !shouldIgnore(path: path)
    }

    logger.debug("After filtering: \(relevantPaths.count) relevant paths")
    for path in relevantPaths {
      logger.debug("  - \(path)")
    }
    guard !relevantPaths.isEmpty else { return }

    // Accumulate changes during debounce period
    pendingChanges.append(contentsOf: relevantPaths)
    logger.debug("Pending changes: \(pendingChanges.count)")

    // Debounce - ignore events too close together
    let now = Date()
    let timeSinceLast = now.timeIntervalSince(lastEventTime)
    logger.debug("Time since last event: \(timeSinceLast)s, debounce interval: \(debounceInterval)s")
    if timeSinceLast < debounceInterval {
      logger.debug("Debouncing - waiting for more events")
      return
    }
    lastEventTime = now

    // Analyze what types of files changed
    logger.debug("Analyzing \(pendingChanges.count) changes")
    let result = analyzeChanges(pendingChanges)
    logger.debug("Result: backend=\(result.hasBackendChanges), frontend=\(result.hasFrontendChanges), config=\(result.hasConfigChanges)")

    // Capture continuation before stopping
    let cont = continuation
    continuation = nil

    // Stop watching
    logger.debug("Stopping stream")
    stopSync()

    // Resume continuation on a global queue to avoid any dispatch queue issues
    if let cont = cont {
      logger.debug("Resuming continuation")
      DispatchQueue.global().async {
        cont.resume(returning: result)
      }
    } else {
      logger.error("Continuation is nil - this should not happen")
    }
  }

  private func stopSync() {
    guard let stream = self.stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }

  private func analyzeChanges(_ paths: [String]) -> FileChangeResult {
    var hasBackend = false
    var hasFrontend = false
    var hasConfig = false

    for path in paths {
      let filename = (path as NSString).lastPathComponent

      if filename == "velox.json" {
        hasConfig = true
      } else if path.hasSuffix(".swift") {
        hasBackend = true
      } else {
        // Check if it's a frontend file
        for ext in frontendExtensions {
          if path.hasSuffix(ext) {
            hasFrontend = true
            break
          }
        }
      }
    }

    return FileChangeResult(
      hasBackendChanges: hasBackend,
      hasFrontendChanges: hasFrontend,
      hasConfigChanges: hasConfig,
      changedPaths: paths
    )
  }

  /// Frontend file extensions to watch
  private let frontendExtensions = [
    ".html", ".htm", ".css", ".js", ".ts", ".jsx", ".tsx",
    ".json", ".svg", ".png", ".jpg", ".jpeg", ".gif", ".webp",
    ".woff", ".woff2", ".ttf", ".eot",
  ]

  private func shouldIgnore(path: String) -> Bool {
    for pattern in ignorePatterns {
      if path.contains(pattern) {
        return true
      }
    }

    let filename = (path as NSString).lastPathComponent

    // Always watch config files
    if filename == "velox.json" {
      return false
    }

    // Watch Swift source files
    if path.hasSuffix(".swift") {
      return false
    }

    // Watch frontend files
    for ext in frontendExtensions {
      if path.hasSuffix(ext) {
        return false
      }
    }

    // Ignore everything else
    return true
  }
}
#elseif os(Linux)
import Glibc

final class FileWatcher: @unchecked Sendable {
  private let paths: [String]
  private let debounceInterval: TimeInterval
  private var inotifyFd: Int32 = -1
  private var watchDescriptors: [Int32: String] = [:]

  /// Patterns to ignore (simple suffix matching)
  private let ignorePatterns = [
    ".build/",
    ".git/",
    "node_modules/",
    ".DS_Store",
    ".swp",
    "~",
  ]

  /// Frontend file extensions to watch
  private let frontendExtensions = [
    ".html", ".htm", ".css", ".js", ".ts", ".jsx", ".tsx",
    ".json", ".svg", ".png", ".jpg", ".jpeg", ".gif", ".webp",
    ".woff", ".woff2", ".ttf", ".eot",
  ]

  init(paths: [String], debounceInterval: TimeInterval = 1.0) {
    self.paths = paths.map { path in
      if path.hasPrefix("/") {
        return path
      }
      return FileManager.default.currentDirectoryPath + "/" + path
    }
    self.debounceInterval = debounceInterval
  }

  deinit {
    cleanup()
  }

  func waitForChange() async -> FileChangeResult {
    logger.debug("Starting inotify file watcher for paths: \(paths)")
    return await withCheckedContinuation { (cont: CheckedContinuation<FileChangeResult, Never>) in
      DispatchQueue.global().async { [self] in
        let result = self.watch()
        cont.resume(returning: result)
      }
    }
  }

  private func watch() -> FileChangeResult {
    inotifyFd = inotify_init()
    guard inotifyFd >= 0 else {
      logger.error("Failed to initialize inotify")
      return FileChangeResult(hasBackendChanges: true, hasFrontendChanges: false, hasConfigChanges: false, changedPaths: [])
    }

    // Recursively add watches for all directories
    for path in paths {
      addWatchesRecursively(path)
    }

    let mask: UInt32 = UInt32(IN_MODIFY) | UInt32(IN_CREATE) | UInt32(IN_DELETE) | UInt32(IN_MOVED_TO)
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
    defer {
      buffer.deallocate()
      cleanup()
    }

    var pendingChanges: [String] = []
    var lastEventTime = Date.distantPast

    while true {
      let bytesRead = read(inotifyFd, buffer, bufferSize)
      if bytesRead <= 0 { break }

      var offset = 0
      while offset < bytesRead {
        let event = buffer.advanced(by: offset).withMemoryRebound(to: inotify_event.self, capacity: 1) { $0.pointee }
        let nameLength = Int(event.len)

        if nameLength > 0 {
          let namePtr = buffer.advanced(by: offset + MemoryLayout<inotify_event>.size)
          let name = String(cString: namePtr)
          let dir = watchDescriptors[event.wd] ?? ""
          let fullPath = dir.isEmpty ? name : "\(dir)/\(name)"

          if !shouldIgnore(path: fullPath) {
            pendingChanges.append(fullPath)
          }
        }

        offset += MemoryLayout<inotify_event>.size + nameLength
      }

      guard !pendingChanges.isEmpty else { continue }

      let now = Date()
      let timeSinceLast = now.timeIntervalSince(lastEventTime)
      if timeSinceLast < debounceInterval {
        continue
      }
      lastEventTime = now

      return analyzeChanges(pendingChanges)
    }

    return FileChangeResult(hasBackendChanges: true, hasFrontendChanges: false, hasConfigChanges: false, changedPaths: pendingChanges)
  }

  private func addWatchesRecursively(_ path: String) {
    let mask: UInt32 = UInt32(IN_MODIFY) | UInt32(IN_CREATE) | UInt32(IN_DELETE) | UInt32(IN_MOVED_TO)
    let wd = inotify_add_watch(inotifyFd, path, mask)
    if wd >= 0 {
      watchDescriptors[wd] = path
    }

    // Recursively watch subdirectories
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: path) else { return }
    while let item = enumerator.nextObject() as? String {
      let fullPath = "\(path)/\(item)"
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
        if shouldIgnore(path: fullPath) {
          enumerator.skipDescendants()
          continue
        }
        let subWd = inotify_add_watch(inotifyFd, fullPath, mask)
        if subWd >= 0 {
          watchDescriptors[subWd] = fullPath
        }
      }
    }
  }

  private func cleanup() {
    if inotifyFd >= 0 {
      for wd in watchDescriptors.keys {
        inotify_rm_watch(inotifyFd, wd)
      }
      close(inotifyFd)
      inotifyFd = -1
      watchDescriptors.removeAll()
    }
  }

  private func analyzeChanges(_ paths: [String]) -> FileChangeResult {
    var hasBackend = false
    var hasFrontend = false
    var hasConfig = false

    for path in paths {
      let filename = URL(fileURLWithPath: path).lastPathComponent

      if filename == "velox.json" {
        hasConfig = true
      } else if path.hasSuffix(".swift") {
        hasBackend = true
      } else {
        for ext in frontendExtensions {
          if path.hasSuffix(ext) {
            hasFrontend = true
            break
          }
        }
      }
    }

    return FileChangeResult(
      hasBackendChanges: hasBackend,
      hasFrontendChanges: hasFrontend,
      hasConfigChanges: hasConfig,
      changedPaths: paths
    )
  }

  private func shouldIgnore(path: String) -> Bool {
    for pattern in ignorePatterns {
      if path.contains(pattern) {
        return true
      }
    }

    let filename = URL(fileURLWithPath: path).lastPathComponent

    if filename == "velox.json" { return false }
    if path.hasSuffix(".swift") { return false }
    for ext in frontendExtensions {
      if path.hasSuffix(ext) { return false }
    }

    return true
  }
}
#elseif os(Windows)
final class FileWatcher: @unchecked Sendable {
  init(paths: [String], debounceInterval: TimeInterval = 1.0) {}

  func waitForChange() async -> FileChangeResult {
    // Hot reload is not supported on Windows
    try? await Task.sleep(nanoseconds: UInt64.max)
    fatalError("Unreachable")
  }
}
#endif
