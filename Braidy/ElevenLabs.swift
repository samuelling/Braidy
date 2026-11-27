import CryptoKit
import Foundation

/// A voice in the user's ElevenLabs account (their default/premade voices plus any they've added).
struct ElevenVoice: Codable, Hashable, Identifiable {
    var id: String { voice_id }
    var voice_id: String
    var name: String
    var labels: [String: String]?
    var description: String?

    var gender: String { (labels?["gender"] ?? "").lowercased() }
    var age: String { (labels?["age"] ?? "").lowercased() }
    /// A voice Braidy designed for a character (named "Braidy · …"). Kept out of automatic casting.
    var isBraidyDesigned: Bool { name.hasPrefix(ElevenClient.designedPrefix) }
    /// "Rachel · female · young · calm"
    var summary: String {
        let extra = [labels?["gender"], labels?["age"], labels?["accent"], labels?["description"] ?? labels?["descriptive"]]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return ([name] + extra).joined(separator: " · ")
    }
}

/// ElevenLabs text-to-speech with the user's own API key.
struct ElevenClient {
    let apiKey: String

    enum Failure: LocalizedError {
        case api(Int, String)
        var errorDescription: String? {
            switch self {
            case .api(let code, let msg): return "ElevenLabs error \(code): \(msg)"
            }
        }
    }

    static let models: [(id: String, label: String)] = [
        ("eleven_flash_v2_5", "Fast (Flash) · half price"),
        ("eleven_v4", "Most expressive (v4)"),
    ]

    private struct VoicePage: Decodable {
        var voices: [ElevenVoice]
        var has_more: Bool?
        var next_page_token: String?
    }

    /// Free check that the key works and can read voices.
    func validate() async throws {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v2/voices?page_size=1&include_total_count=false")!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
    }

    /// All voices the account can use, defaults included.
    func voices() async throws -> [ElevenVoice] {
        var all: [ElevenVoice] = []
        var token: String?
        for _ in 0..<5 {
            var c = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            var q = [URLQueryItem(name: "page_size", value: "100"),
                     URLQueryItem(name: "include_total_count", value: "false")]
            if let token { q.append(URLQueryItem(name: "next_page_token", value: token)) }
            c.queryItems = q
            var req = URLRequest(url: c.url!)
            req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, data)
            let page = try JSONDecoder().decode(VoicePage.self, from: data)
            all += page.voices
            guard page.has_more == true, let next = page.next_page_token else { break }
            token = next
        }
        return all
    }

    /// MP3 of `text` in `voiceID`.
    func speech(_ text: String, voiceID: String, model: String, speed: Double) async throws -> Data {
        var c = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        c.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": model,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "speed": speed],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        return data
    }

    // MARK: Custom voices (Voice Design)

    static let designedPrefix = "Braidy · "

    /// Models that perform bracketed audio tags like "[excited]" (older ones would read them aloud).
    static func takesAudioTags(_ model: String) -> Bool {
        model.hasPrefix("eleven_v3") || model.hasPrefix("eleven_v4")
    }

    struct VoicePreview: Identifiable {
        var id: String { generatedID }
        let generatedID: String
        let audio: Data
    }

    struct VoiceSlots {
        var used: Int
        var limit: Int
        var free: Int { max(0, limit - used) }
    }

    /// How many voices the plan can hold and how many are in use.
    func slots() async throws -> VoiceSlots {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return VoiceSlots(used: json["voice_slots_used"] as? Int ?? 0, limit: json["voice_limit"] as? Int ?? 0)
    }

    /// Three sample voices made from a written description. Nothing is saved to the account yet.
    func designVoice(description: String) async throws -> [VoicePreview] {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-voice/design")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "voice_description": Self.fit(description),
            "model_id": "eleven_multilingual_ttv_v2",
            "auto_generate_text": true,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let previews = json["previews"] as? [[String: Any]] ?? []
        return previews.compactMap { p in
            guard let id = p["generated_voice_id"] as? String,
                  let b64 = p["audio_base_64"] as? String,
                  let audio = Data(base64Encoded: b64) else { return nil }
            return VoicePreview(generatedID: id, audio: audio)
        }
    }

    /// Keep a sample voice in the account. Uses one voice slot. Returns the new voice ID.
    func saveDesignedVoice(name: String, description: String, generatedID: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-voice")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "voice_name": String(name.prefix(80)),
            "voice_description": Self.fit(description),
            "generated_voice_id": generatedID,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let id = json["voice_id"] as? String else { throw Failure.api(0, "No voice ID came back") }
        return id
    }

    /// Delete a voice from the account, freeing its slot.
    func deleteVoice(_ id: String) async throws {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
    }

    /// Voice descriptions must be 20–1000 characters.
    private static func fit(_ d: String) -> String {
        var s = d.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count < 20 { s += " A clear, friendly, expressive character voice." }
        return String(s.prefix(1000))
    }

    /// Plain-English version of an ElevenLabs error, for parents.
    static func friendly(_ error: Error) -> String {
        guard case Failure.api(let code, let msg)? = error as? Failure else { return error.localizedDescription }
        let m = msg.lowercased()
        if code == 401 || code == 403 || m.contains("permission") || m.contains("missing_permissions") {
            return "Your ElevenLabs key needs two more permissions: Voice Generation and Voices (Write). In ElevenLabs › Developers › API Keys, edit the key to turn them on, or make a new key and paste it in Extras."
        }
        if m.contains("voice_limit") || (m.contains("limit") && m.contains("voice")) {
            return "Your ElevenLabs plan has no free voice slots. Remove custom voices from another game, or upgrade the plan for more slots."
        }
        if code == 402 || m.contains("quota") || m.contains("credits") {
            return "Out of ElevenLabs credits for this month."
        }
        return "ElevenLabs: \(msg)"
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["detail"]
            let msg = (detail as? [String: Any])?["message"] as? String
                ?? detail as? String
                ?? String(data: data, encoding: .utf8)?.prefix(200).description
                ?? "Request failed"
            throw Failure.api(code, msg)
        }
    }
}

