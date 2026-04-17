import Foundation
import AVFoundation
import AppKit
import NaturalLanguage

enum SpeechEngine: String, CaseIterable {
    case edge
    case google
    case system

    var displayName: String {
        switch self {
        case .edge:   return "Edge TTS (Neural，推荐)"
        case .google: return "Google Translate"
        case .system: return "系统语音 (AVSpeech)"
        }
    }
}

@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let systemSynth = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?
    private var edgeClient: EdgeTTSClient?

    // MARK: - Public API

    /// 用"目标语言"显示名指定语言（来自 AppSettings.targetLanguage）
    func speak(_ text: String, language: String) {
        let tag = Self.bcp47(for: language)
        speakInternal(text, languageTag: tag)
    }

    /// 用 NLLanguageRecognizer 自动检测文本语言后朗读（用于原文卡片）
    func speakAutoDetect(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let tag: String
        if let nl = recognizer.dominantLanguage {
            tag = Self.normalizeNLTag(nl.rawValue)
        } else {
            tag = "en-US"
        }
        speakInternal(trimmed, languageTag: tag)
    }

    func stop() {
        systemSynth.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        currentTask?.cancel()
        currentTask = nil
        edgeClient?.stop()
        edgeClient = nil
    }

    // MARK: - Core

    private func speakInternal(_ text: String, languageTag tag: String) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let engine = AppSettings.shared.speechEngine
        switch engine {
        case .system:
            let utterance = AVSpeechUtterance(string: trimmed)
            if let voice = AVSpeechSynthesisVoice(language: tag) {
                utterance.voice = voice
            }
            systemSynth.speak(utterance)

        case .google:
            playGoogleTTS(text: trimmed, languageTag: tag)

        case .edge:
            playEdgeTTS(text: trimmed, languageTag: tag)
        }
    }

    // MARK: - Google

    private func playGoogleTTS(text: String, languageTag: String) {
        let truncated = String(text.prefix(200))
        let shortCode = Self.googleShortCode(for: languageTag)
        guard let encoded = truncated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&q=\(encoded)&tl=\(shortCode)&client=tw-ob")
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
                    NSLog("[TranslateSnap] Google TTS HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
                await MainActor.run {
                    do {
                        let p = try AVAudioPlayer(data: data)
                        self?.audioPlayer = p
                        p.play()
                    } catch {
                        NSLog("[TranslateSnap] Google TTS play err: \(error.localizedDescription)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    NSLog("[TranslateSnap] Google TTS fetch err: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Edge

    private func playEdgeTTS(text: String, languageTag: String) {
        let (voice, tag) = Self.edgeVoice(for: languageTag)
        let client = EdgeTTSClient()
        edgeClient = client
        client.synthesize(text: text, voice: voice, languageTag: tag) { [weak self] data in
            Task { @MainActor in
                guard let self = self, let data = data, !data.isEmpty else {
                    NSLog("[TranslateSnap] Edge TTS returned no audio")
                    return
                }
                do {
                    let p = try AVAudioPlayer(data: data)
                    self.audioPlayer = p
                    p.play()
                } catch {
                    NSLog("[TranslateSnap] Edge TTS play err: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Language code maps

    /// 目标语言显示名 → BCP-47（e.g. "en-US"）
    static func bcp47(for language: String) -> String {
        switch language {
        case "简体中文": return "zh-CN"
        case "繁體中文": return "zh-TW"
        case "English": return "en-US"
        case "日本語": return "ja-JP"
        case "한국어": return "ko-KR"
        case "Français": return "fr-FR"
        case "Deutsch": return "de-DE"
        case "Español": return "es-ES"
        default: return "en-US"
        }
    }

    /// Google translate_tts 参数（短码）
    static func googleShortCode(for bcp47: String) -> String {
        switch bcp47 {
        case "zh-CN": return "zh-CN"
        case "zh-TW": return "zh-TW"
        case "en-US", "en-GB": return "en"
        case "ja-JP": return "ja"
        case "ko-KR": return "ko"
        case "fr-FR": return "fr"
        case "de-DE": return "de"
        case "es-ES": return "es"
        default: return bcp47.split(separator: "-").first.map(String.init) ?? "en"
        }
    }

    /// Edge 神经网络声音（voice 名 + xml:lang 标签）
    static func edgeVoice(for bcp47: String) -> (voice: String, tag: String) {
        switch bcp47 {
        case "zh-CN": return ("zh-CN-XiaoxiaoNeural", "zh-CN")
        case "zh-TW": return ("zh-TW-HsiaoChenNeural", "zh-TW")
        case "en-US", "en-GB", "en": return ("en-US-AriaNeural", "en-US")
        case "ja-JP", "ja": return ("ja-JP-NanamiNeural", "ja-JP")
        case "ko-KR", "ko": return ("ko-KR-SunHiNeural", "ko-KR")
        case "fr-FR", "fr": return ("fr-FR-DeniseNeural", "fr-FR")
        case "de-DE", "de": return ("de-DE-KatjaNeural", "de-DE")
        case "es-ES", "es": return ("es-ES-ElviraNeural", "es-ES")
        default: return ("en-US-AriaNeural", "en-US")
        }
    }

    /// NLLanguage.rawValue → BCP-47
    static func normalizeNLTag(_ nlCode: String) -> String {
        switch nlCode {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "es": return "es-ES"
        default:
            // 保留 BCP-47-ish 形式；如果只给了 2 字母，用主语言标签即可
            return nlCode
        }
    }
}
