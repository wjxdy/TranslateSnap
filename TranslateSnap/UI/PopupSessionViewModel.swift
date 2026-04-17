import SwiftUI
import AppKit

@MainActor
final class PopupSessionViewModel: ObservableObject {
    struct TabState: Equatable {
        var text: String = ""
        var isLoading: Bool = true
        var error: String? = nil
    }

    enum TriggerKind {
        case selection(cursor: NSPoint)
        case screenshot
    }

    let originalText: String
    let trigger: TriggerKind
    @Published private(set) var tabs: [PromptTab]
    @Published private(set) var states: [UUID: TabState] = [:]
    @Published var pinned: Bool

    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(originalText: String, trigger: TriggerKind) {
        self.originalText = originalText
        self.trigger = trigger
        self.tabs = AppSettings.shared.promptTabs.filter { $0.visible }
        self.pinned = AppSettings.shared.defaultPinned
        for tab in tabs { states[tab.id] = TabState() }
    }

    func start() {
        let settings = AppSettings.shared
        let provider = TranslationEngine.provider(for: settings)
        for tab in tabs {
            spawn(tab: tab, provider: provider, settings: settings)
        }
    }

    func retry(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tasks[tabID]?.cancel()
        states[tabID] = TabState()
        let settings = AppSettings.shared
        let provider = TranslationEngine.provider(for: settings)
        spawn(tab: tab, provider: provider, settings: settings)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func togglePin() {
        pinned.toggle()
        AppSettings.shared.defaultPinned = pinned
    }

    private func spawn(tab: PromptTab, provider: TranslationProvider, settings: AppSettings) {
        let prompt = TranslationEngine.renderPrompt(
            tab.systemPrompt,
            targetLanguage: settings.targetLanguage,
            style: settings.translationStyle
        )
        let request = TranslationRequest(
            text: originalText,
            targetLanguage: settings.targetLanguage,
            style: settings.translationStyle,
            systemPrompt: prompt
        )
        let stream = provider.translateStream(request)
        let id = tab.id
        tasks[id] = Task { [weak self] in
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard var s = self?.states[id] else { return }
                        if s.isLoading { s.isLoading = false }
                        s.text.append(chunk)
                        self?.states[id] = s
                    }
                }
                await MainActor.run {
                    guard var s = self?.states[id] else { return }
                    s.isLoading = false
                    s.text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.states[id] = s
                }
            } catch is CancellationError {
                // intentional cancel — leave state as-is
            } catch {
                await MainActor.run {
                    guard var s = self?.states[id] else { return }
                    s.isLoading = false
                    s.error = error.localizedDescription
                    self?.states[id] = s
                }
            }
        }
    }
}
