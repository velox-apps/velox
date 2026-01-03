import Foundation

actor ProcessManager {
  enum ProcessError: Error {
    case buildFailed(String)
    case runtimeError(String)
    case terminated
  }

  private var backgroundProcesses: [String: Process] = [:]
  private var currentAppProcess: Process?

  /// Spawns a background process that runs until explicitly terminated
  func spawnBackgroundProcess(command: String, label: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Set up pipes for output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    // Forward output to console with label prefix
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
        for line in str.split(separator: "\n", omittingEmptySubsequences: false) {
          if !line.isEmpty {
            print("[\(label)] \(line)")
          }
        }
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
        for line in str.split(separator: "\n", omittingEmptySubsequences: false) {
          if !line.isEmpty {
            print("[\(label)] \(line)")
          }
        }
      }
    }

    try process.run()
    backgroundProcesses[label] = process
  }

  /// Runs the Swift app and waits for it to exit
  func runSwiftApp(
    target: String,
    release: Bool,
    devUrl: String?,
    packageDirectory: URL? = nil
  ) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")

    var args = ["run"]
    if release {
      args.append("-c")
      args.append("release")
    }
    args.append(target)
    process.arguments = args

    // Run from the Package.swift directory if specified, otherwise current directory
    let workingDir = packageDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    process.currentDirectoryURL = workingDir

    // Set environment with VELOX_DEV_URL and VELOX_CONFIG_DIR
    var env = ProcessInfo.processInfo.environment
    if let devUrl = devUrl {
      env["VELOX_DEV_URL"] = devUrl
    }
    // Tell the app where the original config directory is
    env["VELOX_CONFIG_DIR"] = FileManager.default.currentDirectoryPath
    process.environment = env

    // Capture output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    var outputData = Data()
    var errorData = Data()

    // Forward output in real-time
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        outputData.append(data)
        if let str = String(data: data, encoding: .utf8) {
          print(str, terminator: "")
        }
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        errorData.append(data)
        if let str = String(data: data, encoding: .utf8) {
          FileHandle.standardError.write(data)
        }
      }
    }

    currentAppProcess = process

    try process.run()
    process.waitUntilExit()

    // Clean up handlers
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil

    currentAppProcess = nil

    let exitCode = process.terminationStatus

    // Check if terminated by signal (we killed it)
    if process.terminationReason == .uncaughtSignal {
      throw ProcessError.terminated
    }

    if exitCode != 0 {
      let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
      // Check if it's a build error (swift build failed)
      if errorOutput.contains("error:") && errorOutput.contains("Build complete!") == false {
        throw ProcessError.buildFailed(errorOutput)
      }
      throw ProcessError.runtimeError(errorOutput)
    }
  }

  /// Terminates the currently running app process
  func terminateApp() {
    guard let process = currentAppProcess, process.isRunning else { return }
    process.terminate()
    // Give it a moment to clean up
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
      if process.isRunning {
        process.interrupt()
      }
    }
  }

  /// Terminates all managed processes
  func terminateAll() {
    // First terminate the app
    terminateApp()

    // Then terminate background processes
    for (label, process) in backgroundProcesses {
      if process.isRunning {
        print("[shutdown] Terminating \(label)...")
        process.terminate()
      }
    }

    // Wait a bit, then force kill if needed
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [backgroundProcesses] in
      for (_, process) in backgroundProcesses {
        if process.isRunning {
          process.interrupt()
        }
      }
    }

    backgroundProcesses.removeAll()
  }
}
