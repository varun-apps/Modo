import Foundation

/// Handles any OpenAI-compatible chat completions endpoint (Groq, OpenAI, etc.).
final class OpenAICompatibleService: AIProviderService {
    private let endpoint: URL
    private let provider: AIProvider
    private let maxTokens = 2048

    init(endpoint: URL, provider: AIProvider) {
        self.endpoint = endpoint
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model":      provider.currentModelID,
            "max_tokens": maxTokens,
            "stream":     true,
            "messages": [
                ["role": "system", "content": mode.systemPrompt],
                ["role": "user",   "content": mode.isDirectPrompt ? text : "<text>\(text)</text>"]
            ]
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
                guard !payload.isEmpty, payload != "[DONE]",
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "Unknown streaming error"
                    throw APIError.http(status: http.statusCode, message: msg)
                }

                guard let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let chunk = delta["content"] as? String, !chunk.isEmpty
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
