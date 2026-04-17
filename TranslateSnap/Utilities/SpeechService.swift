import Foundation
import AVFoundation
import AppKit

enum SpeechEngine: String, CaseIterable {
    case system
    case google

    var displayName: String {
        switch self {
        case .system: return "系统语音 (AVSpeech)"
        case .google: return "Google Translate"
        }
    }
}

@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let systemSynth = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

    func speak(_ text: String, language: String) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let engine = AppSettings.shared.speechEngine
        switch engine {
        case .system:
            let utterance = AVSpeechUtterance(string: trimmed)
            if let voice = AVSpeechSynthesisVoice(language: Self.bcp47(for: language)) {
                utterance.voice = voice
            }
            systemSynth.speak(utterance)
        case .google:
            playGoogleTTS(text: trimmed, language: language)
        }
    }

    func stop() {
        systemSynth.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        currentTask?.cancel()
        currentTask = nil
    }

    private func playGoogleTTS(text: String, language: String) {
        let code = Self.bcp47(for: language)
        // translate_tts 的非官方端点对单次请求约 200 字符上限
        let truncated = String(text.prefix(200))
        guard let encoded = truncated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&q=\(encoded)&tl=\(code)&client=tw-ob")
        else { return }

        currentTask = Task { [weak self] in
            var req = URLRequest(url: url)
            req.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0",
                forHTTPHeaderField: "User-Agent"
            )
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if Task.isCancelled { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    NSLog("[TranslateSnap] SpeechService: Google TTS HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
                await MainActor.run {
                    do {
                        let player = try AVAudioPlayer(data: data)
                        self?.audioPlayer = player
                        player.play()
                    } catch {
                        NSLog("[TranslateSnap] SpeechService: AVAudioPlayer init failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    NSLog("[TranslateSnap] SpeechService: Google TTS fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    static func bcp47(for language: String) -> String {
        switch language {
        case "简体中文": return "zh-CN"
        case "繁體中文": return "zh-TW"
        case "English": return "en"
        case "日本語": return "ja"
        case "한국어": return "ko"
        case "Français": return "fr"
        case "Deutsch": return "de"
        case "Español": return "es"
        default: return "en"
        }
    }
}
