import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    return await checkHTTPConnection(url: url)
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
}
