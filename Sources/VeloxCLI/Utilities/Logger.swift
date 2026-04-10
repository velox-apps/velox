import Foundation
import Logging

/// Global logger for VeloxCLI
var logger = Logger(label: "com.velox.cli")

/// Custom log handler that outputs to stderr with a clean format
struct VeloxLogHandler: LogHandler {
  var logLevel: Logger.Level = .info
  var metadata: Logger.Metadata = [:]

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let output = "\(message)\n"
    fputs(output, stderr)
  }
}

/// Configure the global logger with the specified log level
func configureLogger(verbose: Bool = false) {
  LoggingSystem.bootstrap { label in
    var handler = VeloxLogHandler()
    handler.logLevel = verbose ? .debug : .info
    return handler
  }
  logger = Logger(label: "com.velox.cli")
  logger.logLevel = verbose ? .debug : .info
}
