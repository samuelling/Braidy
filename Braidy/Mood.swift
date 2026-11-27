import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// How a line should be performed. ElevenLabs' expressive model takes it as an audio tag ("[sad] …");
/// device voices get a small pitch and speed nudge.
enum Mood: String, CaseIterable {
    case neutral, happy, excited, sad, angry, scared, worried, curious, surprised, playful, tired, proud
    case whispering, shouting

    /// The ElevenLabs audio tag, or nil to let the voice read it plainly.
    var elevenTag: String? {
        switch self {
        case .neutral: return nil
        case .whispering: return "whispers"
        case .shouting: return "shouts"
        case .playful: return "mischievously"
        case .worried: return "nervous"
        default: return rawValue
        }
    }

    /// Pitch and speed multipliers for device voices. Kept small: big shifts sound robotic.
    var pitch: Float {
        switch self {
        case .excited, .happy, .surprised, .playful: return 1.07
        case .scared, .worried: return 1.04
        case .sad, .tired: return 0.94
        case .angry, .shouting, .proud: return 0.97
        default: return 1
        }
    }

    var rate: Float {
        switch self {
        case .excited, .scared, .shouting, .angry: return 1.08
        case .sad, .tired, .whispering: return 0.88
        case .worried, .curious: return 0.96
        default: return 1
        }
    }
}

/// Picks a line's mood from its words and the lines just before it.
///
/// Uses Apple's on-device language model when the iPad has Apple Intelligence, so the dialogue
/// never leaves the device. Otherwise (or if the model is slow), simple rules from punctuation
/// and a few telling words.
enum MoodReader {
    /// True when the on-device model can be used.
    static var onDevice: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func mood(for line: String, speaker: String?, about: String?, context: [String], game: String) async -> Mood {
        let quick = rules(line)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), onDevice {
            var prompt = game.isEmpty ? "" : "Game: \(game)\n"
            if !context.isEmpty { prompt += "Just before:\n" + context.joined(separator: "\n") + "\n" }
            if let speaker { prompt += "Speaker: \(speaker)" + ((about ?? "").isEmpty ? "" : " (\(about!))") + "\n" }
            prompt += "Line to perform: \(line)"
            // Don't hold the line up for long: past ~1.2 s, the rules decide.
            if let picked = await withTimeout(1.2, { await ask(prompt) }) { return picked }
        }
        #endif
        return quick
    }

    /// Punctuation and word rules, used when the on-device model isn't there.
    static func rules(_ line: String) -> Mood {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = t.filter(\.isLetter)
        let lower = t.lowercased()
        func has(_ words: [String]) -> Bool {
            words.contains { w in lower.range(of: "\\b\(w)\\b", options: .regularExpression) != nil }
        }
        if letters.count >= 6, Double(letters.filter(\.isUppercase).count) / Double(letters.count) > 0.7 { return .shouting }
        if has(["shh", "psst", "whisper", "quietly"]) { return .whispering }
        if has(["help", "run", "scared", "afraid", "monster", "eek", "aah+"]) && t.contains("!") { return .scared }
        if has(["sorry", "sad", "miss you", "goodbye", "cry", "alone", "lost", "gone"]) { return .sad }
        if has(["hmph", "grr+", "how dare", "you fool", "enough"]) { return .angry }
        if has(["sigh", "yawn", "tired", "sleepy", "zzz+"]) { return .tired }
        if has(["hee", "hehe+", "teehee", "heh"]) { return .playful }
        if t.contains("!!") || has(["wow", "yay", "hooray", "amazing", "awesome", "woo+", "yahoo"]) { return .excited }
        if t.hasPrefix("...") || t.hasPrefix("…") || t.components(separatedBy: "...").count > 2 { return .worried }
        if has(["what", "huh", "whoa", "oh"]) && (t.contains("?!") || t.contains("!?")) { return .surprised }
        if t.hasSuffix("?") { return .curious }
        if t.hasSuffix("!") { return .happy }
        return .neutral
    }

    private static func withTimeout(_ seconds: Double, _ work: @escaping @Sendable () async -> Mood?) async -> Mood? {
        await withTaskGroup(of: Mood?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func ask(_ prompt: String) async -> Mood? {
        let session = LanguageModelSession(instructions: """
        You direct voice actors for an app that reads a video game's text aloud to a young child. \
        Given one line of game dialogue and the lines just before it, pick the single emotion the line \
        should be performed with. Choose neutral for plain information, menus, tutorials and item text.
        """)
        do {
            let reply = try await session.respond(to: prompt, generating: MoodPick.self)
            return Mood(rawValue: reply.content.mood.lowercased())
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct MoodPick {
    @Guide(description: "How the line should sound", .anyOf(Mood.allCases.map(\.rawValue)))
    var mood: String
}
#endif
