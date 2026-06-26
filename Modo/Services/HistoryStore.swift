import Foundation

/// A single rewrite entry: original text, mode used, result, and timestamp.
struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let modeTitle: String
    let modeSymbol: String
    let originalText: String
    let resultText: String

    init(id: UUID = UUID(),
         date: Date = Date(),
         modeTitle: String,
         modeSymbol: String,
         originalText: String,
         resultText: String) {
        self.id = id
        self.date = date
        self.modeTitle = modeTitle
        self.modeSymbol = modeSymbol
        self.originalText = originalText
        self.resultText = resultText
    }
}

/// Stores the last N rewrites in UserDefaults. Local-only, capped, clearable.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let key = "rewriteHistory_v1"
    private let maxEntries = 20

    private init() {
        entries = load()
    }

    func add(_ entry: HistoryEntry) {
        // Privacy: honor the user's "save history" preference. When off, no
        // selection text is written to disk at all.
        guard AppPolicy.shared.saveHistory else { return }
        var updated = entries
        updated.insert(entry, at: 0)
        if updated.count > maxEntries {
            updated = Array(updated.prefix(maxEntries))
        }
        entries = updated
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func load() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
