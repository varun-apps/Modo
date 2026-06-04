import Foundation

protocol AIProviderService {
    func streamImprovement(
        text: String,
        mode: Mode,
        modelOverride: String?,
        onDelta: @escaping (String) -> Void
    ) async throws
}

extension AIProviderService {
    func streamImprovement(
        text: String,
        mode: Mode,
        onDelta: @escaping (String) -> Void
    ) async throws {
        try await streamImprovement(text: text, mode: mode, modelOverride: nil, onDelta: onDelta)
    }
}

enum APIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(status: Int, message: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your API key in Preferences."
        case .invalidResponse:
            return "Received an unexpected response from the provider."
        case .http(let status, let message):
            switch status {
            case 401, 403:
                return "Your API key looks invalid or expired. Update it in Preferences."
            case 404:
                return "The provider returned 404. The model name may be wrong — check it in Preferences."
            case 429:
                return "Rate limit or quota reached. Wait a moment, switch models, or check your provider account."
            case 500..<600:
                return "The provider is having issues (HTTP \(status)). Try again in a few moments, or switch providers."
            default:
                let detail = message.isEmpty ? "" : " — \(message)"
                return "API error (\(status))\(detail)"
            }
        case .network(let message):
            let lower = message.lowercased()
            if lower.contains("offline") || lower.contains("internet connection") {
                return "You appear to be offline. Check your network connection."
            }
            if lower.contains("could not connect") || lower.contains("connection refused") {
                return "Couldn't reach the endpoint. If you're using Ollama, make sure it's running locally."
            }
            return "Network error: \(message)"
        }
    }
}
