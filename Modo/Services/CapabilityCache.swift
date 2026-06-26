import Foundation

/// Which capture strategy last worked for an app.
enum CaptureTier: String, Codable {
    case accessibility   // AX text attributes
    case clipboard       // synthetic ⌘C fallback
}

/// Which apply strategy last worked for an app.
enum ApplyTier: String, Codable {
    case accessibility   // AX set value
    case paste           // synthetic ⌘V
    case copyOnly        // read-only / paste-blocked — leave on clipboard
}

/// Per-app memory of which capture/apply tiers succeeded, so Modo can skip
/// strategies that are known to fail for a given app (notably AX reads against
/// Chromium/Electron apps, which always fail and add latency + flicker).
///
/// Persisted across launches with a TTL so an app that gains AX support in a
/// later version gets re-probed instead of being stuck on a stale verdict.
/// Thread-safe via an internal lock; UserDefaults itself is thread-safe.
final class CapabilityCache {
    static let shared = CapabilityCache()

    struct Record: Codable {
        var captureTier: CaptureTier?
        var applyTier: ApplyTier?
        var updated: Date
    }

    /// Apps known to be Chromium/Electron-based, where the AX text attributes
    /// are not exposed and only the clipboard path works. Seeding these avoids
    /// a doomed AX attempt (and its flicker) on first use.
    static let seededCopyOnly: Set<String> = [
        "com.tinyspeck.slackmacgap",            // Slack
        "com.microsoft.teams",                  // Teams (classic)
        "com.microsoft.teams2",                 // Teams (new)
        "com.microsoft.VSCode",                 // VS Code
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",        // Cursor
        "com.hnc.Discord",                      // Discord
        "com.electron.discord",
        "com.spotify.client",                   // Spotify
        "notion.id",                            // Notion
        "md.obsidian",                          // Obsidian
        "com.figma.Desktop",                    // Figma
        "com.postmanlabs.mac",                  // Postman
        "com.github.GitHubClient",              // GitHub Desktop
        "com.google.Chrome",                    // Chrome
        "com.google.Chrome.beta",
        "com.microsoft.edgemac",                // Edge
        "com.brave.Browser",                    // Brave
        "company.thebrowser.Browser",           // Arc
        "com.vivaldi.Vivaldi",                  // Vivaldi
        "com.operasoftware.Opera",              // Opera
    ]

    private let key = "capabilityCache_v1"
    private let ttl: TimeInterval = 60 * 60 * 24 * 30 // 30 days
    private let lock = NSLock()
    private var records: [String: Record]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    /// The capture tier Modo should try FIRST for this app. Returns `.clipboard`
    /// for seeded copy-only apps or a fresh recorded verdict; `nil` means "no
    /// opinion — try the normal AX-first chain".
    func preferredCaptureTier(for bundleID: String?) -> CaptureTier? {
        guard let bundleID else { return nil }
        if Self.seededCopyOnly.contains(bundleID) { return .clipboard }
        lock.lock(); defer { lock.unlock() }
        guard let record = records[bundleID], !isStale(record) else { return nil }
        return record.captureTier
    }

    /// The apply tier Modo should try first for this app, if known and fresh.
    func preferredApplyTier(for bundleID: String?) -> ApplyTier? {
        guard let bundleID else { return nil }
        if Self.seededCopyOnly.contains(bundleID) { return .paste }
        lock.lock(); defer { lock.unlock() }
        guard let record = records[bundleID], !isStale(record) else { return nil }
        return record.applyTier
    }

    func recordCapture(_ tier: CaptureTier, for bundleID: String?) {
        guard let bundleID else { return }
        lock.lock(); defer { lock.unlock() }
        var record = records[bundleID] ?? Record(captureTier: nil, applyTier: nil, updated: Date())
        record.captureTier = tier
        record.updated = Date()
        records[bundleID] = record
        persistLocked()
    }

    func recordApply(_ tier: ApplyTier, for bundleID: String?) {
        guard let bundleID else { return }
        lock.lock(); defer { lock.unlock() }
        var record = records[bundleID] ?? Record(captureTier: nil, applyTier: nil, updated: Date())
        record.applyTier = tier
        record.updated = Date()
        records[bundleID] = record
        persistLocked()
    }

    /// Hidden support/debugging action: forget everything learned so all apps
    /// get re-probed from scratch.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        records = [:]
        persistLocked()
    }

    private func isStale(_ record: Record) -> Bool {
        Date().timeIntervalSince(record.updated) > ttl
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
