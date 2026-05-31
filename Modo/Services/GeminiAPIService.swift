import Foundation

final class GeminiAPIService: AIProviderService {
    private let provider: AIProvider
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

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.currentModelID):streamGenerateContent"
        )!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "alt", value: "sse")
        ]
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userContent = mode.isDirectPrompt ? text : "<text>\(text)</text>"
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": mode.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userContent]]]],
            "generationConfig": ["maxOutputTokens": maxTokens]
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
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let chunk = parts.first?["text"] as? String, !chunk.isEmpty
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
