import Foundation

struct PromptTab: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var visible: Bool
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, systemPrompt: String, visible: Bool = true, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.visible = visible
        self.isBuiltin = isBuiltin
    }

    /// 固定 UUID 的内置提示词。通过 ID 稳定性，AppSettings 可以在读取时补齐用户尚未拥有的内置。
    static let builtinDefaults: [PromptTab] = [
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            name: "翻译",
            systemPrompt: "将下列文字翻译为 {targetLanguage}，使用自然流畅的表达。只输出翻译结果，不要额外说明。",
            visible: true,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            name: "解释",
            systemPrompt: "解释下列内容（术语、背景、典型用法）。如果没有可解释的内容，直接输出\"无\"。",
            visible: true,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            name: "润色",
            systemPrompt: "对下列内容进行润色，使表达更自然流畅、逻辑更清晰，保持原意不变。只输出润色后的结果。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
            name: "语法检查",
            systemPrompt: "检查下列文字的语法、拼写和用词问题，逐条列出错误并给出修正建议（用 {targetLanguage} 说明）。如果没有问题，直接输出\"无\"。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
            name: "总结",
            systemPrompt: "用一两句话概括下列内容的核心要点，用 {targetLanguage} 输出。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000006")!,
            name: "例句",
            systemPrompt: "如果下列内容是单词或短语，给出 2-3 个实用例句，并附 {targetLanguage} 译文。每句一行。如果不是单词或短语，直接输出\"无\"。",
            visible: false,
            isBuiltin: true
        )
    ]
}
