import Foundation

struct ProviderModel: Identifiable, Equatable {
    let id: String
    let displayName: String
}

enum AIProvider: String, CaseIterable, Identifiable {
    case groq
    case openAI = "openai"
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq:      return "Groq"
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Google Gemini"
        }
    }

    // Groq keeps the legacy account string so existing keys migrate automatically.
    var keychainAccount: String {
        switch self {
        case .groq:      return "groq-api-key"
        case .openAI:    return "openai-api-key"
        case .anthropic: return "anthropic-api-key"
        case .gemini:    return "gemini-api-key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .groq:      return "gsk_…"
        case .openAI:    return "sk-…"
        case .anthropic: return "sk-ant-…"
        case .gemini:    return "AIza…"
        }
    }

    var keyHelpText: String {
        switch self {
        case .groq:      return "Get a free key at console.groq.com"
        case .openAI:    return "Get a key at platform.openai.com"
        case .anthropic: return "Get a key at console.anthropic.com"
        case .gemini:    return "Get a free key at aistudio.google.com"
        }
    }

    var models: [ProviderModel] {
        switch self {
        case .groq:
            return [
                ProviderModel(id: "llama-3.3-70b-versatile",  displayName: "Llama 3.3 70B (recommended)"),
                ProviderModel(id: "llama-3.1-8b-instant",     displayName: "Llama 3.1 8B (fastest)")
            ]
        case .openAI:
            return [
                ProviderModel(id: "gpt-4o",      displayName: "GPT-4o (recommended)"),
                ProviderModel(id: "gpt-4o-mini", displayName: "GPT-4o mini (faster)")
            ]
        case .anthropic:
            return [
                ProviderModel(id: "claude-sonnet-4-6",        displayName: "Claude Sonnet 4.6 (recommended)"),
                ProviderModel(id: "claude-haiku-4-5-20251001",displayName: "Claude Haiku 4.5 (faster)"),
                ProviderModel(id: "claude-opus-4-7",          displayName: "Claude Opus 4.7 (most capable)")
            ]
        case .gemini:
            return [
                ProviderModel(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash (recommended)"),
                ProviderModel(id: "gemini-2.5-pro",   displayName: "Gemini 2.5 Pro (most capable)")
            ]
        }
    }

    var defaultModel: ProviderModel { models[0] }

    var currentModelID: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "selectedModel_\(rawValue)") {
                return saved
            }
            // Migrate the legacy Groq model key written by the old GroqModel enum.
            if self == .groq, let legacy = UserDefaults.standard.string(forKey: "selectedModel") {
                return legacy
            }
            return defaultModel.id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectedModel_\(rawValue)")
        }
    }

    static var current: AIProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "selectedProvider") ?? ""
            return AIProvider(rawValue: raw) ?? .groq
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedProvider")
        }
    }

    func makeService() -> AIProviderService {
        switch self {
        case .groq:
            return OpenAICompatibleService(
                endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                provider: self
            )
        case .openAI:
            return OpenAICompatibleService(
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                provider: self
            )
        case .anthropic:
            return AnthropicAPIService(provider: self)
        case .gemini:
            return GeminiAPIService(provider: self)
        }
    }
}
