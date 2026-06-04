import Foundation

/// Cancels a long-running streaming task if no progress arrives within the
/// configured timeout. Call `tick()` whenever a chunk is received to keep the
/// watchdog from firing.
actor StreamWatchdog {
    private let timeoutNanoseconds: UInt64
    private let onTimeout: @Sendable () -> Void
    private var watcher: Task<Void, Never>?
    private(set) var firedTimeout = false
    private var lastTickAt: Date = .distantPast

    init(timeoutSeconds: Double, onTimeout: @escaping @Sendable () -> Void) {
        self.timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
        self.onTimeout = onTimeout
    }

    func start() {
        lastTickAt = Date()
        watcher?.cancel()
        watcher = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if await self.shouldFire() {
                    await self.fire()
                    return
                }
            }
        }
    }

    func tick() {
        lastTickAt = Date()
    }

    func cancel() {
        watcher?.cancel()
        watcher = nil
    }

    private func shouldFire() -> Bool {
        guard !firedTimeout else { return false }
        let elapsed = Date().timeIntervalSince(lastTickAt)
        return UInt64(elapsed * 1_000_000_000) >= timeoutNanoseconds
    }

    private func fire() {
        guard !firedTimeout else { return }
        firedTimeout = true
        onTimeout()
    }
}
