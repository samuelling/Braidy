import AVFoundation
import SwiftUI

/// Ties the camera, the dialogue tracker, the cast and speech together.
final class Reader: ObservableObject {
    let camera = CameraModel()
    let cast = CastStore()
    let listener = VoiceListener()
    private let speaker = Speaker()
    private var tracker = DialogueTracker()
    private let defaults = UserDefaults.standard
    private let audioQueue = DispatchQueue(label: "navi.audio-session")

    static let defaultRegion = CGRect(x: 0.06, y: 0.55, width: 0.88, height: 0.4)
    static let suggestedGames = [
        "The Legend of Zelda: Tears of the Kingdom",
        "The Legend of Zelda: Breath of the Wild",
        "The Legend of Zelda: Echoes of Wisdom",
        "The Legend of Zelda: Link's Awakening",
        "The Legend of Zelda: Skyward Sword HD",
        "Pokémon Scarlet and Violet",
        "Pokémon Legends: Z-A",
        "Super Mario Odyssey",
        "Animal Crossing: New Horizons",
    ]

    let voices: [AVSpeechSynthesisVoice]

    @Published var lastLine = ""
    @Published var lastSpeaker: String?
    /// The last line was voiced by the game itself, so Navi stayed quiet.
    @Published var lastLineWasVoiced = false
    @Published var isSpeaking = false
    @Published var status: String?
    @Published var lookingUp = false

