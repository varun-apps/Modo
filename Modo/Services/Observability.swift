import Foundation
import os

/// Content-free, structured logging for the capture/apply pipeline. Records
/// WHICH tier was used, WHETHER it succeeded, per-app bundle ID, and a coarse
/// latency bucket — never the selection text or the improved output.
///
/// Two sinks: `os.Logger` (visible in Console.app, survives crashes) and a
/// small in-memory ring buffer that the "It's not working" help/debug path can
/// display. Both are strictly metadata; see `redactedBundle` for the only field
/// that could conceivably be sensitive.
final class Observability {
    static let shared = Observability()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Modo",
                                category: "pipeline")
    private let lock = NSLock()
    private var ring: [Entry] = []
    private let ringCapacity = 100

    struct Entry: Sendable {
        let date: Date
        let phase: String        // "capture" | "apply" | "engine"
        let tier: String
        let success: Bool
        let bundleID: String
        let latencyBucket: String
    }

    private init() {}

    /// Buckets a millisecond latency into coarse ranges so timing data never
    /// becomes a side channel and stays easy to scan.
    static func bucket(ms: Int) -> String {
        switch ms {
        case ..<50: return "<50ms"
        case ..<150: return "50-150ms"
        case ..<400: return "150-400ms"
        case ..<1000: return "400ms-1s"
        default: return ">1s"
        }
    }

    func logCapture(tier: CaptureSource?, success: Bool, bundleID: String?, latencyMS: Int) {
        record(phase: "capture",
               tier: tier?.rawValue ?? "none",
               success: success,
               bundleID: bundleID,
               latencyBucket: Self.bucket(ms: latencyMS))
    }

    func logApply(tier: String, success: Bool, bundleID: String?) {
        record(phase: "apply", tier: tier, success: success, bundleID: bundleID, latencyBucket: "n/a")
    }

    func logEngine(success: Bool, bundleID: String?, latencyMS: Int) {
        record(phase: "engine", tier: "stream", success: success,
               bundleID: bundleID, latencyBucket: Self.bucket(ms: latencyMS))
    }

    /// Snapshot of the recent events for a debug view. Newest first.
    func recentEntries() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return ring.reversed()
    }

    private func record(phase: String, tier: String, success: Bool,
                        bundleID: String?, latencyBucket: String) {
        let bundle = bundleID ?? "unknown"
        // os_log: bundle ID is an app identifier, not user content — public is
        // fine and makes field triage possible. No text is ever logged.
        logger.log("phase=\(phase, privacy: .public) tier=\(tier, privacy: .public) success=\(success, privacy: .public) app=\(bundle, privacy: .public) latency=\(latencyBucket, privacy: .public)")

        let entry = Entry(date: Date(), phase: phase, tier: tier, success: success,
                          bundleID: bundle, latencyBucket: latencyBucket)
        lock.lock()
        ring.append(entry)
        if ring.count > ringCapacity { ring.removeFirst(ring.count - ringCapacity) }
        lock.unlock()
    }
}
