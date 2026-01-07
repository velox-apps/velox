import Foundation
import VeloxRuntime

// MARK: - Metrics Payload

struct MetricsPayload: Codable, Sendable {
    let cpuUsage: Double
    let memoryUsed: Int64
    let memoryTotal: Int64
    let timestamp: Date
}

// MARK: - Metrics Collector

final class MetricsCollector: @unchecked Sendable {
    private var timer: Timer?
    private weak var eventManager: VeloxEventManager?

    init(eventManager: VeloxEventManager) {
        self.eventManager = eventManager
    }

    func start() {
        // Collect metrics every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectAndEmit()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func collectAndEmit() {
        let metrics = MetricsPayload(
            cpuUsage: getCPUUsage(),
            memoryUsed: getMemoryUsed(),
            memoryTotal: getMemoryTotal(),
            timestamp: Date()
        )

        do {
            try eventManager?.emit("metrics-update", payload: metrics)
        } catch {
            print("Failed to emit metrics: \(error)")
        }
    }

    private func getCPUUsage() -> Double {
        // Simplified - real implementation would use host_statistics
        return Double.random(in: 10...90)
    }

    private func getMemoryUsed() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func getMemoryTotal() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }
}

// MARK: - Setup in Main

func main() {
    let projectDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    do {
        let app = try VeloxAppBuilder(directory: projectDir)
            .registerCommands(registry)

        // Create and start metrics collector
        let collector = MetricsCollector(eventManager: app.eventManager)
        collector.start()

        try app.run()

        // Stop collector on exit
        collector.stop()
    } catch {
        fatalError("Failed to start app: \(error)")
    }
}

main()
