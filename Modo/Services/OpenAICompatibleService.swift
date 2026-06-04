import Foundation

/// Handles any OpenAI-compatible chat completions endpoint (Groq, OpenAI, etc.).
final class OpenAICompatibleService: AIProviderService {
    private let endpoint: URL
    private let provider: AIProvider

    init(endpoint: URL, provider: AIProvider) {
        self.endpoint = endpoint
        self.provider = provider
    }

    func streamImprovement(
        text: String,
        mode: Mode,
        modelOverride: String?,
        onDelta: @escaping (String) -> Void
    ) async throws {
        let apiKey = KeychainService.loadKey(for: provider.keychainAccount) ?? ""
        if provider.requiresAPIKey && apiKey.isEmpty {
            throw APIError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model":       modelOverride ?? provider.currentModelID,
            "max_tokens":  GenerationSettings.length.maxTokens,
            "temperature": GenerationSettings.temperature,
            "stream":      true,
            "messages": [
                ["role": "system", "content": PersonalInstructions.composeSystemPrompt(for: mode)],
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
        } catch let urlError as URLError where provider == .ollama &&
                (urlError.code == .cannotConnectToHost || urlError.code == .cannotFindHost) {
            throw APIError.network("Ollama doesn't appear to be running. Open Terminal and run `ollama serve`, or start the Ollama app.")
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
