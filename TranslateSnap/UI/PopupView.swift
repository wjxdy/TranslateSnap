import SwiftUI

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
        }
        .onAppear {
            viewModel.start()
        }
        .onChange(of: viewModel.pinned) { newValue in
            PopupWindowController.shared.pinStateDidChange(newValue)
        }
    }
}

/// 右下角可拖动手柄，用于调整弹窗大小（top-left 保持不动）
struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(90))
            .padding(6)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        PopupWindowController.shared.resizeBy(
                            dx: value.translation.width,
                            dy: value.translation.height
                        )
                    }
                    .onEnded { _ in
                        PopupWindowController.shared.resizeCommit()
                    }
            )
    }
}
