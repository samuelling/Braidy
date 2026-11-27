import AVFoundation

/// How one line should sound.
struct VoiceStyle {
    var voiceID: String
    /// AVSpeechUtterance pitch, 0.5–2.0.
    var pitch: Float = 1.0
    /// Multiplier on the base speed.
    var rate: Float = 1.0
    /// Word → respelling for this game's names and terms.
    var pronunciations: [String: String] = [:]
    /// ElevenLabs voice to use when that engine is on.
    var elevenVoiceID: String?
    /// How to perform the line, when Expressive voices is on.
    var mood: Mood? = nil
}

/// Text-to-speech with a few game-name pronunciation fixes.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    /// Set when ElevenLabs is the voice engine and a key is saved; nil means Apple's voices.
    var eleven: ElevenClient?
    var elevenModel = "eleven_flash_v2_5"
    /// Called when ElevenLabs fails and a line falls back to Apple's voice.
    var onError: ((String) -> Void)?
    private var player: AVAudioPlayer?
    private var fetch: Task<Void, Never>?
    /// Base speed (AVSpeechUtterance rate, default system speed is 0.5).
    var baseRate: Float = 0.42
    var onSpeaking: ((Bool) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// A line to say as soon as the current one finishes (e.g. Bubble Buddy's "Again, brodie!" then the line).
    private var next: (text: String, style: VoiceStyle)?

    func speak(_ text: String, style: VoiceStyle, then follow: (text: String, style: VoiceStyle)? = nil) {
        stop()
        next = follow
        start(text, style: style)
    }

    /// Say the queued line, if any. Returns false when nothing was waiting.
    private func advance() -> Bool {
        guard let n = next else { return false }
        next = nil
        start(n.text, style: n.style)
        return true
    }

    private func start(_ text: String, style: VoiceStyle) {
        if let client = eleven, let voice = style.elevenVoiceID, !voice.isEmpty {
            // ElevenLabs says game names well on its own, so only clean the text (no respellings).
            let clean = Pronounce.prepare(text, extra: [:], respell: false)
            guard !clean.isEmpty else { return }
            // ElevenLabs accepts speed 0.7–1.2; the user's base speed (0.42 ≈ normal) scales it too.
            let speed = min(max((Double(baseRate) / 0.45) * (1 + (Double(style.rate) - 1) * 0.6), 0.7), 1.2)
            let model = elevenModel
            // The expressive model takes the mood as an audio tag; the tag is part of the cache key,
            // so a line said sadly in one scene and happily in another is kept as two recordings.
            var said = clean
            if ElevenClient.takesAudioTags(model), let tag = style.mood?.elevenTag { said = "[\(tag)] " + clean }
            fetch = Task { [weak self] in
                do {
                    let data = try await AudioCache.shared.audio(text: said, voiceID: voice, model: model, speed: speed) {
                        try await client.speech(said, voiceID: voice, model: model, speed: speed)
                    }
                    try Task.checkCancellation()
                    await MainActor.run { self?.play(data) }
                } catch is CancellationError {
                } catch {
                    if (error as? URLError)?.code == .cancelled { return }
                    await MainActor.run {
                        self?.onError?(error.localizedDescription)
                        self?.speakApple(text, style: style)
                    }
                }
            }
            return
        }
        speakApple(text, style: style)
    }

    private func play(_ data: Data) {
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.delegate = self
        player = p
        p.play()
        onSpeaking?(true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { if !self.advance() { self.onSpeaking?(false) } }
    }

    private func speakApple(_ text: String, style: VoiceStyle) {
        let spoken = Pronounce.prepare(text, extra: style.pronunciations)
        guard !spoken.isEmpty else { return }
        let u = AVSpeechUtterance(string: spoken)
        // Big pitch and speed shifts make the synthesizer sound robotic, so a character's settings are
        // compressed toward natural: pitch 0.5–2.0 maps to about 0.8–1.35, speed changes are softened.
        let rate = baseRate * (1 + (style.rate - 1) * 0.6) * (style.mood?.rate ?? 1)
        u.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        u.pitchMultiplier = min(max((1 + (style.pitch - 1) * 0.5) * (style.mood?.pitch ?? 1), 0.75), 1.4)
        u.postUtteranceDelay = 0.1
        u.voice = AVSpeechSynthesisVoice(identifier: style.voiceID) ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() {
        next = nil
        fetch?.cancel()
        fetch = nil
        if let p = player {
            p.stop()
            player = nil
            onSpeaking?(false)
        }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeaking?(true) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.synth.isSpeaking || self.advance() { return }
            self.onSpeaking?(false)
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeaking?(self.synth.isSpeaking) }
    }

    /// English voices worth offering, best quality first. Skips novelty and Personal Voice.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
                let aUS = a.language == "en-US", bUS = b.language == "en-US"
                if aUS != bUS { return aUS }
                return a.name < b.name
            }
    }

    static func label(_ v: AVSpeechSynthesisVoice) -> String {
        let region = v.language.replacingOccurrences(of: "en-", with: "")
        let gender: String
        switch v.gender {
        case .male: gender = "♂"
        case .female: gender = "♀"
        default: gender = ""
        }
        let quality: String
        switch v.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(v.name) \(gender) (\(region))\(quality)"
    }
}

enum Pronounce {
    /// Common franchise words, spelled the way the speech engine gets them right.
    /// Each game adds its own through Claude's vocabulary lookup.
    private static let fixes: [(String, String)] = [
        ("Hyrule", "Hi-rule"), ("Zonai", "Zoh-nye"), ("Sheikah", "Shay-kah"), ("Gerudo", "Geh-roo-doe"),
        ("Koroks", "Koh-rocks"), ("Korok", "Koh-rock"), ("Rito", "Ree-toe"), ("Lynel", "Lie-nel"),
        ("Bokoblin", "Boh-koh-blin"), ("Purah", "Poo-rah"), ("Rauru", "Rah-oo-roo"), ("Riju", "Ree-joo"),
        ("Pokémon", "Poh-kay-mon"), ("Pokemon", "Poh-kay-mon"),
    ]
    private static let regexes: [(NSRegularExpression, String)] = fixes.compactMap { word, say in
        guard let re = try? NSRegularExpression(pattern: "\\b\(word)\\b", options: [.caseInsensitive]) else { return nil }
        return (re, say)
    }
    private static let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        .union(CharacterSet(charactersIn: ".,!?'’\"“”-—:;()…%&"))

    static func prepare(_ text: String, extra: [String: String] = [:], respell: Bool = true) -> String {
        // Drop on-screen glyphs (▼, button icons misread as symbols).
        var s = String(String.UnicodeScalarView(text.unicodeScalars.map { allowed.contains($0) ? $0 : " " }))
        guard respell else { return s.split(separator: " ").joined(separator: " ") }
        // Longest words first, so "Koroks" wins over "Korok".
        let gameFixes: [(NSRegularExpression, String)] = extra.sorted { $0.key.count > $1.key.count }.compactMap { word, say in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (re, NSRegularExpression.escapedTemplate(for: say))
        }
        for (re, say) in gameFixes + regexes {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: say)
        }
        return s.split(separator: " ").joined(separator: " ")
    }
}
