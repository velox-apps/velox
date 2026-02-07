// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Foundation
import VeloxRuntime

/// Built-in Shell plugin for executing system commands.
///
/// This plugin exposes the following commands:
/// - `plugin:shell|execute` - Execute a command and wait for completion
/// - `plugin:shell|spawn` - Spawn a command in background (returns immediately)
/// - `plugin:shell|kill` - Kill a spawned process
///
/// **Security Note**: This plugin should be used carefully with proper permission scoping
/// to prevent arbitrary command execution.
///
/// Example frontend usage:
/// ```javascript
/// // Execute command and get output
/// const result = await invoke('plugin:shell|execute', {
///   program: 'ls',
///   args: ['-la', '/tmp']
/// });
/// console.log(result.stdout);
///
/// // Spawn background process
/// const pid = await invoke('plugin:shell|spawn', {
///   program: 'tail',
///   args: ['-f', '/var/log/system.log']
/// });
///
/// // Kill process
/// await invoke('plugin:shell|kill', { pid });
/// ```
public final class ShellPlugin: VeloxPlugin, @unchecked Sendable {
  public let name = "shell"

  /// Active spawned processes
  private var processes: [Int32: Process] = [:]
  private let lock = NSLock()

  public init() {}

  public func setup(context: PluginSetupContext) throws {
    let commands = context.commands(for: name)

    // Execute command synchronously
    commands.register("execute", args: ExecuteArgs.self, returning: ExecuteResult.self) { [self] args, _ in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: args.program)
      process.arguments = args.args ?? []

      if let cwd = args.cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
      }

      if let env = args.env {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
          environment[key] = value
        }
        process.environment = environment
      }

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      do {
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ExecuteResult(
          code: process.terminationStatus,
          stdout: String(data: stdoutData, encoding: .utf8) ?? "",
          stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
      } catch {
        throw CommandError(code: "ExecutionFailed", message: error.localizedDescription)
      }
    }

    // Spawn process in background
    commands.register("spawn", args: ExecuteArgs.self, returning: Int32.self) { [self] args, _ in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: args.program)
      process.arguments = args.args ?? []

      if let cwd = args.cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
      }

      if let env = args.env {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
          environment[key] = value
        }
        process.environment = environment
      }

      do {
        try process.run()

        let pid = process.processIdentifier

        lock.lock()
        processes[pid] = process
        lock.unlock()

        // Clean up when process exits
        process.terminationHandler = { [weak self] _ in
          self?.lock.lock()
          self?.processes.removeValue(forKey: pid)
          self?.lock.unlock()
        }

        return pid
      } catch {
        throw CommandError(code: "SpawnFailed", message: error.localizedDescription)
      }
    }

    // Kill a spawned process
    commands.register("kill", args: KillArgs.self, returning: Bool.self) { [self] args, _ in
      lock.lock()
      defer { lock.unlock() }

      guard let process = processes[args.pid] else {
        return false
      }

      if args.force == true {
        process.terminate()
      } else {
        process.interrupt()
      }

      processes.removeValue(forKey: args.pid)
      return true
    }

    // Check if process is running
    commands.register("isRunning", args: KillArgs.self, returning: Bool.self) { [self] args, _ in
      lock.lock()
      defer { lock.unlock() }

      guard let process = processes[args.pid] else {
        return false
      }
      return process.isRunning
    }
  }

  public func onDrop() {
    // Terminate all spawned processes on shutdown
    lock.lock()
    for (_, process) in processes where process.isRunning {
      process.terminate()
    }
    processes.removeAll()
    lock.unlock()
  }

  // MARK: - Argument Types

  struct ExecuteArgs: Codable, Sendable {
    let program: String
    var args: [String]?
    var cwd: String?
    var env: [String: String]?
  }

  struct KillArgs: Codable, Sendable {
    let pid: Int32
    var force: Bool?
  }

  struct ExecuteResult: Codable, Sendable {
    let code: Int32
    let stdout: String
    let stderr: String
  }
}
