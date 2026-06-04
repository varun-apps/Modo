import Foundation

/// Sections that appear in the Help window's sidebar.
enum HelpTopic: String, CaseIterable, Identifiable, Hashable {
    case gettingStarted
    case threeWays
    case modesExplained
    case customModes
    case providers
    case routing
    case personalInstructions
    case generation
    case privacy
    case permissions
    case troubleshooting
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted:        return "Getting Started"
        case .threeWays:             return "Three Ways to Use Modo"
        case .modesExplained:        return "The Modes Explained"
        case .customModes:           return "Custom Modes"
        case .providers:             return "AI Providers"
        case .routing:               return "Per-Mode Model Routing"
        case .personalInstructions:  return "Personal Instructions"
        case .generation:            return "Tone, Diff & Generation"
        case .privacy:               return "Privacy"
        case .permissions:           return "Permissions"
        case .troubleshooting:       return "Troubleshooting"
        case .shortcuts:             return "Keyboard Shortcuts"
        case .about:                 return "About"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted:       return "play.circle"
        case .threeWays:            return "square.grid.2x2"
        case .modesExplained:       return "wand.and.stars"
        case .customModes:          return "wand.and.rays"
        case .providers:            return "cube.box"
        case .routing:              return "arrow.triangle.branch"
        case .personalInstructions: return "person.text.rectangle"
        case .generation:           return "slider.horizontal.3"
        case .privacy:              return "lock.shield"
        case .permissions:          return "checkmark.shield"
        case .troubleshooting:      return "stethoscope"
        case .shortcuts:            return "command"
        case .about:                return "info.circle"
        }
    }
}

extension Notification.Name {
    /// Posted when something in the app wants the Help window to open.
    /// AppDelegate listens and shows the window.
    static let openModoHelp = Notification.Name("Modo.OpenHelp")
}
