import Foundation

/// Unified representation of a rewrite mode shown in the popover.
/// Wraps either a built-in `ImprovementMode` or a user-defined custom mode.
struct Mode: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let systemSymbol: String
    let systemPrompt: String
    let isDirectPrompt: Bool
    let isBuiltIn: Bool
    /// If set, the model is instructed to produce output in this language.
    /// Otherwise it preserves the input language.
    let targetLanguage: String?

    init(id: String,
         title: String,
         systemSymbol: String,
         systemPrompt: String,
         isDirectPrompt: Bool,
         isBuiltIn: Bool,
         targetLanguage: String? = nil) {
        self.id = id
        self.title = title
        self.systemSymbol = systemSymbol
        self.systemPrompt = systemPrompt
        self.isDirectPrompt = isDirectPrompt
        self.isBuiltIn = isBuiltIn
        self.targetLanguage = targetLanguage
    }

    static func builtIn(_ mode: ImprovementMode) -> Mode {
        Mode(
            id: "builtin.\(mode.rawValue)",
            title: mode.title,
            systemSymbol: mode.systemSymbol,
            systemPrompt: mode.systemPrompt,
            isDirectPrompt: mode.isDirectPrompt,
            isBuiltIn: true
        )
    }

    static func custom(id: String = UUID().uuidString,
                       title: String,
                       systemSymbol: String,
                       systemPrompt: String,
                       isDirectPrompt: Bool,
                       targetLanguage: String? = nil) -> Mode {
        Mode(
            id: "custom.\(id)",
            title: title,
            systemSymbol: systemSymbol,
            systemPrompt: systemPrompt,
            isDirectPrompt: isDirectPrompt,
            isBuiltIn: false,
            targetLanguage: targetLanguage
        )
    }

    static var allBuiltIn: [Mode] {
        ImprovementMode.allCases.map { Mode.builtIn($0) }
    }
}
