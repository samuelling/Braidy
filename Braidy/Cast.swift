import AVFoundation
import Foundation

/// One character and how they should sound.
struct CharacterProfile: Codable, Identifiable, Hashable {
    var id: String { key }
    /// Normalized name, unique within a game.
    var key: String
    var name: String
    var aliases: [String] = []
    /// How to spell the name so the speech voice says it right (e.g. "Pee-kah-choo"), if needed.
    var say: String?
    /// "male", "female", "neutral" or "unknown".
    var gender: String = "unknown"
    var species: String = ""
    /// "child", "adult" or "elder".
    var age: String = "adult"
    var about: String = ""
    /// Speech pitch, 0.5–2.0.
    var pitch: Double = 1.0
    /// Speed multiplier, 0.6–1.5.
    var rate: Double = 1.0
    var voiceID: String = ""
    /// ElevenLabs voice, when that engine is on.
    var elevenVoiceID: String?
    /// How this character should sound, written by Claude, for designing a custom ElevenLabs voice.
    var voiceDescription: String?
    /// "star", "major" or "minor": how big a part they have in the game.
    var role: String?
    /// A voice Braidy designed for this character in the user's ElevenLabs account.
    var designedVoiceID: String?
    /// True once someone picks this character's voice by hand, so Claude won't change it.
    var voiceLocked: Bool = false
    /// "claude", "seen" or "manual".
    var source: String = "seen"

    init(name: String) {
        self.name = name
        self.key = DialogueTracker.normalize(name)
    }

    var summary: String {
        var parts: [String] = []
        if !species.isEmpty { parts.append(species) }
        if gender != "unknown" { parts.append(gender) }
        if age != "adult" { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

/// Per-game cast lists, saved on the device.
final class CastStore: ObservableObject {
    /// game key → character key → profile
    @Published private(set) var games: [String: [String: CharacterProfile]] = [:]
    /// game key → the game's own words (places, items, creatures, moves) and how to say them.
    @Published private(set) var vocabulary: [String: [GameTerm]] = [:]

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cast.json")
    }()
    private var vocabURL: URL { url.deletingLastPathComponent().appendingPathComponent("vocabulary.json") }

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: [String: CharacterProfile]].self, from: data) {
            games = saved
        }
        if let data = try? Data(contentsOf: vocabURL),
           let saved = try? JSONDecoder().decode([String: [GameTerm]].self, from: data) {
            vocabulary = saved
        }
    }

    func terms(for game: String) -> [GameTerm] { vocabulary[Self.gameKey(game)] ?? [] }

    func setTerms(_ terms: [GameTerm], game: String) {
        vocabulary[Self.gameKey(game)] = terms
        if let data = try? JSONEncoder().encode(vocabulary) { try? data.write(to: vocabURL, options: .atomic) }
    }

    /// Respellings for the speech voice: game words, then character names.
    func pronunciations(for game: String) -> [String: String] {
        var map: [String: String] = [:]
        for t in terms(for: game) { if let say = t.say, !say.isEmpty { map[t.word] = say } }
        for p in cast(for: game) { if let say = p.say, !say.isEmpty { map[p.name] = say } }
        return map
    }

    static func gameKey(_ game: String) -> String { DialogueTracker.normalize(game) }

    func cast(for game: String) -> [CharacterProfile] {
        (games[Self.gameKey(game)] ?? [:]).values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func names(for game: String) -> [String] {
        cast(for: game).flatMap { [$0.name] + $0.aliases }
    }

    /// The character whose name or alias matches what was read off the screen.
    func match(_ name: String, game: String) -> CharacterProfile? {
        let n = DialogueTracker.normalize(name)
        guard !n.isEmpty else { return nil }
        let all = games[Self.gameKey(game)] ?? [:]
        if let exact = all[n] { return exact }
        var best: (CharacterProfile, Double)?
        for p in all.values {
            for candidate in [p.name] + p.aliases {
                let s = DialogueTracker.similarity(n, DialogueTracker.normalize(candidate))
                if s >= 0.8, s > (best?.1 ?? 0) { best = (p, s) }
            }
        }
        return best?.0
    }

    func upsert(_ p: CharacterProfile, game: String) {
        let g = Self.gameKey(game)
        var cast = games[g] ?? [:]
        cast[p.key] = p
        games[g] = cast
        save()
    }

    func remove(_ p: CharacterProfile, game: String) {
        let g = Self.gameKey(game)
        games[g]?[p.key] = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(games) { try? data.write(to: url, options: .atomic) }
    }
}

/// A word from a game's own vocabulary.
struct GameTerm: Codable, Hashable {
    var word: String
    var say: String?
}

/// Chooses an installed voice that fits a character.
enum VoiceCasting {
    /// Pick a voice matching the character's gender, spreading characters across the voices
    /// available (stable per name) and avoiding the narrator's voice when there's a choice.
    static func pick(for p: CharacterProfile, voices: [AVSpeechSynthesisVoice], narrator: String) -> String {
        let wanted: AVSpeechSynthesisVoiceGender? = {
            switch p.gender {
            case "male": return .male
            case "female": return .female
            default: return nil
            }
        }()
        var pool = voices.filter { wanted == nil || $0.gender == wanted }
        if pool.isEmpty { pool = voices }
        // Prefer the best quality tier that has any voices in the pool.
        if let top = pool.map(\.quality.rawValue).max() {
            let best = pool.filter { $0.quality.rawValue == top }
            if best.count >= 2 || pool.count == best.count { pool = best }
        }
        if pool.count > 1 { pool.removeAll { $0.identifier == narrator } }
        guard !pool.isEmpty else { return narrator }
        return pool[Int(stableHash(p.key) % UInt64(pool.count))].identifier
    }

    /// Defaults when Claude hasn't weighed in: children higher, elders slower.
    static func defaultStyle(_ p: inout CharacterProfile) {
        switch p.age {
        case "child": p.pitch = 1.35; p.rate = 1.05
        case "elder": p.pitch = 0.9; p.rate = 0.85
        default: break
        }
    }

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }
}
