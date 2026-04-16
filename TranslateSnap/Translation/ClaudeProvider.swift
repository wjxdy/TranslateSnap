import Foundation

class ClaudeProvider: TranslationProvider {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private func buildRequest(_ request: TranslationRequest, stream: Bool) throws -> URLRequest {
        let apiKey = settings.apiKey
        guard !apiKey.isEmpty else { throw TranslationError.noAPIKey }

        let url = URL(string: "\(settings.effectiveBaseURL)/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = TranslationEngine.buildSystemPrompt(targetLanguage: request.targetLanguage, style: request.style)
        var body: [String: Any] = [
            "model": settings.effectiveModel,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": request.text]],
            "metadata": ["session_id": UUID().uuidString]
        ]
        if stream { body["stream"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyText
        }
        let req = try buildRequest(request, stream: false)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.networkError("HTTP \(statusCode)\n\(body)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw TranslationError.parseError
        }
        let parts = text.components(separatedBy: "\n---\n")
        let translation = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let explanation = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return TranslationResult(original: request.text, translation: translation, explanation: explanation)
    }

    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw TranslationError.emptyText
                    }
                    let req = try self.buildRequest(request, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw TranslationError.networkError("HTTP \(statusCode)")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        // Claude SSE: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
                        if let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
