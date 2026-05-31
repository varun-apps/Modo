import Foundation

protocol AIProviderService {
    func streamImprovement(
        text: String,
        mode: ImprovementMode,
        onDelta: @escaping (String) -> Void
    ) async throws
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
            return "Received an unexpected response from the API."
        case .http(let status, let message):
            return "API error (\(status)): \(message)"
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}
