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

    /// 固定 UUID 的内置提示词（可被用户删除，删除记录在 AppSettings.deletedBuiltinIDs）。
    /// 每个 prompt 作为 system message；选中/OCR 出的文字作为 user message 单独一次调用。
    static let builtinDefaults: [PromptTab] = [
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            name: "翻译",
            systemPrompt: "你是一个专业翻译助手。将用户发来的文字翻译成简体中文（若已是中文则翻译成英文），使用自然流畅的表达。只输出翻译结果，不要额外说明。",
            visible: true,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            name: "解释",
            systemPrompt: "用简体中文解释用户发来的内容（术语、背景、典型用法）。如果没有可解释的内容，直接输出\"无\"。",
            visible: true,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            name: "润色",
            systemPrompt: "对用户发来的文字进行润色，使表达更自然流畅、逻辑更清晰，保持原意和原语言不变。只输出润色后的结果。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
            name: "语法检查",
            systemPrompt: "检查用户发来文字的语法、拼写和用词问题，逐条列出错误并给出修正建议（中文说明）。如果没有问题，直接输出\"无\"。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
            name: "总结",
            systemPrompt: "用一两句简体中文概括用户发来内容的核心要点。",
            visible: false,
            isBuiltin: true
        ),
        PromptTab(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000006")!,
            name: "例句",
            systemPrompt: "如果用户发来的是单词或短语，给出 2-3 个实用例句，附简体中文译文。每句一行。如果不是单词或短语，直接输出\"无\"。",
            visible: false,
            isBuiltin: true
        )
    ]
}
