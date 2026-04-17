import SwiftUI
import AppKit

struct PopupRootView: View {
    @ObservedObject var viewModel: PopupSessionViewModel
    @AppStorage("showOriginal") private var showOriginal: Bool = true
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopupHeaderBar(
                pinned: viewModel.pinned,
                onTogglePin: { viewModel.togglePin() },
                onClose: onClose
            )
            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        if showOriginal {
                            OriginalCard(text: viewModel.originalText)
                            Divider().opacity(0.4)
                        }
                        if viewModel.tabs.isEmpty {
                            EmptyHintView(onOpenSettings: onOpenSettings)
                        } else {
                            ForEach(viewModel.tabs) { tab in
                                TabCard(
                                    tab: tab,
                                    state: viewModel.states[tab.id] ?? PopupSessionViewModel.TabState(),
                                    onRetry: { viewModel.retry(tabID: tab.id) }
                                )
                                if tab.id != viewModel.tabs.last?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.states) { _ in
                    proxy.scrollTo("bottom")
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 400)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            ResizeHandle()
                .frame(width: 18, height: 18)
                .padding(2)
        }
        .onAppear {
            viewModel.start()
        }
        .onChange(of: viewModel.pinned) { newValue in
            PopupWindowController.shared.pinStateDidChange(newValue)
        }
    }
}

/// 右下角可拖动手柄。直接用 NSView 处理鼠标事件，
/// 并通过 `mouseDownCanMoveWindow = false` 避免被 `isMovableByWindowBackground` 吞掉 drag。
struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ResizeHandleNSView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private var startTop: CGFloat?

    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
        ctx.setLineWidth(1.2)
        let pad: CGFloat = 4
        // 画两条平行的 45° 斜线，提示可拖动
        for offset in stride(from: CGFloat(0), through: CGFloat(6), by: 4) {
            ctx.move(to: CGPoint(x: bounds.maxX - pad, y: bounds.minY + pad + offset))
            ctx.addLine(to: CGPoint(x: bounds.minX + pad + offset, y: bounds.maxY - pad))
        }
        ctx.strokePath()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        startTop = window.frame.origin.y + window.frame.size.height
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let startTop = startTop else { return }
        let minW: CGFloat = 280, minH: CGFloat = 160, maxW: CGFloat = 1000, maxH: CGFloat = 900
        // event.deltaY 在 macOS 屏幕向下拖动时为 正值，正好对应"加高"
        let newW = min(max(minW, window.frame.size.width + event.deltaX), maxW)
        let newH = min(max(minH, window.frame.size.height + event.deltaY), maxH)
        var frame = window.frame
        frame.size = NSSize(width: newW, height: newH)
        frame.origin.y = startTop - newH  // 保持顶部固定
        window.setFrame(frame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        defer { startTop = nil }
        guard let window = window else { return }
        AppSettings.shared.setSavedPopupSize(window.frame.size)
    }
}
