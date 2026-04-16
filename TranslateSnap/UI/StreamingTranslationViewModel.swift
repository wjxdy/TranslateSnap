import SwiftUI

@MainActor
class StreamingTranslationViewModel: ObservableObject {
    @Published var original: String
    @Published var translation: String = ""
    @Published var explanation: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var isFinished: Bool = false

    init(original: String) {
        self.original = original
    }

    func start(stream: AsyncThrowingStream<String, Error>) {
        Task {
            var buffer = ""
            var inExplanation = false
            do {
                for try await chunk in stream {
                    buffer += chunk
                    if isLoading { isLoading = false }

                    if !inExplanation, let range = buffer.range(of: "\n---\n") {
                        let beforeSep = String(buffer[..<range.lowerBound])
                        let afterSep = String(buffer[range.upperBound...])
                        translation = beforeSep.trimmingCharacters(in: .whitespacesAndNewlines)
                        explanation = afterSep
                        inExplanation = true
                        buffer = ""
                    } else if inExplanation {
                        explanation += chunk
                    } else {
                        translation = buffer
                    }
                }
                // Final cleanup
                translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                if explanation == "无" { explanation = "" }
                isFinished = true
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                isFinished = true
            }
        }
    }
}
