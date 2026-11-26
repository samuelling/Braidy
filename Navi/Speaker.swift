import AVFoundation

/// How one line should sound.
struct VoiceStyle {
    var voiceID: String
    /// AVSpeechUtterance pitch, 0.5–2.0.
    var pitch: Float = 1.0
    /// Multiplier on the base speed.
    var rate: Float = 1.0
}

/// Text-to-speech with a few game-name pronunciation fixes.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    /// Base speed (AVSpeechUtterance rate, default system speed is 0.5).
    var baseRate: Float = 0.42
    var onSpeaking: ((Bool) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, style: VoiceStyle) {
        let spoken = Pronounce.prepare(text)
        guard !spoken.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: spoken)
        let rate = baseRate * style.rate
        u.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        u.pitchMultiplier = min(max(style.pitch, 0.5), 2.0)
        u.postUtteranceDelay = 0.1
        u.voice = AVSpeechSynthesisVoice(identifier: style.voiceID) ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeaking?(true) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeaking?(self.synth.isSpeaking) }
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
    /// Spelled the way the speech engine gets them right.
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

    static func prepare(_ text: String) -> String {
        // Drop on-screen glyphs (▼, button icons misread as symbols).
        var s = String(String.UnicodeScalarView(text.unicodeScalars.map { allowed.contains($0) ? $0 : " " }))
        for (re, say) in regexes {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: say)
        }
        return s.split(separator: " ").joined(separator: " ")
    }
}
