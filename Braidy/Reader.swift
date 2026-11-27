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
    private let audioQueue = DispatchQueue(label: "braidy.audio-session")

    static let defaultRegion = CGRect(x: 0.06, y: 0.55, width: 0.88, height: 0.4)
    static let suggestedGames = [
        "Pokémon Scarlet and Violet",
        "Pokémon Legends: Z-A",
        "Pokémon: Let's Go, Pikachu! and Let's Go, Eevee!",
        "Super Mario Bros. Wonder",
        "Super Mario Odyssey",
        "Paper Mario: The Thousand-Year Door",
        "Kirby and the Forgotten Land",
        "Animal Crossing: New Horizons",
        "Donkey Kong Bananza",
        "Luigi's Mansion 3",
        "Minecraft",
        "Splatoon 3",
        "The Legend of Zelda: Tears of the Kingdom",
        "The Legend of Zelda: Breath of the Wild",
        "The Legend of Zelda: Echoes of Wisdom",
        "The Legend of Zelda: Link's Awakening",
    ]

    /// Installed English voices, best first (refreshes when the user downloads more).
    @Published private(set) var voices: [AVSpeechSynthesisVoice]
    /// Enhanced or Premium voices installed (the natural-sounding ones).
    var goodVoiceCount: Int { voices.filter { $0.quality != .default }.count }

    /// The console or device the game is on, chosen before searching.
    @Published var platform: String {
        didSet { defaults.set(platform, forKey: "platform") }
    }
    static let platforms: [(name: String, short: String, icon: String)] = [
        ("Nintendo Switch 2", "Switch 2", "gamecontroller.fill"),
        ("Nintendo Switch", "Switch", "gamecontroller"),
        ("PlayStation 5", "PS5", "playstation.logo"),
        ("Xbox Series X|S", "Xbox", "xbox.logo"),
        ("PC", "PC", "desktopcomputer"),
        ("iPad or iPhone", "iPad", "ipad"),
        ("Something else", "", "questionmark.circle"),
    ]
    /// Claude's popular-games list per platform, fetched once per launch.
    private var popularCache: [String: [ClaudeClient.GameMatch]] = [:]
    private var voiceObserver: NSObjectProtocol?

    @Published var lastLine = ""
    @Published var lastSpeaker: String?
    /// The last line was voiced by the game itself, so Braidy stayed quiet.
    @Published var lastLineWasVoiced = false
    @Published var isSpeaking = false
    @Published var status: String?
    @Published var lookingUp = false

    @Published var listening = true {
        didSet {
            camera.setListening(listening)
            if !listening {
                pendingLine?.cancel()
                moodTask?.cancel()
                speaker.stop()
            }
        }
    }
    @Published var region: CGRect {
        didSet {
            camera.setRegion(region)
            let saved = [region.minX, region.minY, region.width, region.height]
            defaults.set(saved, forKey: "region")
            // Each game puts its text somewhere different, so remember the box per game.
            if !game.isEmpty { defaults.set(saved, forKey: Self.regionKey(game)) }
        }
    }
    /// Parts of the screen whose text is never read (score, timers, button hints), per game.
    @Published var ignoreZones: [CGRect] {
        didSet {
            camera.setIgnoreZones(ignoreZones)
            defaults.set(ignoreZones.map { [$0.minX, $0.minY, $0.width, $0.height] },
                         forKey: Self.ignoreKey(game))
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
            if !game.isEmpty {
                var recent = recentGames.filter { $0.caseInsensitiveCompare(game) != .orderedSame }
                recent.insert(game, at: 0)
                recentGames = Array(recent.prefix(12))
                defaults.set(recentGames, forKey: "recentGames")
            }
            if let r = Self.savedRegion(defaults, key: Self.regionKey(game)), r != region { region = r }
            let zones = Self.savedZones(defaults, key: Self.ignoreKey(game))
            if zones != ignoreZones { ignoreZones = zones }
            refreshGameListening()
            updateCustomWords()
        }
    }
    /// Platform · year · description for the current game, when Claude matched it.
    @Published var gameDetail: String {
        didSet { defaults.set(gameDetail, forKey: "gameDetail") }
    }
    /// Games picked before, most recent first.
    @Published var recentGames: [String]
    @Published var characterVoices: Bool {
        didSet { defaults.set(characterVoices, forKey: "characterVoices") }
    }
    @Published var sayNames: Bool {
        didSet { defaults.set(sayNames, forKey: "sayNames") }
    }
    /// Expressive voices: each line is performed with an emotion picked from its words and the lines
    /// before it (on this iPad), as an ElevenLabs audio tag or a small pitch/speed change.
    @Published var expressive: Bool {
        didSet { defaults.set(expressive, forKey: "expressive") }
    }
    /// The mood of the last line, shown in the dialogue box and reused by AGAIN.
    @Published private(set) var lastMood: Mood?
    private var recentLines: [String] = []
    private var moodTask: Task<Void, Never>?
    /// Silly mode: Bubble Buddy calls the player "brodie" now and then.
    @Published var brodie: Bool {
        didSet { defaults.set(brodie, forKey: "brodie") }
    }
    /// Listen for the game's own voice acting and don't talk over it.
    @Published var quietWhenGameTalks: Bool {
        didSet {
            defaults.set(quietWhenGameTalks, forKey: "quietWhenGameTalks")
            applyListening()
        }
    }
    /// How much of the current game is voiced, from Claude: "none", "some", "full", or nil if unknown.
    @Published private(set) var gameVoiced: String?
    /// Whether to listen for voice acting in the current game. A text-only game turns the mic off,
    /// so talk in the room can't make Braidy skip lines. A parent can override it per game.
    @Published private(set) var listenThisGame = true
    /// True when Braidy is actually listening for the game's voice.
    var listensForVoices: Bool { quietWhenGameTalks && listenThisGame }

    static func voicedKey(_ game: String) -> String { "voiced." + CastStore.gameKey(game) }
    static func listenKey(_ game: String) -> String { "listen." + CastStore.gameKey(game) }

    /// A parent's choice for this game, or nil to follow what Claude found.
    var listenOverride: Bool? { defaults.object(forKey: Self.listenKey(game)) as? Bool }

    func setListenThisGame(_ on: Bool?) {
        if let on { defaults.set(on, forKey: Self.listenKey(game)) } else { defaults.removeObject(forKey: Self.listenKey(game)) }
        refreshGameListening()
    }

    /// Remember Claude's answer about voice acting for a game.
    func noteVoiced(_ voiced: String?, game title: String) {
        guard let v = voiced?.lowercased(), ["none", "some", "full"].contains(v), !title.isEmpty else { return }
        defaults.set(v, forKey: Self.voicedKey(title))
        if title == game { refreshGameListening() }
    }

    private func refreshGameListening() {
        gameVoiced = game.isEmpty ? nil : defaults.string(forKey: Self.voicedKey(game))
        let on = listenOverride ?? (gameVoiced != "none")
        if on != listenThisGame {
            listenThisGame = on
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
    // MARK: ElevenLabs

    /// "apple" (free, on-device) or "eleven" (ElevenLabs, natural character voices).
    @Published var voiceEngine: String {
        didSet { defaults.set(voiceEngine, forKey: "voiceEngine"); configureEleven() }
    }
    @Published var elevenKey: String {
        didSet {
            Keychain.save(elevenKey.trimmingCharacters(in: .whitespacesAndNewlines), service: Keychain.elevenLabs)
            configureEleven()
            loadElevenVoices()
        }
    }
    @Published var elevenModel: String {
        didSet { defaults.set(elevenModel, forKey: "elevenModel"); speaker.elevenModel = elevenModel }
    }
    @Published var elevenNarrator: String {
        didSet { defaults.set(elevenNarrator, forKey: "elevenNarrator") }
    }
    @Published private(set) var elevenVoices: [ElevenVoice] = []
    @Published private(set) var loadingElevenVoices = false
    /// True while Braidy designs custom voices for the main characters.
    @Published private(set) var designingVoices = false
    /// The ElevenLabs plan's voice slots, once known.
    @Published private(set) var voiceSlots: ElevenClient.VoiceSlots?
    var hasElevenKey: Bool { !elevenKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var usingEleven: Bool { voiceEngine == "eleven" && hasElevenKey }
    private var lastElevenError = Date.distantPast

    @Published var apiKey: String {
        didSet { Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// The speaker label in the most recent frame.
    private var pendingLookups: Set<String> = []
    /// A settled line waiting to see whether the game is voicing it.
    private var pendingLine: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        let savedGame = d.string(forKey: "game") ?? ""
        region = Self.savedRegion(d, key: Self.regionKey(savedGame))
            ?? Self.savedRegion(d, key: "region") ?? Self.defaultRegion
        ignoreZones = Self.savedZones(d, key: Self.ignoreKey(savedGame))
        rate = d.object(forKey: "rate") as? Double ?? 0.42
        let vs = Speaker.englishVoices()
        voices = vs
        narratorVoice = d.string(forKey: "voice") ?? (vs.first?.identifier ?? "")
        zoom = d.object(forKey: "zoom") as? Double ?? 1
        game = savedGame
        gameDetail = d.string(forKey: "gameDetail") ?? ""
        platform = d.string(forKey: "platform") ?? "Nintendo Switch 2"
        recentGames = d.stringArray(forKey: "recentGames") ?? (savedGame.isEmpty ? [] : [savedGame])
        characterVoices = d.object(forKey: "characterVoices") as? Bool ?? true
        sayNames = d.object(forKey: "sayNames") as? Bool ?? false
        brodie = d.object(forKey: "brodie") as? Bool ?? false
        expressive = d.object(forKey: "expressive") as? Bool ?? true
        quietWhenGameTalks = d.object(forKey: "quietWhenGameTalks") as? Bool ?? true
        voiceSensitivity = d.object(forKey: "voiceSensitivity") as? Double ?? 0.5
        apiKey = Keychain.load()
        voiceEngine = d.string(forKey: "voiceEngine") ?? "apple"
        elevenKey = Keychain.load(Keychain.elevenLabs)
        elevenModel = d.string(forKey: "elevenModel") ?? ElevenClient.models[0].id
        elevenNarrator = d.string(forKey: "elevenNarrator") ?? ""
        if let data = d.data(forKey: "elevenVoices"),
           let saved = try? JSONDecoder().decode([ElevenVoice].self, from: data) {
            elevenVoices = saved
        }

        gameVoiced = savedGame.isEmpty ? nil : d.string(forKey: Self.voicedKey(savedGame))
        listenThisGame = (d.object(forKey: Self.listenKey(savedGame)) as? Bool) ?? (gameVoiced != "none")
        camera.setRegion(region)
        camera.setIgnoreZones(ignoreZones)
        camera.zoom = CGFloat(zoom)
        speaker.baseRate = Float(rate)
        speaker.elevenModel = elevenModel
        speaker.onError = { [weak self] msg in
            guard let self else { return }
            // Don't flood the screen if every line fails (e.g. out of characters).
            if Date().timeIntervalSince(self.lastElevenError) > 20 {
                self.status = msg + " Using the iPad's voice for now."
                self.lastElevenError = Date()
            }
        }
        configureEleven()
        listener.threshold = voiceSensitivity
        speaker.onSpeaking = { [weak self] s in
            self?.isSpeaking = s
            self?.listener.setSelfSpeaking(s)
        }
        camera.onFrame = { [weak self] rows in self?.handle(rows) }
        voiceObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.voices = Speaker.englishVoices() }
        updateCustomWords()
    }

    static func regionKey(_ game: String) -> String { "region." + CastStore.gameKey(game) }
    static func ignoreKey(_ game: String) -> String { "ignore." + CastStore.gameKey(game) }

    static func savedZones(_ d: UserDefaults, key: String) -> [CGRect] {
        guard let list = d.array(forKey: key) as? [[Double]] else { return [] }
        return list.compactMap { a in a.count == 4 ? CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) : nil }
    }

    /// Add an ignore zone: around some text (with a little margin), or a new box in the reading box.
    func addIgnoreZone(around box: CGRect? = nil) {
        let z: CGRect
        if let box {
            z = box.insetBy(dx: -0.012, dy: -0.012).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        } else {
            let w = min(0.3, region.width * 0.5), h = min(0.12, region.height * 0.5)
            z = CGRect(x: region.midX - w / 2, y: region.midY - h / 2, width: w, height: h)
        }
        ignoreZones.append(z)
    }

    static func savedRegion(_ d: UserDefaults, key: String) -> CGRect? {
        guard let a = d.array(forKey: key) as? [Double], a.count == 4 else { return nil }
        return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
    }

    func start() {
        camera.start()
        applyListening()
        if hasElevenKey && elevenVoices.isEmpty { loadElevenVoices() }
    }

    /// Playback-only when not listening; play-and-record (still out of the speaker, mixing with
    /// other audio) when listening for the game's voice. Speech plays even with the silent switch on.
    private func applyListening() {
        listener.stop()
        let listen = listensForVoices
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
                guard let self, self.listensForVoices == listen, listen else { return }
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
                                     : (speaker: nil, body: TextRow.joined(rows))
        if !parsed.body.isEmpty { vote(parsed.speaker, body: parsed.body) }
        if let line = tracker.ingest(parsed.body) {
            deliver(line, from: electedSpeaker())
        }
    }

    // A name label is often misread on a frame or two (or missed while the box animates in), and
    // one bad frame used to decide the voice. So every frame of a line votes, and the line goes to
    // the name seen most. A new line (text unlike the last frame's) starts a fresh vote, so the
    // previous speaker's votes never carry over in a back-and-forth.
    private var speakerVotes: [String: Int] = [:]
    private var unlabeledFrames = 0
    private var lastFrameBody = ""

    private func vote(_ speaker: String?, body: String) {
        let a = DialogueTracker.normalize(body), b = DialogueTracker.normalize(lastFrameBody)
        let continues = !b.isEmpty && (a.hasPrefix(String(b.prefix(12))) || DialogueTracker.similarity(a, b) >= 0.6)
        if !continues {
            speakerVotes = [:]
            unlabeledFrames = 0
        }
        lastFrameBody = body
        if let speaker {
            // Count misreads of a known character as that character.
            let name = cast.match(speaker, game: game)?.name ?? speaker
            speakerVotes[name, default: 0] += 1
        } else {
            unlabeledFrames += 1
        }
    }

    private func electedSpeaker() -> String? {
        guard let top = speakerVotes.max(by: { $0.value < $1.value }) else { return nil }
        // A label seen on only a stray frame or two of a long unlabeled line is noise.
        return top.value * 3 >= unlabeledFrames ? top.key : nil
    }

    /// Speak a settled line, unless the game is voicing it.
    ///
    /// Subtitles and the actor's voice start together, but the sound classifier needs a moment to
    /// be sure it hears speech. So a settled line waits ~0.7 s, then Braidy checks whether the game
    /// spoke from 1.5 s before the line settled until now. If it did, the line is shown but not read.
    private func deliver(_ line: String, from name: String?) {
        pendingLine?.cancel()
        guard listensForVoices, listener.isRunning else {
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
        let st = style(for: profile)
        let context = recentLines
        recentLines = Array((recentLines + ["\(lastSpeaker ?? "Narration"): \(line)"]).suffix(3))
        moodTask?.cancel()
        guard expressive else {
            lastMood = nil
            speaker.speak(text, style: st)
            return
        }
        let who = lastSpeaker, about = profile?.about, game = self.game
        moodTask = Task { @MainActor [weak self] in
            let mood = await MoodReader.mood(for: line, speaker: who, about: about, context: context, game: game)
            guard let self, !Task.isCancelled else { return }
            var acted = st
            acted.mood = mood
            self.lastMood = mood
            self.speaker.speak(text, style: acted)
        }
    }

    func repeatLast() {
        guard !lastLine.isEmpty else { return }
        let profile = lastSpeaker.flatMap { cast.match($0, game: game) }
        var text = lastLine
        if sayNames, let who = lastSpeaker { text = "\(who): \(lastLine)" }
        var lineStyle = style(for: profile)
        lineStyle.mood = expressive ? lastMood : nil
        if brodie, Bool.random() {
            // Bubble Buddy chimes in first, in the narrator voice, then the line in its own voice.
            let quip = ["Again, brodie!", "One more time, brodie!", "Okay brodie, here it is again!"].randomElement()!
            speaker.speak(quip, style: style(for: nil), then: (text, lineStyle))
        } else {
            speaker.speak(text, style: lineStyle)
        }
    }

    /// Read whatever is in the box right now, even if it was already read.
    func readNow() {
        let rows = camera.rows
        let parsed: (speaker: String?, body: String) = characterVoices ? SpeakerParser.split(rows, knownNames: cast.names(for: game))
                                     : (speaker: nil, body: TextRow.joined(rows))
        guard !parsed.body.isEmpty else { status = "No text in the reading box"; return }
        pendingLine?.cancel()
        tracker.markSpoken(parsed.body)
        say(parsed.body, from: parsed.speaker)
    }

    func test(_ profile: CharacterProfile? = nil) {
        let line = profile.map { "Hi, I'm \($0.name)!" } ?? (brodie ? "Hi, I'm Bubble Buddy! I'll read the words on the screen for you, brodie!"
                                                          : "Hi, I'm Bubble Buddy! I'll read the words on the screen for you.")
        speaker.speak(line, style: style(for: profile))
    }

    func style(for p: CharacterProfile?) -> VoiceStyle {
        guard characterVoices, var p else {
            return VoiceStyle(voiceID: narratorVoice, pronunciations: pronunciations,
                              elevenVoiceID: elevenNarrator)
        }
        // Give a character an ElevenLabs voice the first time they speak with that engine on.
        if usingEleven, (p.elevenVoiceID ?? "").isEmpty,
           let v = ElevenCasting.pick(for: p, voices: elevenVoices, narrator: elevenNarrator) {
            p.elevenVoiceID = v
            cast.upsert(p, game: game)
        }
        return VoiceStyle(voiceID: p.voiceID.isEmpty ? narratorVoice : p.voiceID,
                          pitch: Float(p.pitch), rate: Float(p.rate), pronunciations: pronunciations,
                          elevenVoiceID: p.elevenVoiceID ?? elevenNarrator)
    }

    // MARK: ElevenLabs

    private func configureEleven() {
        speaker.eleven = usingEleven
            ? ElevenClient(apiKey: elevenKey.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    /// Fetch the account's voices, pick a narrator, and give the cast voices.
    func loadElevenVoices() {
        guard hasElevenKey, !loadingElevenVoices else { return }
        loadingElevenVoices = true
        let client = ElevenClient(apiKey: elevenKey.trimmingCharacters(in: .whitespacesAndNewlines))
        Task { @MainActor [weak self] in
            do {
                let voices = try await client.voices()
                guard let self else { return }
                self.elevenVoices = voices
                if let data = try? JSONEncoder().encode(voices) { self.defaults.set(data, forKey: "elevenVoices") }
                if self.elevenNarrator.isEmpty || !voices.contains(where: { $0.voice_id == self.elevenNarrator }) {
                    self.elevenNarrator = ElevenCasting.narrator(from: voices) ?? ""
                }
                self.castElevenVoices(force: false)
                self.status = "ElevenLabs connected: \(voices.count) voices"
            } catch {
                self?.status = error.localizedDescription
            }
            self?.loadingElevenVoices = false
        }
    }

    /// Give every character an ElevenLabs voice (all of them with force, else only those without one).
    func castElevenVoices(force: Bool) {
        guard !elevenVoices.isEmpty else { return }
        for var p in cast.cast(for: game) {
            if !force && !(p.elevenVoiceID ?? "").isEmpty { continue }
            if p.voiceLocked && !(p.elevenVoiceID ?? "").isEmpty { continue }
            if p.designedVoiceID != nil { continue }
            p.elevenVoiceID = ElevenCasting.pick(for: p, voices: elevenVoices, narrator: elevenNarrator)
            cast.upsert(p, game: game)
        }
    }

    // MARK: Custom ElevenLabs voices

    private var elevenClient: ElevenClient {
        ElevenClient(apiKey: elevenKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Characters with a custom voice in the current game.
    var designedCount: Int { cast.cast(for: game).filter { $0.designedVoiceID != nil }.count }

    /// Claude's description of the character's voice, or one built from what's known about them.
    func voiceDescription(for p: CharacterProfile) -> String {
        if let d = p.voiceDescription, d.count >= 20 { return d }
        var who: [String] = []
        switch p.age {
        case "child": who.append("young")
        case "elder": who.append("old")
        default: break
        }
        if p.gender == "male" || p.gender == "female" { who.append(p.gender) }
        who.append(p.species.isEmpty ? "character" : p.species)
        var s = "A \(who.joined(separator: " ")) named \(p.name)"
        if !game.isEmpty { s += " from the video game \(game)" }
        if !p.about.isEmpty { s += ": \(p.about)" }
        return s + ". Clear, expressive and friendly, easy for a young child to understand."
    }

    @MainActor
    func refreshVoiceSlots() async {
        guard hasElevenKey else { return }
        voiceSlots = try? await elevenClient.slots()
    }

    @MainActor
    func designSamples(_ description: String) async throws -> [ElevenClient.VoicePreview] {
        try await elevenClient.designVoice(description: description)
    }

    /// Save a sample as the character's own voice (replacing any earlier custom voice).
    @MainActor
    func keepDesignedVoice(_ preview: ElevenClient.VoicePreview, key: String, description: String) async throws {
        guard let p = cast.cast(for: game).first(where: { $0.key == key }) else { return }
        let client = elevenClient
        let name = "\(ElevenClient.designedPrefix)\(p.name) (\(game))"
        let id = try await client.saveDesignedVoice(name: name, description: description, generatedID: preview.generatedID)
        let old = p.designedVoiceID
        if let old, old != id { try? await client.deleteVoice(old) }
        // Re-read: the profile may have changed while waiting.
        var q = cast.cast(for: game).first(where: { $0.key == key }) ?? p
        q.designedVoiceID = id
        q.elevenVoiceID = id
        q.voiceDescription = description
        q.voiceLocked = true
        cast.upsert(q, game: game)
        elevenVoices.removeAll { $0.voice_id == old }
        elevenVoices.append(ElevenVoice(voice_id: id, name: name, labels: nil, description: description))
        if let data = try? JSONEncoder().encode(elevenVoices) { defaults.set(data, forKey: "elevenVoices") }
        voiceSlots = try? await client.slots()
    }

    /// Design and keep voices for the stars (then major characters), as many as the plan has room for.
    func designMainVoices() {
        guard hasElevenKey, !game.isEmpty, !designingVoices else { return }
        designingVoices = true
        let client = elevenClient
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.designingVoices = false }
            let slots = try? await client.slots()
            self.voiceSlots = slots
            let free = slots?.free ?? 3
            guard free > 0 else {
                self.status = "No free voice slots on your ElevenLabs plan. Remove custom voices from another game first."
                return
            }
            let rank: [String: Int] = ["star": 0, "major": 1]
            let all = self.cast.cast(for: self.game).filter { $0.designedVoiceID == nil }
            let ranked = all.filter { rank[$0.role ?? ""] != nil }
                .sorted { rank[$0.role ?? ""]! < rank[$1.role ?? ""]! }
            let todo = Array((ranked.isEmpty ? all : ranked).prefix(min(free, 6)))
            guard !todo.isEmpty else {
                self.status = all.isEmpty && self.designedCount > 0
                    ? "Every character already has a custom voice."
                    : "No characters yet. Look them up with Claude first."
                return
            }
            var made = 0
            for p in todo {
                self.status = "Designing a voice for \(p.name)… (\(made + 1) of \(todo.count))"
                do {
                    let d = self.voiceDescription(for: p)
                    let samples = try await client.designVoice(description: d)
                    guard let first = samples.first else { continue }
                    try await self.keepDesignedVoice(first, key: p.key, description: d)
                    made += 1
                } catch {
                    self.status = ElevenClient.friendly(error)
                    return
                }
            }
            self.status = made == 1 ? "Designed 1 custom voice" : "Designed \(made) custom voices"
        }
    }

    /// Delete this game's custom voices from the ElevenLabs account and go back to stock voices.
    func removeDesignedVoices() {
        guard hasElevenKey else { return }
        let client = elevenClient
        Task { @MainActor [weak self] in
            guard let self else { return }
            for var p in self.cast.cast(for: self.game) {
                guard let id = p.designedVoiceID else { continue }
                try? await client.deleteVoice(id)
                self.elevenVoices.removeAll { $0.voice_id == id }
                p.designedVoiceID = nil
                p.voiceLocked = false
                p.elevenVoiceID = ElevenCasting.pick(for: p, voices: self.elevenVoices, narrator: self.elevenNarrator)
                self.cast.upsert(p, game: self.game)
            }
            if let data = try? JSONEncoder().encode(self.elevenVoices) { self.defaults.set(data, forKey: "elevenVoices") }
            self.voiceSlots = try? await client.slots()
            self.status = "Removed this game's custom voices"
        }
    }

    // MARK: Cast

    /// Find or create the profile for a name read off the screen, asking Claude about newcomers.
    private func profileFor(speakerName name: String) -> CharacterProfile? {
        if let known = cast.match(name, game: game) { return known }
        // A misread label ("Lnik") shouldn't become a new character with a different voice.
        if DialogueTracker.normalize(name).count >= 4, let close = cast.match(name, game: game, threshold: 0.65) {
            return close
        }
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
                let reply = try await client.lookUpCast(game: game)
                let entries = reply.characters
                guard let self else { return }
                if let terms = reply.terms {
                    self.cast.setTerms(terms.map { GameTerm(word: $0.word, say: $0.say) }, game: game)
                }
                let wasListening = self.listenThisGame
                self.noteVoiced(reply.voiced, game: game)
                for e in entries {
                    let existing = self.cast.match(e.name, game: game) ?? CharacterProfile(name: e.name)
                    self.apply(e, to: existing, game: game)
                }
                var note = "Found \(entries.count) characters"
                if wasListening && !self.listenThisGame && self.quietWhenGameTalks {
                    note += ". It's a text-only game, so the mic is off"
                }
                self.status = note
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
        if let say = e.say, !say.isEmpty { p.say = say }
        if let role = e.role, !role.isEmpty { p.role = role.lowercased() }
        if let voice = e.voice, voice.count >= 20 { p.voiceDescription = voice }
        if !p.voiceLocked {
            if let pitch = e.pitch { p.pitch = min(max(pitch, 0.5), 2.0) } else { VoiceCasting.defaultStyle(&p) }
            if let rate = e.rate { p.rate = min(max(rate, 0.6), 1.5) }
            p.voiceID = VoiceCasting.pick(for: p, voices: voices, narrator: narratorVoice)
            if !elevenVoices.isEmpty && p.designedVoiceID == nil {
                p.elevenVoiceID = ElevenCasting.pick(for: p, voices: elevenVoices, narrator: elevenNarrator)
            }
        }
        p.source = "claude"
        cast.upsert(p, game: game)
        updateCustomWords()
    }

    /// Games on the chosen platform matching what someone typed (partial, misspelled or a series name).
    func searchGames(_ query: String, platform: String) async throws -> [ClaudeClient.GameMatch] {
        try await client.searchGames(query: query, platform: platform)
    }

    func popularGames(platform: String) async throws -> [ClaudeClient.GameMatch] {
        if let cached = popularCache[platform] { return cached }
        let list = try await client.popularGames(platform: platform)
        popularCache[platform] = list
        return list
    }

    /// Switch the narrator and every character not set by hand to the best installed voices.
    func useBestVoices() {
        voices = Speaker.englishVoices()
        if let best = voices.first { narratorVoice = best.identifier }
        for var p in cast.cast(for: game) where !p.voiceLocked {
            p.voiceID = VoiceCasting.pick(for: p, voices: voices, narrator: narratorVoice)
            cast.upsert(p, game: game)
        }
        status = goodVoiceCount > 0 ? "Using the best voices on this iPad" : "No Enhanced or Premium voices installed yet"
    }

    /// Set the game, confirm it on screen, and look up its characters if they aren't known yet.
    func choose(game title: String, detail: String = "", voiced: String? = nil) {
        noteVoiced(voiced, game: title)
        game = title
        gameDetail = detail
        let mic = quietWhenGameTalks && gameVoiced == "none" && listenOverride == nil
            ? " Text only, so the mic stays off." : ""
        if hasKey && cast.cast(for: title).isEmpty {
            lookUpCast()
            status = "✓ Game set: \(title).\(mic) Looking up its characters…"
        } else {
            status = "✓ Game set: \(title).\(mic)"
        }
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
                        self.gameDetail = ""
                        self.lookUpCast()
                        self.status = "Claude thinks this is \(reply.game). Looking up its characters…"
                    }
                } catch {
                    self?.status = error.localizedDescription
                    self?.lookingUp = false
                }
            }
        }
    }

    /// Respellings for this game's names and words (from Claude's lookups).
    private var pronunciations: [String: String] = [:]

    /// Teach OCR this game's names and words, and refresh their pronunciations.
    private func updateCustomWords() {
        let names = cast.names(for: game).flatMap { $0.split(separator: " ").map(String.init) }
        let terms = cast.terms(for: game).flatMap { $0.word.split(separator: " ").map(String.init) }
        camera.customWords = Array(Set(CameraModel.commonWords + names + terms))
        pronunciations = cast.pronunciations(for: game)
    }
}
