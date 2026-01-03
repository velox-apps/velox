import Foundation

final class FileWatcher: @unchecked Sendable {
  private let paths: [String]
  private let debounceInterval: TimeInterval
  private var stream: FSEventStreamRef?
  private var continuation: CheckedContinuation<Void, Never>?
  private var lastEventTime: Date = .distantPast
  private let queue = DispatchQueue(label: "com.velox.filewatcher")

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
  func waitForChange() async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      queue.async { [weak self] in
        self?.continuation = cont
        self?.start()
      }
    }
  }

  private func start() {
    guard stream == nil else { return }

    var context = FSEventStreamContext()
    context.info = Unmanaged.passUnretained(self).toOpaque()

    let callback: FSEventStreamCallback = {
      (
        streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds
      ) in
      guard let info = clientCallBackInfo else { return }
      let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

      let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
      watcher.handleEvents(paths: paths)
    }

    let pathsToWatch = paths as CFArray

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
      FSEventStreamStart(stream)
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
    // Filter out ignored paths
    let relevantPaths = paths.filter { path in
      !shouldIgnore(path: path)
    }

    guard !relevantPaths.isEmpty else { return }

    // Debounce - ignore events too close together
    let now = Date()
    if now.timeIntervalSince(lastEventTime) < debounceInterval {
      return
    }
    lastEventTime = now

    // Stop watching and signal continuation
    stop()
    if let cont = continuation {
      continuation = nil
      cont.resume()
    }
  }

  private func shouldIgnore(path: String) -> Bool {
    for pattern in ignorePatterns {
      if path.contains(pattern) {
        return true
      }
    }

    // Only watch Swift files and config
    let filename = (path as NSString).lastPathComponent
    if filename == "velox.json" {
      return false
    }
    if path.hasSuffix(".swift") {
      return false
    }

    // Ignore everything else
    return true
  }
}
