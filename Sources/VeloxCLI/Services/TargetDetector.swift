import Foundation

struct TargetDetector {
  enum DetectorError: Error, CustomStringConvertible {
    case packageNotFound
    case parseError(String)

    var description: String {
      switch self {
      case .packageNotFound:
        return "Package.swift not found in current directory"
      case .parseError(let message):
        return "Failed to parse Package.swift: \(message)"
      }
    }
  }

  /// Result containing detected executables and the package directory
  struct DetectionResult {
    let executables: [String]
    let packageDirectory: URL
  }

  /// Detects executable targets from Package.swift
  /// Searches current directory and parent directories
  func detectExecutables() throws -> [String] {
    return try detect().executables
  }

  /// Detects executable targets and returns the package directory
  func detect() throws -> DetectionResult {
    guard let packagePath = findPackageSwift() else {
      throw DetectorError.packageNotFound
    }

    let content = try String(contentsOfFile: packagePath, encoding: .utf8)
    let packageDirectory = URL(fileURLWithPath: packagePath).deletingLastPathComponent()

    return DetectionResult(
      executables: parseExecutables(from: content),
      packageDirectory: packageDirectory
    )
  }

  /// Searches for Package.swift in current and parent directories
  private func findPackageSwift() -> String? {
    var currentPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Search up to 5 levels up
    for _ in 0..<5 {
      let packagePath = currentPath.appendingPathComponent("Package.swift").path
      if FileManager.default.fileExists(atPath: packagePath) {
        return packagePath
      }
      currentPath = currentPath.deletingLastPathComponent()
    }

    return nil
  }

  /// Parses Package.swift content to find executable names
  private func parseExecutables(from content: String) -> [String] {
    var executables: [String] = []

    // Match .executable(name: "...", or .executable(name:"...
    // Pattern: .executable followed by name: and a quoted string
    let executablePattern = #"\.executable\s*\(\s*name\s*:\s*"([^"]+)""#

    if let regex = try? NSRegularExpression(pattern: executablePattern, options: []) {
      let range = NSRange(content.startIndex..., in: content)
      let matches = regex.matches(in: content, options: [], range: range)

      for match in matches {
        if let nameRange = Range(match.range(at: 1), in: content) {
          let name = String(content[nameRange])
          // Skip the velox CLI itself
          if name != "velox" {
            executables.append(name)
          }
        }
      }
    }

    // Also match .executableTarget(name: "...",
    let executableTargetPattern = #"\.executableTarget\s*\(\s*name\s*:\s*"([^"]+)""#

    if let regex = try? NSRegularExpression(pattern: executableTargetPattern, options: []) {
      let range = NSRange(content.startIndex..., in: content)
      let matches = regex.matches(in: content, options: [], range: range)

      for match in matches {
        if let nameRange = Range(match.range(at: 1), in: content) {
          let name = String(content[nameRange])
          // Skip the velox CLI itself and avoid duplicates
          if name != "VeloxCLI" && !executables.contains(name) {
            executables.append(name)
          }
        }
      }
    }

    return executables
  }
}
