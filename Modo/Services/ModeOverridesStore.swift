import Foundation

/// Per-mode override of which (provider, model) to use. Either field may be
/// nil — `providerRaw` nil means "use the currently-selected provider", and
/// `modelID` nil means "use that provider's currently-selected model".
struct ModeOverride: Codable, Hashable {
    var providerRaw: String?
    var modelID: String?

    var isEmpty: Bool {
        (providerRaw?.isEmpty ?? true) && (modelID?.isEmpty ?? true)
    }
}

/// Persists per-mode (provider, model) overrides in UserDefaults so users can
/// route cheap/fast models to simple modes and stronger models to complex ones.
final class ModeOverridesStore {
    static let shared = ModeOverridesStore()

    private let key = "modeOverrides_v1"

    private init() {}

    func load() -> [String: ModeOverride] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ModeOverride].self, from: data)
        else { return [:] }
        return decoded
    }

    func override(for modeID: String) -> ModeOverride? {
        let result = load()[modeID]
        if let result, !result.isEmpty { return result }
        return nil
    }

    func setOverride(_ override: ModeOverride?, for modeID: String) {
        var all = load()
        if let override, !override.isEmpty {
            all[modeID] = override
        } else {
            all.removeValue(forKey: modeID)
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
