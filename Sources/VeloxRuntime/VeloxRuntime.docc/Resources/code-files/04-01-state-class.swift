import Foundation

/// Thread-safe state class for managing application data.
/// Use NSLock to protect shared data from concurrent access.
final class AppState: @unchecked Sendable {
    private let lock = NSLock()

    // Private backing storage
    private var _counter: Int = 0
    private var _username: String = "Guest"
    private var _items: [String] = []

    // Thread-safe accessors
    var counter: Int {
        lock.lock()
        defer { lock.unlock() }
        return _counter
    }

    var username: String {
        lock.lock()
        defer { lock.unlock() }
        return _username
    }

    var items: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _items
    }

    // Thread-safe mutators
    func incrementCounter() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _counter += 1
        return _counter
    }

    func setUsername(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        _username = name
    }

    func addItem(_ item: String) {
        lock.lock()
        defer { lock.unlock() }
        _items.append(item)
    }
}
