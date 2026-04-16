import AppKit

@MainActor
class ScreenshotCaptureManager {
    static let shared = ScreenshotCaptureManager()

    func start() {
        let tempFile = NSTemporaryDirectory() + "translatesnap_\(UUID().uuidString).png"
        NSLog("[TranslateSnap] screenshot: tempFile=\(tempFile)")

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", tempFile]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run { self.showError("无法启动截图工具：\(error.localizedDescription)") }
                return
            }

            NSLog("[TranslateSnap] screenshot: process exited, status=\(process.terminationStatus)")
            NSLog("[TranslateSnap] screenshot: file exists=\(FileManager.default.fileExists(atPath: tempFile))")

            guard FileManager.default.fileExists(atPath: tempFile) else {
                NSLog("[TranslateSnap] screenshot: user cancelled")
                return
            }

            guard let image = NSImage(contentsOfFile: tempFile) else {
                NSLog("[TranslateSnap] screenshot: failed to load image")
                try? FileManager.default.removeItem(atPath: tempFile)
                await MainActor.run { self.showError("截图加载失败") }
                return
            }

            NSLog("[TranslateSnap] screenshot: image loaded, size=\(image.size)")
            defer { try? FileManager.default.removeItem(atPath: tempFile) }

            await self.captureAndTranslate(image: image)
        }
    }

    private func captureAndTranslate(image: NSImage) async {
        do {
            let text = try await OCRService.recognize(image: image)
            let settings = AppSettings.shared
            let request = TranslationRequest(
                text: text,
                targetLanguage: settings.targetLanguage,
                style: settings.translationStyle
            )
            let provider = TranslationEngine.provider(for: settings)
            let viewModel = StreamingTranslationViewModel(original: text)
            PopupWindowController.shared.showStreamCentered(viewModel: viewModel)
            viewModel.start(stream: provider.translateStream(request))
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "翻译失败"
        alert.informativeText = message
        alert.runModal()
    }
}
