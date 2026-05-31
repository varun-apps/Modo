import Foundation

final class AnthropicAPIService: AIProviderService {
    private let provider: AIProvider
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let maxTokens = 2048

    init(provider: AIProvider) {
        self.provider = provider
    }

    func streamImprovement(
        text: String,
        mode: ImprovementMode,
        onDelta: @escaping (String) -> Void
    ) async throws {
        guard let apiKey = KeychainService.loadKey(for: provider.keychainAccount), !apiKey.isEmpty else {
            throw APIError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

        let userContent = mode.isDirectPrompt ? text : "<text>\(text)</text>"
        let body: [String: Any] = [
            "model":      provider.currentModelID,
            "max_tokens": maxTokens,
            "stream":     true,
            "system":     mode.systemPrompt,
            "messages": [["role": "user", "content": userContent]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                var raw = ""
                for try await line in bytes.lines { raw += line }
                throw APIError.http(status: http.statusCode, message: extractErrorMessage(from: raw))
            }

            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty,
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["type"] as? String) == "content_block_delta",
                      let delta = json["delta"] as? [String: Any],
                      let chunk = delta["text"] as? String, !chunk.isEmpty
                else { continue }

                let captured = chunk
                await MainActor.run { onDelta(captured) }
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func extractErrorMessage(from raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String { return msg }
        return raw.isEmpty ? "Unknown error" : raw
    }
}
