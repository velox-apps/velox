import Foundation
import Logging

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
