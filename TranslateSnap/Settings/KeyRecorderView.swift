import SwiftUI
import AppKit

struct KeyRecorderView: View {
    let label: String
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var isRecording = false

    var displayString: String {
        HotkeyUtils.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Button(action: { isRecording.toggle() }) {
                    Text(isRecording ? "按下快捷键..." : displayString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(isRecording ? .blue : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isRecording ? Color.blue.opacity(0.1) : Color.clear)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .background(isRecording ? KeyCaptureRepresentable(
                    onKeyDown: { event in
                        if event.keyCode == 53 { // ESC cancels
                            isRecording = false
                            return
                        }
                        let mods = HotkeyUtils.modifiersFromNSEvent(event)
                        // Require at least one modifier key
                        guard mods != 0 else { return }
                        keyCode = Int(event.keyCode)
                        modifiers = mods
                        isRecording = false
                    }
                ) : nil)
            }
        }
    }
}

struct KeyCaptureRepresentable: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
