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

    static var builtinDefaults: [PromptTab] {
        [
            PromptTab(
                name: "翻译",
                systemPrompt: "将下列文字翻译为 {targetLanguage}，风格：{style}。只输出翻译结果，不要额外说明。",
                visible: true,
                isBuiltin: true
            ),
            PromptTab(
                name: "解释",
                systemPrompt: "解释下列内容（术语、背景、典型用法）。如果没有可解释的内容，直接输出\"无\"。",
                visible: true,
                isBuiltin: true
            )
        ]
    }
}
