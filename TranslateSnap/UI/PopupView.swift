import SwiftUI
import AVFoundation

struct StreamPopupView: View {
    @ObservedObject var viewModel: StreamingTranslationViewModel
    @State private var synthesizer = AVSpeechSynthesizer()
    @AppStorage("showOriginal") private var showOriginal: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        if showOriginal {
                            section(title: "原文", content: viewModel.original, isLoading: false)
                            Divider().opacity(0.4)
                        }

                        translationSection
                        Divider().opacity(0.4)
                        explanationSection

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.translation) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: viewModel.explanation) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            .frame(maxHeight: 400)

            Divider()

            HStack(spacing: 8) {
                Button(action: copyTranslation) {
                    Label("复制", systemImage: "doc.on.doc").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.translation.isEmpty)

                Button(action: speakTranslation) {
                    Label("朗读", systemImage: "speaker.wave.2").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.translation.isEmpty)

                Spacer()

                Text("ESC 关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("翻译")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.5).frame(height: 10)
                }
            }
            if viewModel.isLoading && viewModel.translation.isEmpty {
                Text("正在翻译…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.translation)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解释")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if viewModel.explanation.isEmpty {
                Text(viewModel.isFinished ? "（无）" : "等待中…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                Text(viewModel.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section(title: String, content: String, isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.translation, forType: .string)
    }

    private func speakTranslation() {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: viewModel.translation)
        synthesizer.speak(utterance)
    }
}
