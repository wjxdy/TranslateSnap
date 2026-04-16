import AppKit
import Vision

class OCRService {
    static func recognize(image: NSImage) async throws -> String {
        NSLog("[TranslateSnap] OCR: image size=\(image.size), representations=\(image.representations.count)")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSLog("[TranslateSnap] OCR: cgImage conversion FAILED")
            throw TranslationError.emptyText
        }
        NSLog("[TranslateSnap] OCR: cgImage ok, \(cgImage.width)x\(cgImage.height)")

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: TranslationError.networkError(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                NSLog("[TranslateSnap] OCR: recognized text length=\(text.count): \(String(text.prefix(100)))")
                if text.isEmpty {
                    continuation.resume(throwing: TranslationError.emptyText)
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: TranslationError.networkError(error.localizedDescription))
            }
        }
    }
}
