import SwiftUI
import AVFoundation

// MARK: - HeaderBar

struct PopupHeaderBar: View {
    let pinned: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(pinned ? "取消钉住" : "钉住到最前")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - OriginalCard

struct OriginalCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("原文")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - TabCard

struct TabCard: View {
    let tab: PromptTab
    let state: PopupSessionViewModel.TabState
    let onRetry: () -> Void
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tab.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if state.isLoading {
                    ProgressView().scaleEffect(0.5).frame(height: 10)
                }
                Spacer()
                if !state.text.isEmpty {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                    }.buttonStyle(.plain).help("复制")
                    Button(action: speak) {
                        Image(systemName: "speaker.wave.2").font(.system(size: 10))
                    }.buttonStyle(.plain).help("朗读")
                }
            }
            if let err = state.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("重试", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if state.isLoading && state.text.isEmpty {
                Text("生成中…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text(state.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.text, forType: .string)
    }

    private func speak() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: state.text))
    }
}

// MARK: - EmptyHint

struct EmptyHintView: View {
    let onOpenSettings: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("暂无可用的提示词")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("打开设置", action: onOpenSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(24)
    }
}
