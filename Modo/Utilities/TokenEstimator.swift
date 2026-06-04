import Foundation

/// Rough estimate of how many tokens a piece of text consumes. Uses the
/// "~4 characters per token" heuristic documented by OpenAI, which is close
/// enough for cost/usage indication without bundling a tokenizer.
enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        let chars = text.unicodeScalars.count
        return max(1, Int((Double(chars) / 4.0).rounded()))
    }

    /// "~120 tokens" — short, user-facing label.
    static func displayString(for text: String) -> String {
        let count = estimate(text)
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "~%.1fk tokens", k)
        }
        return "~\(count) tokens"
    }
}