/// Saved ElevenLabs audio, so a line is only paid for once. Also counts characters sent this month.
final class AudioCache {
    static let shared = AudioCache()
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ElevenLabsAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func key(_ parts: [String]) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Cached audio, or fetch it, save it and count its characters.
    func audio(text: String, voiceID: String, model: String, speed: Double,
               fetch: () async throws -> Data) async throws -> Data {
        let file = dir.appendingPathComponent(key([text, voiceID, model, String(format: "%.2f", speed)]) + ".mp3")
        if let data = try? Data(contentsOf: file) { return data }
        let data = try await fetch()
        try? data.write(to: file, options: .atomic)
        let d = UserDefaults.standard
        let month = Self.monthKey
        d.set(d.integer(forKey: month) + text.count, forKey: month)
        return data
    }

    static var monthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return "elevenChars." + f.string(from: Date())
    }

    var charactersThisMonth: Int { UserDefaults.standard.integer(forKey: Self.monthKey) }

    var bytesOnDisk: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// Chooses an ElevenLabs voice that fits a character.
enum ElevenCasting {
    static func pick(for p: CharacterProfile, voices: [ElevenVoice], narrator: String) -> String? {
        let stock = voices.filter { !$0.isBraidyDesigned }
        guard !stock.isEmpty else { return nil }
        var pool = stock
        if p.gender == "male" || p.gender == "female" {
            let g = pool.filter { $0.gender == p.gender }
            if !g.isEmpty { pool = g }
        }
        let wantAge: [String] = {
            switch p.age {
            case "child": return ["young"]
            case "elder": return ["old"]
            default: return ["middle", "young"]
            }
        }()
        let aged = pool.filter { v in wantAge.contains { v.age.contains($0) } }
        if !aged.isEmpty { pool = aged }
        if pool.count > 1 { pool.removeAll { $0.voice_id == narrator } }
        var h: UInt64 = 5381
        for b in p.key.utf8 { h = (h &* 33) &+ UInt64(b) }
        return pool[Int(h % UInt64(pool.count))].voice_id
    }

    /// A calm, clear default narrator: prefer a voice described as a narrator, else the first.
    static func narrator(from voices: [ElevenVoice]) -> String? {
        let voices = voices.filter { !$0.isBraidyDesigned }
        return voices.first { v in
            let text = (v.labels?.values.joined(separator: " ") ?? "") + " " + (v.description ?? "")
            return text.lowercased().contains("narrat")
        }?.voice_id ?? voices.first?.voice_id
    }
}
