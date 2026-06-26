import Foundation

/// User-facing policy switches that gate Modo's behavior:
///  • per-app enable/disable (so Modo never acts in apps the user excludes),
///  • a network mode that restricts rewriting to on-device providers,
///  • whether rewrite history is persisted at all.
///
/// All values are persisted in `UserDefaults`. Reads are cheap and safe from
/// any thread.
final class AppPolicy {
    static let shared = AppPolicy()

    private let disabledKey = "disabledBundleIDs_v1"
    private let networkModeKey = "networkMode_v1"
    private let saveHistoryKey = "saveHistory_v1"

    private init() {}

    // MARK: - Per-app enable/disable

    /// Bundle IDs the user has switched Modo OFF for.
    var disabledBundleIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: disabledKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: disabledKey)
        }
    }

    func isEnabled(forBundleID bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !disabledBundleIDs.contains(bundleID)
    }

    func setEnabled(_ enabled: Bool, forBundleID bundleID: String) {
        var set = disabledBundleIDs
        if enabled { set.remove(bundleID) } else { set.insert(bundleID) }
        disabledBundleIDs = set
    }

    // MARK: - Network mode

    enum NetworkMode: String {
        case normal       // any configured provider
        case localOnly    // only on-device providers (Ollama / localhost endpoints)
    }

    var networkMode: NetworkMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: networkModeKey),
                  let mode = NetworkMode(rawValue: raw) else { return .normal }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: networkModeKey) }
    }

    // MARK: - History persistence

    /// Whether rewrites are saved to local History. Default on.
    var saveHistory: Bool {
        get { UserDefaults.standard.object(forKey: saveHistoryKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: saveHistoryKey) }
    }
}
