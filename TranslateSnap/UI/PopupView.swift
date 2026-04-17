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
            .frame(maxHeight: 400)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.start()
        }
        .onChange(of: viewModel.pinned) { newValue in
            PopupWindowController.shared.pinStateDidChange(newValue)
        }
    }
}
