import Foundation

/// Persists user-defined custom modes in UserDefaults as Codable JSON.
final class CustomModeStore {
    static let shared = CustomModeStore()

    private let key = "customModes_v1"

    private init() {}

    func load() -> [Mode] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let modes = try? JSONDecoder().decode([Mode].self, from: data)
        else { return [] }
        return modes.filter { !$0.isBuiltIn }
    }

    func save(_ modes: [Mode]) {
        let customs = modes.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
