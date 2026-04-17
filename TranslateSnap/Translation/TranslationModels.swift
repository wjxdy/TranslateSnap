import Foundation

struct TranslationRequest {
    let text: String
    let targetLanguage: String
    let style: TranslationStyle
    let systemPrompt: String
}

struct TranslationResult {
    let original: String
    let translation: String
    let explanation: String?
}

protocol TranslationProvider {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}

enum TranslationError: LocalizedError {
    case noAPIKey
    case networkError(String)
    case parseError
    case emptyText

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "请先在设置中填写 API Key"
        case .networkError(let msg): return "网络错误：\(msg)"
        case .parseError: return "解析响应失败"
        case .emptyText: return "没有识别到文字"
        }
    }
}

class TranslationEngine {
    static func provider(for settings: AppSettings) -> TranslationProvider {
        switch settings.aiProvider {
        case .claude:
            return ClaudeProvider(settings: settings)
        case .openai, .kimi, .custom:
            return OpenAIProvider(settings: settings)
        }
    }

    static func renderPrompt(
        _ template: String,
        targetLanguage: String,
        style: TranslationStyle
    ) -> String {
        template
            .replacingOccurrences(of: "{targetLanguage}", with: targetLanguage)
            .replacingOccurrences(of: "{style}", with: style.displayName)
    }

}
