import Foundation
import Security

/// Calls the Claude API with the user's own API key (stored in the Keychain).
///
/// Claude.ai subscriptions can't sign in to third-party apps, so each person who uses Sidekick's
/// character lookups pastes an API key from platform.claude.com, billed per use.
struct ClaudeClient {
    let apiKey: String
    var model = "claude-sonnet-5-5"

    enum Failure: LocalizedError {
        case api(Int, String)
        case noJSON
        var errorDescription: String? {
            switch self {
            case .api(let code, let msg): return "Claude API error \(code): \(msg)"
            case .noJSON: return "Claude's answer didn't include the expected data."
            }
        }
    }

    // MARK: Character lookups

    struct CastReply: Decodable {
        var characters: [Entry]
        var terms: [Term]?
    }

    struct Term: Decodable {
        var word: String
        var say: String?
    }

    struct Entry: Decodable {
        var name: String
        var aliases: [String]?
        var gender: String?
        var species: String?
        var age: String?
        var about: String?
        var say: String?
        var pitch: Double?
        var rate: Double?
    }

    private static let voiceGuide = """
    For each character give: gender ("male", "female", "neutral" or "unknown"), species or race as the game \
    names it, age ("child", "adult" or "elder"), a description of at most 12 words, and voice settings for an \
    iOS text-to-speech voice that suit their species, size, age and personality: pitch from 0.5 (very deep, \
    e.g. a huge rock creature) through 1.0 (typical) to 2.0 (very high, e.g. a tiny sprite), and rate from \
    0.7 (slow, ponderous) to 1.3 (quick, excitable). Keep most characters between 0.8 and 1.3 pitch.
    Also give "say": the name respelled with hyphenated English syllables so a standard text-to-speech voice \
    pronounces it correctly (e.g. "Pikachu" → "Pee-kah-choo"), only when the voice would likely get it wrong; \
    otherwise leave "say" out.
    """

    /// The game's main speaking characters, researched with web search.
    func lookUpCast(game: String) async throws -> CastReply {
        let prompt = """
        I'm building a reader that speaks a video game's dialogue aloud for a young child, using a different \
        voice per character. Search the web as needed and list the main speaking characters in the video game \
        "\(game)" (up to 40), including the names exactly as they appear in dialogue boxes and any alternate \
        names shown in game (aliases). If the game's text is mostly narration or menus with few named speakers \
        (e.g. battle messages), list the characters that do speak.
        \(Self.voiceGuide)
        Also list up to 80 of the game's own words a child will meet in its text (places, items, creatures, \
        moves, abilities, made-up words), each with "say" in the same way, only when a standard voice would \
        mispronounce it.
        Reply with only JSON in this shape, no other text:
        {"characters":[{"name":"","aliases":[],"gender":"","species":"","age":"","about":"","say":"","pitch":1.0,"rate":1.0}],
         "terms":[{"word":"","say":""}]}
        """
        let text = try await send([["type": "text", "text": prompt]], webSearch: true, maxTokens: 12000)
        return try Self.decode(CastReply.self, from: text)
    }

    /// One character whose name appeared in a dialogue box.
    func lookUpCharacter(name: String, game: String) async throws -> Entry {
        let prompt = """
        In the video game "\(game)", a dialogue box shows the speaker name "\(name)" (read by OCR from a camera, \
        so it may have a small typo). Search the web as needed and identify the character. If you can't find \
        them, make a best guess from the name and the game.
        \(Self.voiceGuide)
        Reply with only JSON, no other text:
        {"name":"","aliases":[],"gender":"","species":"","age":"","about":"","say":"","pitch":1.0,"rate":1.0}
        Use the character's correctly spelled name for "name".
        """
        let text = try await send([["type": "text", "text": prompt]], webSearch: true, maxTokens: 2000)
        return try Self.decode(Entry.self, from: text)
    }

    struct GameReply: Decodable { var game: String; var confidence: Double? }

    struct GameMatch: Decodable, Hashable {
        var title: String
        var platform: String?
        var year: String?
        var about: String?

        /// "Switch · 2022 · Open-world monster-catching adventure"
        var detail: String {
            [platform, year, about].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    struct GameList: Decodable { var games: [GameMatch] }

    /// Games matching what someone typed, best match first.
    func searchGames(query: String) async throws -> [GameMatch] {
        let prompt = """
        Someone is choosing which video game their child is playing and typed "\(query)". It may be partial, \
        misspelled, a nickname or a series name. Search the web as needed and list up to 8 video games that best \
        match, most likely first, using each game's full official title. Prefer games on Nintendo Switch and \
        Switch 2, then other consoles, and include recent releases.
        For each give the main platform(s) as a short label (e.g. "Switch 2"), the release year, and what the game is \
        in at most 8 words.
        Reply with only JSON: {"games":[{"title":"","platform":"","year":"","about":""}]}
        """
        let text = try await send([["type": "text", "text": prompt]], webSearch: true, maxTokens: 2000)
        return try Self.decode(GameList.self, from: text).games.filter { !$0.title.isEmpty }
    }

    /// Which game is on the screen in this photo.
    func identifyGame(jpeg: Data) async throws -> GameReply {
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                         "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": """
            This is a camera photo of a TV or handheld screen showing a video game. Which game is it? \
            Use the full official title. Reply with only JSON: {"game":"","confidence":0.0}
            """],
        ]
        let text = try await send(content, webSearch: false, maxTokens: 300)
        return try Self.decode(GameReply.self, from: text)
    }

    // MARK: Messages API

    private func send(_ content: [[String: Any]], webSearch: Bool, maxTokens: Int) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": content]]
        var collected = ""
        // A turn using server tools can pause; continue it a few times if so.
        for _ in 0..<4 {
            var body: [String: Any] = ["model": model, "max_tokens": maxTokens, "messages": messages]
            if webSearch {
                body["tools"] = [["type": "web_search_20260318", "name": "web_search", "max_uses": 5]]
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 180
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard code == 200 else {
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
                throw Failure.api(code, msg)
            }
            let blocks = json["content"] as? [[String: Any]] ?? []
            collected += blocks.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
            guard json["stop_reason"] as? String == "pause_turn" else { break }
            messages.append(["role": "assistant", "content": blocks])
        }
        return collected
    }

    /// Pull the JSON object out of Claude's reply and decode it.
    private static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { throw Failure.noJSON }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Minimal Keychain storage for the API key.
enum Keychain {
    private static let service = "com.samuelling.sidekick.claude"

    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
