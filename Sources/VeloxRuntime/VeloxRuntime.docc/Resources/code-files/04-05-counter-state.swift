import Foundation

/// Thread-safe counter state for the counter app
final class CounterState: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }

    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value -= 1
        return _value
    }

    func reset() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value = 0
        return _value
    }

    func set(_ newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
        return _value
    }
}
