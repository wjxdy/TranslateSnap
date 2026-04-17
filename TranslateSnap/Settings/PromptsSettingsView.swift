import SwiftUI

struct PromptsSettingsView: View {
    @State private var tabs: [PromptTab] = AppSettings.shared.promptTabs
    @State private var editing: PromptTab? = nil
    @State private var isNew: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($tabs) { $tab in
                    HStack {
                        Toggle("", isOn: $tab.visible)
                            .labelsHidden()
                            .onChange(of: tab.visible) { _ in persist() }
                        Text(tab.name)
                        if tab.isBuiltin {
                            Text("内置")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") {
                            editing = tab
                            isNew = false
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Button(role: .destructive) {
                            deleteTab(tab.id, isBuiltin: tab.isBuiltin)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .onMove { src, dst in
                    tabs.move(fromOffsets: src, toOffset: dst)
                    persist()
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    editing = PromptTab(name: "新提示词", systemPrompt: "", visible: true, isBuiltin: false)
                    isNew = true
                } label: {
                    Label("添加新提示词", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(12)
        }
        .sheet(item: $editing) { tab in
            PromptEditorSheet(
                draft: tab,
                isNew: isNew,
                onCancel: { editing = nil },
                onSave: { saved in
                    if isNew {
                        tabs.append(saved)
                    } else if let idx = tabs.firstIndex(where: { $0.id == saved.id }) {
                        tabs[idx] = saved
                    }
                    persist()
                    editing = nil
                }
            )
        }
    }

    private func deleteTab(_ id: UUID, isBuiltin: Bool) {
        tabs.removeAll { $0.id == id }
        if isBuiltin {
            // 记录用户主动删除的内置 ID，避免下次启动被迁移逻辑补回来
            AppSettings.shared.markBuiltinDeleted(id)
        }
        persist()
    }

    private func persist() {
        AppSettings.shared.promptTabs = tabs
    }
}

struct PromptEditorSheet: View {
    @State private var draft: PromptTab
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (PromptTab) -> Void

    init(draft: PromptTab, isNew: Bool, onCancel: @escaping () -> Void, onSave: @escaping (PromptTab) -> Void) {
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "添加提示词" : (draft.isBuiltin ? "编辑内置提示词" : "编辑提示词"))
                .font(.headline)

            Form {
                TextField("名称", text: $draft.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.systemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.3)))
                }
                Toggle("在弹窗中显示", isOn: $draft.visible)
                VStack(alignment: .leading, spacing: 2) {
                    Text("工作方式：这段提示词会作为 system message，划词选中或截图识别到的文字会作为 user message，一起发送给 AI。")
                    Text("示例：上面写\"把用户的文字翻译成粤语\"，选中的文字被翻译成粤语。想指定输出语言、风格、格式直接写在提示词里。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480, height: 360)
    }
}
