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
                        if !tab.isBuiltin {
                            Button(role: .destructive) {
                                deleteTab(tab.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
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
                Text("占位符：{targetLanguage} / {style}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func deleteTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
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
                Text("占位符 {targetLanguage} 和 {style} 会在调用时替换为当前设置。")
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
