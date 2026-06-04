import Foundation

/// A segment of a diff: either unchanged, removed, or inserted text.
struct DiffSegment: Hashable, Identifiable {
    enum Kind { case equal, removed, inserted }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Computes a word-level diff between two strings using the standard
/// longest-common-subsequence algorithm. Consecutive same-kind segments are
/// merged so the renderer can show a single run of red/green text.
enum WordDiff {
    /// Hard cap on input size — the LCS table is O(m·n), so above this point
    /// we degrade gracefully rather than freeze the UI.
    private static let maxCharsPerSide = 8000

    static func diff(original: String, updated: String) -> [DiffSegment] {
        if original.count > maxCharsPerSide || updated.count > maxCharsPerSide {
            return [
                DiffSegment(kind: .removed, text: original),
                DiffSegment(kind: .inserted, text: updated)
            ]
        }

        let a = tokenize(original)
        let b = tokenize(updated)

        let m = a.count
        let n = b.count

        guard m > 0 || n > 0 else { return [] }

        // lcs[i][j] = length of longest common subsequence of a[0..<i] and b[0..<j].
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in 1...m {
                for j in 1...n {
                    if a[i - 1] == b[j - 1] {
                        lcs[i][j] = lcs[i - 1][j - 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                    }
                }
            }
        }

        // Backtrack to assemble the segment list in order.
        var segments: [DiffSegment] = []
        var i = m
        var j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                segments.append(DiffSegment(kind: .equal, text: a[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || lcs[i][j - 1] >= lcs[i - 1][j] {
                segments.append(DiffSegment(kind: .inserted, text: b[j - 1]))
                j -= 1
            } else {
                segments.append(DiffSegment(kind: .removed, text: a[i - 1]))
                i -= 1
            }
        }

        return merge(segments.reversed())
    }

    /// Splits a string into words while preserving the whitespace that follows
    /// each word, so reassembling produces the original text exactly.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false
        for char in text {
            if char.isWhitespace {
                if inWord {
                    inWord = false
                }
                current.append(char)
            } else {
                if !inWord && !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWord = true
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func merge(_ segments: [DiffSegment]) -> [DiffSegment] {
        var merged: [DiffSegment] = []
        for segment in segments {
            if let last = merged.last, last.kind == segment.kind {
                merged[merged.count - 1] = DiffSegment(kind: last.kind,
                                                       text: last.text + segment.text)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}
