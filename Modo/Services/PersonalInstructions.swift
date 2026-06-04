import Foundation

/// User-supplied instructions that are appended to every system prompt
/// (e.g. "I'm British, keep -our spellings"; "never use em-dashes";
/// "always capitalize Acme product names exactly as written").
enum PersonalInstructions {
    private static let key = "personalInstructions_v1"

    static var current: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Wraps the mode's system prompt with the user's persistent instructions
    /// (if any) and, when present, an explicit target-language directive. Both
    /// are added as named sections so the model treats them as binding
    /// constraints across every mode.
    static func composeSystemPrompt(for mode: Mode) -> String {
        var result = mode.systemPrompt

        if let language = mode.targetLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty {
            result += "\n\n" +
                "OUTPUT LANGUAGE: Produce the result in \(language). " +
                "This overrides any \"preserve the original language\" instruction above."
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result += "\n\n" +
                "ADDITIONAL USER PREFERENCES (always apply these, in addition to the task above):\n" +
                trimmed
        }

        return result
    }
}
