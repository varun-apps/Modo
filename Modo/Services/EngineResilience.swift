import Foundation

/// A simple circuit breaker that trips after a run of consecutive engine
/// failures and stays open for a cooldown, so Modo stops hammering a provider
/// that's down/rate-limiting and gives the user a clear "try again shortly"
/// state instead of repeated spinner-then-error cycles.
actor CircuitBreaker {
    static let shared = CircuitBreaker()

    enum Decision {
        case allow
        case blocked(retryAfter: TimeInterval)
    }

    private let failureThreshold: Int
    private let cooldown: TimeInterval
    private var consecutiveFailures = 0
    private var openedAt: Date?

    init(failureThreshold: Int = 4, cooldown: TimeInterval = 30) {
        self.failureThreshold = failureThreshold
        self.cooldown = cooldown
    }

    /// Whether a new request may proceed. While open, returns the remaining
    /// cooldown so the UI can tell the user how long to wait.
    func check() -> Decision {
        guard let openedAt else { return .allow }
        let elapsed = Date().timeIntervalSince(openedAt)
        if elapsed >= cooldown {
            // Half-open: allow a probe request through.
            return .allow
        }
        return .blocked(retryAfter: cooldown - elapsed)
    }

    func recordSuccess() {
        consecutiveFailures = 0
        openedAt = nil
    }

    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold {
            openedAt = Date()
        }
    }
}

/// Classifies which API errors are worth an automatic retry (transient
/// infrastructure issues) versus those that won't improve on their own
/// (bad key, wrong model, empty input).
enum RetryPolicy {
    static func isTransient(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .network:
            return true
        case .http(let status, _):
            return status == 429 || (500..<600).contains(status)
        case .missingAPIKey, .invalidResponse:
            return false
        }
    }

    /// Exponential backoff with a small jitter, capped. Attempt is 0-based.
    static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let base = min(pow(2.0, Double(attempt)), 8.0)   // 1s, 2s, 4s, … capped at 8s
        let jitter = Double.random(in: 0...0.4)
        return UInt64((base + jitter) * 1_000_000_000)
    }
}
