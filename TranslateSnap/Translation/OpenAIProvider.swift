import Foundation

class OpenAIProvider: TranslationProvider {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private func buildRequest(_ request: TranslationRequest, stream: Bool) throws -> URLRequest {
        let apiKey = settings.apiKey
        guard !apiKey.isEmpty else { throw TranslationError.noAPIKey }

        let url = URL(string: "\(settings.effectiveBaseURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = request.systemPrompt
        var body: [String: Any] = [
            "model": settings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": request.text]
            ]
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
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.parseError
        }
        let translation = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationResult(original: request.text, translation: translation)
    }

    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
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
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
