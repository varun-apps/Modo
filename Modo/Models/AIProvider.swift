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
    case ollama
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq:      return "Groq"
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Google Gemini"
        case .ollama:    return "Ollama (local)"
        case .custom:    return "Custom (OpenAI-compatible)"
        }
    }

    // Groq keeps the legacy account string so existing keys migrate automatically.
    var keychainAccount: String {
        switch self {
        case .groq:      return "groq-api-key"
        case .openAI:    return "openai-api-key"
        case .anthropic: return "anthropic-api-key"
        case .gemini:    return "gemini-api-key"
        case .ollama:    return "ollama-api-key"
        case .custom:    return "custom-api-key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .groq:      return "gsk_…"
        case .openAI:    return "sk-…"
        case .anthropic: return "sk-ant-…"
        case .gemini:    return "AIza…"
        case .ollama:    return "Not required"
        case .custom:    return "Optional"
        }
    }

    var keyHelpText: String {
        switch self {
        case .groq:      return "Get a free key at console.groq.com"
        case .openAI:    return "Get a key at platform.openai.com"
        case .anthropic: return "Get a key at console.anthropic.com"
        case .gemini:    return "Get a free key at aistudio.google.com"
        case .ollama:    return "Ollama runs locally — leave blank unless your instance requires a key."
        case .custom:    return "Any OpenAI-compatible endpoint (OpenRouter, Together, Azure, etc.)."
        }
    }

    /// Whether this provider requires an API key to function.
    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default:      return true
        }
    }

    /// Whether the selection never leaves the Mac when using this provider.
    /// Ollama is always local; a Custom provider counts as local only when its
    /// endpoint points at localhost. Used by the "local-only" network mode.
    var isLocal: Bool {
        switch self {
        case .ollama:
            return true
        case .custom:
            let host = URL(string: currentEndpointString)?.host?.lowercased() ?? ""
            return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
        default:
            return false
        }
    }

    /// Whether the user types the model name as free text (true) or picks from
    /// a fixed list (false).
    var usesCustomModelName: Bool {
        switch self {
        case .ollama, .custom: return true
        default:               return false
        }
    }

    /// Whether the endpoint URL is user-configurable.
    var usesCustomEndpoint: Bool {
        switch self {
        case .ollama, .custom: return true
        default:               return false
        }
    }

    var models: [ProviderModel] {
        switch self {
        case .groq:
            return [
                ProviderModel(id: "llama-3.3-70b-versatile",  displayName: "Llama 3.3 70B (recommended)"),
                ProviderModel(id: "openai/gpt-oss-20b",        displayName: "GPT OSS 20B")
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
        case .ollama, .custom:
            return []
        }
    }

    var defaultModel: ProviderModel {
        if let first = models.first { return first }
        // Free-text model providers don't expose a list — return a sensible default.
        switch self {
        case .ollama: return ProviderModel(id: "llama3.2", displayName: "llama3.2")
        case .custom: return ProviderModel(id: "", displayName: "")
        default:      return ProviderModel(id: "", displayName: "")
        }
    }

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

    /// Default endpoint URL for providers that allow customization.
    var defaultEndpointString: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        case .custom: return ""
        default:      return ""
        }
    }

    /// User-configurable endpoint URL (only meaningful for Ollama/Custom).
    var currentEndpointString: String {
        get {
            UserDefaults.standard.string(forKey: "endpoint_\(rawValue)") ?? defaultEndpointString
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "endpoint_\(rawValue)")
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
        case .ollama, .custom:
            let endpoint = URL(string: currentEndpointString)
                ?? URL(string: "http://localhost:11434/v1/chat/completions")!
            return OpenAICompatibleService(endpoint: endpoint, provider: self)
        }
    }
}
