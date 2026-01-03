import Foundation
import Darwin

struct DevServerChecker: Sendable {
  let url: String

  /// Waits until the dev server is available or timeout is reached
  /// Returns true if server became available, false on timeout
  func waitUntilAvailable(timeout: TimeInterval, retryInterval: TimeInterval) async -> Bool {
    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
      if await checkConnection() {
        return true
      }

      // Wait before retry
      try? await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
    }

    return false
  }

  /// Checks if the server is responding
  private func checkConnection() async -> Bool {
    guard let url = URL(string: url) else { return false }

    // Try TCP connection first (faster)
    if let host = url.host, let port = url.port ?? defaultPort(for: url.scheme) {
      if await checkTCPConnection(host: host, port: port) {
        return true
      }
    }

    // Fall back to HTTP request
    return await checkHTTPConnection(url: url)
  }

  private func checkTCPConnection(host: String, port: Int) async -> Bool {
    return await withCheckedContinuation { continuation in
      let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
      guard sock >= 0 else {
        continuation.resume(returning: false)
        return
      }

      defer { Darwin.close(sock) }

      // Set socket timeout
      var timeout = timeval(tv_sec: 2, tv_usec: 0)
      setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

      var addr = sockaddr_in()
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = in_port_t(port).bigEndian

      // Try to resolve the host
      if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
        // Try resolving hostname
        if let hostent = gethostbyname(host),
          let addrList = hostent.pointee.h_addr_list,
          let firstAddr = addrList[0]
        {
          memcpy(&addr.sin_addr, firstAddr, Int(hostent.pointee.h_length))
        } else {
          continuation.resume(returning: false)
          return
        }
      }

      let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
          Darwin.connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }

      continuation.resume(returning: connectResult == 0)
    }
  }

  private func checkHTTPConnection(url: URL) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 2

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let httpResponse = response as? HTTPURLResponse {
        return httpResponse.statusCode < 500
      }
      return false
    } catch {
      return false
    }
  }

  private func defaultPort(for scheme: String?) -> Int? {
    switch scheme {
    case "http": return 80
    case "https": return 443
    default: return nil
    }
  }
}