    @Published var listening = true {
        didSet {
            camera.setListening(listening)
            if !listening {
                pendingLine?.cancel()
                speaker.stop()
            }
        }
    }
    @Published var region: CGRect {
        didSet {
            camera.setRegion(region)
            defaults.set([region.minX, region.minY, region.width, region.height], forKey: "region")
        }
    }
    @Published var rate: Double {
        didSet { speaker.baseRate = Float(rate); defaults.set(rate, forKey: "rate") }
    }
    /// Voice for lines with no speaker label.
    @Published var narratorVoice: String {
        didSet { defaults.set(narratorVoice, forKey: "voice") }
    }
    @Published var zoom: Double {
        didSet { camera.zoom = CGFloat(zoom); defaults.set(zoom, forKey: "zoom") }
    }
    @Published var game: String {
        didSet {
            defaults.set(game, forKey: "game")
            updateCustomWords()
        }
    }
    @Published var characterVoices: Bool {
        didSet { defaults.set(characterVoices, forKey: "characterVoices") }
    }
    @Published var sayNames: Bool {
        didSet { defaults.set(sayNames, forKey: "sayNames") }
    }
    /// Listen for the game's own voice acting and don't talk over it.
    @Published var quietWhenGameTalks: Bool {
        didSet {
            defaults.set(quietWhenGameTalks, forKey: "quietWhenGameTalks")
            applyListening()
        }
    }
    /// How sure the sound classifier must be that it hears speech (0.3–0.9).
    @Published var voiceSensitivity: Double {
        didSet {
            listener.threshold = voiceSensitivity
            defaults.set(voiceSensitivity, forKey: "voiceSensitivity")
        }
    }
    @Published var apiKey: String {
        didSet { Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// The speaker label in the most recent frame.
    private var frameSpeaker: String?
    private var pendingLookups: Set<String> = []
    /// A settled line waiting to see whether the game is voicing it.
    private var pendingLine: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        if let a = d.array(forKey: "region") as? [Double], a.count == 4 {
            region = CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
        } else {
            region = Self.defaultRegion
        }
        rate = d.object(forKey: "rate") as? Double ?? 0.42
        let vs = Speaker.englishVoices()
        voices = vs
        narratorVoice = d.string(forKey: "voice") ?? (vs.first?.identifier ?? "")
        zoom = d.object(forKey: "zoom") as? Double ?? 1
        game = d.string(forKey: "game") ?? ""
        characterVoices = d.object(forKey: "characterVoices") as? Bool ?? true
        sayNames = d.object(forKey: "sayNames") as? Bool ?? false
        quietWhenGameTalks = d.object(forKey: "quietWhenGameTalks") as? Bool ?? true
        voiceSensitivity = d.object(forKey: "voiceSensitivity") as? Double ?? 0.5
        apiKey = Keychain.load()

        camera.setRegion(region)
        camera.zoom = CGFloat(zoom)
        speaker.baseRate = Float(rate)
        listener.threshold = voiceSensitivity
        speaker.onSpeaking = { [weak self] s in
            self?.isSpeaking = s
            self?.listener.setSelfSpeaking(s)
        }
        camera.onFrame = { [weak self] rows in self?.handle(rows) }
        updateCustomWords()
    }

    func start() {
        camera.start()
        applyListening()
    }

    /// Playback-only when not listening; play-and-record (still out of the speaker, mixing with
    /// other audio) when listening for the game's voice. Speech plays even with the silent switch on.
    private func applyListening() {
        listener.stop()
        let listen = quietWhenGameTalks
        // Activating the audio session can block, so keep it off the main thread.
        audioQueue.async { [weak self] in
            let session = AVAudioSession.sharedInstance()
            if listen {
                try? session.setCategory(.playAndRecord, mode: .default,
                                         options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            } else {
                try? session.setCategory(.playback, mode: .spokenAudio, options: [])
            }
            try? session.setActive(true)
            DispatchQueue.main.async {
                guard let self, self.quietWhenGameTalks == listen, listen else { return }
                self.listener.start()
            }
        }
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var client: ClaudeClient { ClaudeClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }

    // MARK: Reading

    private func handle(_ rows: [TextRow]) {
        guard listening else { return }
        let names = characterVoices ? cast.names(for: game) : []
        let parsed: (speaker: String?, body: String) = characterVoices ? SpeakerParser.split(rows, knownNames: names)
                                     : (speaker: nil, body: rows.map(\.text).joined(separator: " "))
        if !parsed.body.isEmpty { frameSpeaker = parsed.speaker }
        if let line = tracker.ingest(parsed.body) {
            deliver(line, from: frameSpeaker)
        }
    }

    /// Speak a settled line, unless the game is voicing it.
    ///
    /// Subtitles and the actor's voice start together, but the sound classifier needs a moment to
    /// be sure it hears speech. So a settled line waits ~0.7 s, then Navi checks whether the game
    /// spoke from 1.5 s before the line settled until now. If it did, the line is shown but not read.
    private func deliver(_ line: String, from name: String?) {
        pendingLine?.cancel()
        guard quietWhenGameTalks, listener.isRunning else {
            say(line, from: name)
            return
        }
        let settled = Date()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLine = nil
            if self.listener.gameTalked(since: settled.addingTimeInterval(-1.5)) {
                self.show(line, from: name)
            } else {
                self.say(line, from: name)
            }
        }
        pendingLine = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// The game voiced this line: put it on screen (Repeat still reads it) but stay quiet.
    private func show(_ line: String, from name: String?) {
        let profile = name.flatMap { profileFor(speakerName: $0) }
        lastLine = line
        lastSpeaker = profile?.name ?? name
        lastLineWasVoiced = true
    }

    private func say(_ line: String, from name: String?) {
        let profile = name.flatMap { profileFor(speakerName: $0) }
        lastLine = line
        lastSpeaker = profile?.name ?? name
        lastLineWasVoiced = false
        var text = line
        if sayNames, let who = lastSpeaker { text = "\(who): \(line)" }
        speaker.speak(text, style: style(for: profile))
    }

    func repeatLast() {
        guard !lastLine.isEmpty else { return }
        let profile = lastSpeaker.flatMap { cast.match($0, game: game) }
        var text = lastLine
        if sayNames, let who = lastSpeaker { text = "\(who): \(lastLine)" }
        speaker.speak(text, style: style(for: profile))
    }

    /// Read whatever is in the box right now, even if it was already read.
    func readNow() {
        let rows = camera.rows
        let parsed: (speaker: String?, body: String) = characterVoices ? SpeakerParser.split(rows, knownNames: cast.names(for: game))
                                     : (speaker: nil, body: rows.map(\.text).joined(separator: " "))
        guard !parsed.body.isEmpty else { status = "No text in the reading box"; return }
        pendingLine?.cancel()
        tracker.markSpoken(parsed.body)
        say(parsed.body, from: parsed.speaker)
    }

    func test(_ profile: CharacterProfile? = nil) {
        let line = profile.map { "Hi, I'm \($0.name)!" } ?? "Hey! Listen! I'll read the words on the screen."
        speaker.speak(line, style: style(for: profile))
    }

    func style(for p: CharacterProfile?) -> VoiceStyle {
        guard characterVoices, let p else { return VoiceStyle(voiceID: narratorVoice) }
        return VoiceStyle(voiceID: p.voiceID.isEmpty ? narratorVoice : p.voiceID,
                          pitch: Float(p.pitch), rate: Float(p.rate))
    }

    // MARK: Cast

    /// Find or create the profile for a name read off the screen, asking Claude about newcomers.
    private func profileFor(speakerName name: String) -> CharacterProfile? {
        if let known = cast.match(name, game: game) { return known }
        var p = CharacterProfile(name: name)
        p.voiceID = VoiceCasting.pick(for: p, voices: voices, narrator: narratorVoice)
        cast.upsert(p, game: game)
        if hasKey, !game.isEmpty { lookUp(character: p) }
        return p
    }

    func lookUp(character p: CharacterProfile) {
        guard hasKey, !game.isEmpty, !pendingLookups.contains(p.key) else { return }
        pendingLookups.insert(p.key)
        let client = self.client, game = self.game
        Task { @MainActor [weak self] in
            defer { self?.pendingLookups.remove(p.key) }
            do {
                let entry = try await client.lookUpCharacter(name: p.name, game: game)
                self?.apply(entry, to: p, game: game)
            } catch {
                self?.status = error.localizedDescription
            }
        }
    }

    /// Ask Claude for the game's whole cast and give each character a voice.
    func lookUpCast() {
        guard hasKey else { status = "Add a Claude API key first"; return }
        guard !game.isEmpty else { status = "Choose the game first"; return }
        lookingUp = true
        status = "Asking Claude about the characters in \(game)…"
        let client = self.client, game = self.game
        Task { @MainActor [weak self] in
            do {
                let entries = try await client.lookUpCast(game: game)
                guard let self else { return }
                for e in entries {
                    let existing = self.cast.match(e.name, game: game) ?? CharacterProfile(name: e.name)
                    self.apply(e, to: existing, game: game)
                }
                self.status = "Found \(entries.count) characters"
            } catch {
                self?.status = error.localizedDescription
            }
            self?.lookingUp = false
        }
    }

    private func apply(_ e: ClaudeClient.Entry, to old: CharacterProfile, game: String) {
        var p = old
        // Keep the key the screen produced so future matches still land here.
        p.name = e.name.isEmpty ? old.name : e.name
        var aliases = Set((e.aliases ?? []) + old.aliases)
        if DialogueTracker.normalize(p.name) != old.key { aliases.insert(old.name) }
        aliases.remove(p.name)
        p.aliases = aliases.sorted()
        p.gender = (e.gender ?? p.gender).lowercased()
        p.species = e.species ?? p.species
        p.age = (e.age ?? p.age).lowercased()
        p.about = e.about ?? p.about
        if !p.voiceLocked {
            if let pitch = e.pitch { p.pitch = min(max(pitch, 0.5), 2.0) } else { VoiceCasting.defaultStyle(&p) }
            if let rate = e.rate { p.rate = min(max(rate, 0.6), 1.5) }
            p.voiceID = VoiceCasting.pick(for: p, voices: voices, narrator: narratorVoice)
        }
        p.source = "claude"
        cast.upsert(p, game: game)
        updateCustomWords()
    }

    /// Ask Claude which game is on screen, then look up its cast.
    func identifyGame() {
        guard hasKey else { status = "Add a Claude API key first"; return }
        status = "Looking at the screen…"
        lookingUp = true
        camera.snapshot { [weak self] jpeg in
            guard let self else { return }
            guard let jpeg else { self.status = "Couldn't grab a camera frame"; self.lookingUp = false; return }
            let client = self.client
            Task { @MainActor [weak self] in
                do {
                    let reply = try await client.identifyGame(jpeg: jpeg)
                    guard let self else { return }
                    if reply.game.isEmpty || (reply.confidence ?? 1) < 0.4 {
                        self.status = "Claude wasn't sure which game this is. Type it in instead."
                        self.lookingUp = false
                    } else {
                        self.game = reply.game
                        self.lookUpCast()
                    }
                } catch {
                    self?.status = error.localizedDescription
                    self?.lookingUp = false
                }
            }
        }
    }

    private func updateCustomWords() {
        let names = cast.names(for: game).flatMap { $0.split(separator: " ").map(String.init) }
        camera.customWords = Array(Set(CameraModel.gameWords + names))
    }
}
