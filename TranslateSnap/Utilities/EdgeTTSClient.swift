import Foundation

/// Microsoft Edge 浏览器的 "大声朗读" 用的免费 TTS WebSocket 端点封装。
/// 协议细节来自 edge-tts（Python）开源项目，无需 API Key。
final class EdgeTTSClient: NSObject {
    private let endpoint = URL(string: "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4")!

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var audioData = Data()
    private var completion: ((Data?) -> Void)?
    private var cancelled = false

    func synthesize(text: String, voice: String, languageTag: String, completion: @escaping (Data?) -> Void) {
        self.completion = completion
        self.audioData = Data()
        self.cancelled = false

        let session = URLSession(configuration: .default)
        self.session = session

        var req = URLRequest(url: endpoint)
        req.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.77 Safari/537.36 Edg/91.0.864.41", forHTTPHeaderField: "User-Agent")

        let task = session.webSocketTask(with: req)
        self.task = task
        task.resume()

        sendSpeechConfig()
        sendSSML(text: text, voice: voice, languageTag: languageTag)
        receiveLoop()
    }

    func stop() {
        cancelled = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        completion = nil
    }

    private func sendSpeechConfig() {
        let ts = Self.iso8601Timestamp()
        let body = "X-Timestamp:\(ts)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}"
        task?.send(.string(body)) { [weak self] err in
            if let err = err {
                NSLog("[TranslateSnap] EdgeTTS send config err: \(err.localizedDescription)")
                self?.finish(nil)
            }
        }
    }

    private func sendSSML(text: String, voice: String, languageTag: String) {
        let ts = Self.iso8601Timestamp()
        let reqId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        let ssml = "X-RequestId:\(reqId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(ts)\r\nPath:ssml\r\n\r\n<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(languageTag)'><voice name='\(voice)'>\(escaped)</voice></speak>"
        task?.send(.string(ssml)) { [weak self] err in
            if let err = err {
                NSLog("[TranslateSnap] EdgeTTS send ssml err: \(err.localizedDescription)")
                self?.finish(nil)
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self, !self.cancelled else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s):
                    if s.contains("Path:turn.end") {
                        self.finish(self.audioData.isEmpty ? nil : self.audioData)
                        return
                    }
                case .data(let d):
                    self.appendAudio(from: d)
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let err):
                NSLog("[TranslateSnap] EdgeTTS receive err: \(err.localizedDescription)")
                self.finish(self.audioData.isEmpty ? nil : self.audioData)
            }
        }
    }

    /// 每条 binary 消息格式：2 字节大端 header length + headers + MP3 audio
    private func appendAudio(from raw: Data) {
        guard raw.count >= 2 else { return }
        let headerLen = (Int(raw[0]) << 8) | Int(raw[1])
        let audioStart = 2 + headerLen
        guard audioStart < raw.count else { return }
        audioData.append(raw.subdata(in: audioStart..<raw.count))
    }

    private func finish(_ data: Data?) {
        let cb = completion
        completion = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        cb?(data)
    }

    private static func iso8601Timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: Date())
    }
}
