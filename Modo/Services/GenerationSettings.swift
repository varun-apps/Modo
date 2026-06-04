import Foundation

/// Global generation controls applied to every rewrite request:
/// creativity (temperature) and target length (max output tokens).
enum GenerationSettings {
    enum Length: String, CaseIterable, Identifiable {
        case short
        case medium
        case long

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .short:  return "Short"
            case .medium: return "Medium"
            case .long:   return "Long"
            }
        }

        var maxTokens: Int {
            switch self {
            case .short:  return 512
            case .medium: return 2048
            case .long:   return 4096
            }
        }
    }

    private static let temperatureKey = "generation_temperature"
    private static let lengthKey = "generation_length"

    static var temperature: Double {
        get { UserDefaults.standard.object(forKey: temperatureKey) as? Double ?? 0.7 }
        set { UserDefaults.standard.set(newValue, forKey: temperatureKey) }
    }

    static var length: Length {
        get {
            let raw = UserDefaults.standard.string(forKey: lengthKey) ?? Length.medium.rawValue
            return Length(rawValue: raw) ?? .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lengthKey) }
    }
}
