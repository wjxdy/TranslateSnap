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

    static func buildSystemPrompt(targetLanguage: String, style: TranslationStyle) -> String {
        let styleInstruction: String
        switch style {
        case .literal: styleInstruction = "直译，保持原文结构"
        case .natural: styleInstruction = "意译，使用自然流畅的表达"
        case .professional: styleInstruction = "专业翻译，并解释术语背景和使用场景"
        }

        return """
        你是一个专业翻译助手。将用户提供的文字翻译成\(targetLanguage)，风格：\(styleInstruction)。
        请按以下格式输出（不要输出其他内容）：
        先输出翻译内容，然后输出一行只包含 --- 的分隔线，最后输出解释。
        如果没有需要解释的内容，分隔线后写"无"。
        """
    }
}
