import AVFoundation
import SwiftUI

/// Options: the grown-ups' menu (opened by press-and-hold on the gear).
struct OptionsView: View {
    @ObservedObject var reader: Reader
    @ObservedObject var camera: CameraModel
    @ObservedObject var cast: CastStore
    @Binding var editing: Bool
    var replayTutorial: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                gameSection
                charactersSection
                ElevenLabsSection(reader: reader)
                voiceSection
                GameVoiceSection(reader: reader, listener: reader.listener)
                cameraSection
                extrasSection
                helpSection
            }
            .arcadeForm()
            .navigationTitle("Options")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Theme.body(17, .heavy))
                }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
    }

    // MARK: Sections

    private var gameSection: some View {
        Section {
            NavigationLink {
                PlatformPickerView(reader: reader)
            } label: {
                HStack(alignment: .top) {
                    MenuIcon("gamecontroller.fill", Theme.green)
                    Text("Game")
                    Spacer()
                    if reader.game.isEmpty {
                        Text("Choose…").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(reader.game, systemImage: "checkmark.seal.fill")
                                .labelStyle(TrailingIconLabelStyle())
                                .foregroundStyle(.primary)
                            if !reader.gameDetail.isEmpty {
                                Text(reader.gameDetail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                    }
                }
            }
            if reader.hasKey {
                Button {
                    reader.identifyGame()
                } label: {
                    Label("Ask Claude which game is on screen", systemImage: "sparkles")
                }
                .disabled(reader.lookingUp)
            }
        } header: {
            ArcadeHeader("Now playing")
        } footer: {
            Text("Braidy remembers the reading box for each game.")
        }
    }

    private var charactersSection: some View {
        Section {
            Toggle(isOn: $reader.characterVoices) {
                HStack { MenuIcon("person.2.wave.2.fill", Theme.pink); Text("A different voice for each character") }
            }
            Toggle(isOn: $reader.sayNames) {
                HStack { MenuIcon("tag.fill", Theme.yellow); Text("Say the character's name first") }
            }
            Toggle(isOn: $reader.brodie) {
                HStack { MenuIcon("face.smiling.inverse", Theme.cyan); Text("Bubble Buddy says \u{201C}brodie\u{201D}") }
            }
            NavigationLink {
                CastView(reader: reader, cast: cast)
            } label: {
                HStack {
                    MenuIcon("theatermasks.fill", Theme.violet)
                    Text("Characters")
                    Spacer()
                    Text("\(cast.cast(for: reader.game).count)").foregroundStyle(.secondary)
                }
            }
            .disabled(reader.game.isEmpty)
            if reader.hasKey {
                Button {
                    reader.lookUpCast()
                } label: {
                    HStack {
                        Label("Look up characters with Claude", systemImage: "sparkles")
                        if reader.lookingUp { Spacer(); ProgressView() }
                    }
                }
                .disabled(reader.game.isEmpty || reader.lookingUp)
            }
        } header: {
            ArcadeHeader("Characters")
        } footer: {
            Text(reader.hasKey
                 ? "When a new name shows up above the words, Claude looks up who it is and picks a voice that fits. You can change any voice by hand."
                 : "Braidy notices the name above the words and gives each character their own voice. Add Claude in Extras to match voices to who they are.")
        }
    }

    private var voiceSection: some View {
        Section {
            Picker("Narrator voice", selection: $reader.narratorVoice) {
                ForEach(reader.voices, id: \.identifier) { v in
                    Text(Speaker.label(v)).tag(v.identifier)
                }
            }
            HStack {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                Slider(value: $reader.rate, in: 0.3...0.6)
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
            Button("Test the voice") { reader.test() }
            if reader.goodVoiceCount < 3 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Voices sound robotic?", systemImage: "waveform.badge.exclamationmark")
                        .font(.headline)
                    Text("This device has \(reader.goodVoiceCount) natural-sounding English voice\(reader.goodVoiceCount == 1 ? "" : "s"). Download a few free Enhanced or Premium ones: Settings › Accessibility › Spoken Content (or Read & Speak) › Voices › English. Ava, Zoe, Evan and Nathan (Premium) sound great. Then come back and tap Use the best voices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Button("Use the best voices") { reader.useBestVoices() }
        } header: {
            ArcadeHeader(reader.usingEleven ? "Device voices (backup)" : "Voice")
        }
    }

    private var cameraSection: some View {
        Section {
            HStack {
                MenuIcon("plus.magnifyingglass", Theme.cyan)
                Text("Zoom")
                Slider(value: $reader.zoom, in: 1...max(1.01, Double(camera.maxZoom)))
                Text(String(format: "%.1f×", reader.zoom)).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { editing = true; dismiss() } label: {
                HStack { MenuIcon("rectangle.dashed", Theme.yellow); Text("Move the reading box") }
            }
            Button("Reset the reading box") { reader.region = Reader.defaultRegion }
        } header: {
            ArcadeHeader("Reading box & camera")
        } footer: {
            Text("Zoom in if the device sits far from the TV.")
        }
    }

    private var extrasSection: some View {
        Section {
            NavigationLink {
                ExtrasSetupView(reader: reader)
            } label: {
                HStack {
                    MenuIcon("wand.and.stars", Theme.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extras")
                        Text("Smarter characters (Claude) · Movie-quality voices (ElevenLabs)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ExtraBadge(on: reader.hasKey, label: "Claude")
                    ExtraBadge(on: reader.hasElevenKey, label: "11")
                }
            }
        } header: {
            ArcadeHeader("Optional extras")
        } footer: {
            Text("Braidy works fully without these. They're optional add-ons you connect with your own accounts.")
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink { HowItWorksView() } label: {
                HStack { MenuIcon("lightbulb.fill", Theme.yellow); Text("How Braidy works") }
            }
            NavigationLink { PrivacyView() } label: {
                HStack { MenuIcon("lock.shield.fill", Theme.green); Text("Privacy") }
            }
            Button {
                dismiss()
                replayTutorial()
            } label: {
                HStack { MenuIcon("play.rectangle.fill", Theme.cyan); Text("Replay the setup tutorial") }
            }
        } header: {
            ArcadeHeader("Help")
        }
    }
}

/// A rounded colored icon tile for menu rows.
struct MenuIcon: View {
    let name: String
    let color: Color
    init(_ name: String, _ color: Color) { self.name = name; self.color = color }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.night)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.gradient))
    }
}

struct ArcadeHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Theme.title(13)).tracking(1.5).foregroundStyle(Theme.yellow)
    }
}

struct ExtraBadge: View {
    let on: Bool
    let label: String
    var body: some View {
        Text(label)
            .font(Theme.body(11, .heavy))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(on ? Theme.green : Color.gray.opacity(0.35)))
            .foregroundStyle(on ? Theme.night : .white.opacity(0.7))
    }
}

extension View {
    /// Night-sky background and translucent rows for Forms and Lists.
    func arcadeForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ArcadeBackground())
    }
}

struct CastView: View {
    @ObservedObject var reader: Reader
    @ObservedObject var cast: CastStore
    @State private var newName = ""

    var body: some View {
        let people = cast.cast(for: reader.game)
        List {
            Section {
                if people.isEmpty {
                    Text("No characters yet. They're added as Braidy sees their names, or look them all up with Claude.")
                        .foregroundStyle(.secondary)
                }
                ForEach(people) { p in
                    NavigationLink {
                        CharacterEditor(reader: reader, cast: cast, key: p.key)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            if !p.summary.isEmpty {
                                Text(p.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in idx.map { people[$0] }.forEach { cast.remove($0, game: reader.game) } }
            } header: {
                Text(reader.game)
            }
            Section("Add a character") {
                HStack {
                    TextField("Name as it appears on screen", text: $newName)
                    Button("Add") {
                        var p = CharacterProfile(name: newName.trimmingCharacters(in: .whitespaces))
                        p.voiceID = VoiceCasting.pick(for: p, voices: reader.voices, narrator: reader.narratorVoice)
                        p.source = "manual"
                        cast.upsert(p, game: reader.game)
                        reader.lookUp(character: p)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .arcadeForm()
        .navigationTitle("Characters")
        .toolbar {
            Button {
                reader.lookUpCast()
            } label: {
                if reader.lookingUp { ProgressView() } else { Label("Look up with Claude", systemImage: "sparkles") }
            }
            .disabled(!reader.hasKey || reader.lookingUp)
        }
    }
}

struct CharacterEditor: View {
    @ObservedObject var reader: Reader
    @ObservedObject var cast: CastStore
    let key: String

    private var profile: CharacterProfile? { cast.cast(for: reader.game).first { $0.key == key } }

    var body: some View {
        if let p = profile {
            Form {
                Section {
                    if !p.about.isEmpty { Text(p.about) }
                    Picker("Gender", selection: binding(\.gender, p)) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Neutral").tag("neutral")
                        Text("Unknown").tag("unknown")
                    }
                    TextField("Species", text: binding(\.species, p))
                    Picker("Age", selection: binding(\.age, p)) {
                        Text("Child").tag("child")
                        Text("Adult").tag("adult")
                        Text("Elder").tag("elder")
                    }
                    if !p.aliases.isEmpty {
                        LabeledContent("Also shown as", value: p.aliases.joined(separator: ", "))
                    }
                }
                if reader.usingEleven && !reader.elevenVoices.isEmpty {
                    Section("ElevenLabs voice") {
                        NavigationLink {
                            VoiceDesignView(reader: reader, cast: cast, key: p.key)
                        } label: {
                            HStack {
                                Label(p.designedVoiceID == nil ? "Design a custom voice" : "Custom voice",
                                      systemImage: "wand.and.stars")
                                    .foregroundStyle(Theme.yellow)
                                if p.designedVoiceID != nil {
                                    Spacer()
                                    Text("Redesign").foregroundStyle(.secondary)
                                }
                            }
                        }
                        Picker("Voice", selection: elevenBinding(p)) {
                            ForEach(reader.elevenVoices) { v in Text(v.summary).tag(v.voice_id) }
                        }
                        Button("Test") { reader.test(profile ?? p) }
                    }
                }
                Section(reader.usingEleven ? "iPad voice" as String : "Voice") {
                    Picker("Voice", selection: binding(\.voiceID, p, lock: true)) {
                        ForEach(reader.voices, id: \.identifier) { v in
                            Text(Speaker.label(v)).tag(v.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Pitch \(String(format: "%.2f", p.pitch))")
                        Slider(value: binding(\.pitch, p, lock: true), in: 0.5...2.0)
                    }
                    VStack(alignment: .leading) {
                        Text("Speed \(String(format: "%.2f", p.rate))×")
                        Slider(value: binding(\.rate, p, lock: true), in: 0.6...1.5)
                    }
                    Button("Test") { reader.test(p) }
                    Button("Pick a voice to match gender") {
                        var q = p
                        q.voiceID = VoiceCasting.pick(for: q, voices: reader.voices, narrator: reader.narratorVoice)
                        cast.upsert(q, game: reader.game)
                    }
                }
                Section {
                    Button {
                        var q = p
                        q.voiceLocked = false
                        cast.upsert(q, game: reader.game)
                        reader.lookUp(character: q)
                    } label: {
                        Label("Ask Claude about \(p.name) again", systemImage: "sparkles")
                    }
                    .disabled(!reader.hasKey)
                } footer: {
                    Text(p.voiceLocked ? "You've set this voice by hand, so Claude's lookups won't change it unless you ask again here." : "")
                }
            }
            .arcadeForm()
            .navigationTitle(p.name)
        } else {
            Text("This character was removed.").foregroundStyle(.secondary)
        }
    }

    private func elevenBinding(_ p: CharacterProfile) -> Binding<String> {
        Binding(
            get: { (profile ?? p).elevenVoiceID ?? "" },
            set: { value in
                var q = profile ?? p
                q.elevenVoiceID = value
                q.voiceLocked = true
                cast.upsert(q, game: reader.game)
            }
        )
    }

    private func binding<T>(_ path: WritableKeyPath<CharacterProfile, T>, _ p: CharacterProfile,
                            lock: Bool = false) -> Binding<T> {
        Binding(
            get: { profile?[keyPath: path] ?? p[keyPath: path] },
            set: { value in
                var q = profile ?? p
                q[keyPath: path] = value
                if lock { q.voiceLocked = true }
                cast.upsert(q, game: reader.game)
            }
        )
    }
}

/// Settings for staying quiet while the game's own voice acting plays.
struct GameVoiceSection: View {
    @ObservedObject var reader: Reader
    @ObservedObject var listener: VoiceListener

    var body: some View {
        Section {
            Toggle("Stay quiet when the game is talking", isOn: $reader.quietWhenGameTalks)
            if reader.quietWhenGameTalks {
                if listener.available == false {
                    Label("Braidy can't use the microphone. Allow it in the iPad's Settings › Braidy.",
                          systemImage: "mic.slash.fill")
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Hearing speech")
                        ProgressView(value: min(max(listener.level, 0), 1))
                            .tint(listener.level >= reader.voiceSensitivity ? .purple : .gray)
                    }
                    VStack(alignment: .leading) {
                        Text("Needs to be this sure it's a voice: \(Int(reader.voiceSensitivity * 100))%")
                        Slider(value: $reader.voiceSensitivity, in: 0.3...0.9)
                    }
                }
            }
        } header: {
            Text("Voiced cutscenes")
        } footer: {
            Text("Braidy listens for voice acting (on this iPad, nothing is recorded or sent). When a subtitle appears while the game is speaking, Braidy shows it but doesn't read it; tap the repeat button to hear it anyway. Short grunts and \"Hmm!\" sounds don't count. People talking in the room can also make Braidy stay quiet, so raise the setting if it skips lines it should read.")
        }
    }
}

/// Title first, icon after it (for the confirmed game).
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.foregroundStyle(.green)
        }
    }
}

/// Which voices Braidy speaks with. The ElevenLabs key itself is set up in Extras.
struct ElevenLabsSection: View {
    @ObservedObject var reader: Reader
    @State private var cacheNote = ""

    var body: some View {
        Section {
            Picker("Voices", selection: $reader.voiceEngine) {
                Text("Device (free)").tag("apple")
                Text("ElevenLabs").tag("eleven")
            }
            .pickerStyle(.segmented)

            if reader.voiceEngine == "eleven" {
                if !reader.hasElevenKey {
                    NavigationLink {
                        ExtrasSetupView(reader: reader)
                    } label: {
                        Label("Connect ElevenLabs to use these voices", systemImage: "link")
                            .foregroundStyle(Theme.yellow)
                    }
                } else {
                    HStack {
                        Text("Status")
                        Spacer()
                        if reader.loadingElevenVoices {
                            ProgressView()
                        } else if !reader.elevenVoices.isEmpty {
                            Label("\(reader.elevenVoices.count) voices ready", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.green)
                        }
                    }
                    Picker("Quality", selection: $reader.elevenModel) {
                        ForEach(ElevenClient.models, id: \.id) { m in Text(m.label).tag(m.id) }
                    }
                    if !reader.elevenVoices.isEmpty {
                        Picker("Narrator", selection: $reader.elevenNarrator) {
                            ForEach(reader.elevenVoices) { v in Text(v.summary).tag(v.voice_id) }
                        }
                        Button("Test the narrator") { reader.test() }
                        Button("Re-pick every character's voice") { reader.castElevenVoices(force: true) }
                        Button {
                            reader.designMainVoices()
                        } label: {
                            HStack {
                                Label("Design custom voices for the main characters", systemImage: "wand.and.stars")
                                if reader.designingVoices { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(reader.game.isEmpty || reader.designingVoices)
                        if let slots = reader.voiceSlots, slots.limit > 0 {
                            LabeledContent("Voice slots used", value: "\(slots.used) of \(slots.limit)")
                        }
                        if reader.designedCount > 0 {
                            Button("Remove this game's custom voices", role: .destructive) { reader.removeDesignedVoices() }
                        }
                    }
                    LabeledContent("Used this month", value: "\(AudioCache.shared.charactersThisMonth.formatted()) characters")
                    HStack {
                        Button("Clear saved audio", role: .destructive) {
                            AudioCache.shared.clear()
                            cacheNote = "Cleared"
                        }
                        Spacer()
                        Text(cacheNote).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            ArcadeHeader("Voices")
        } footer: {
            Text(reader.voiceEngine == "eleven"
                 ? "Each character gets a natural voice that fits them. Custom voices are one-of-a-kind voices designed from how Claude describes each main character; each one uses a voice slot on your ElevenLabs plan (Free has 3). Every line is saved on this device, so it's only paid for once. If ElevenLabs can't be reached, Braidy uses the device's own voice."
                 : "The device's own voices are free and work offline.")
        }
        .task { await reader.refreshVoiceSlots() }
        .onAppear {
            let mb = Double(AudioCache.shared.bytesOnDisk) / 1_000_000
            cacheNote = mb > 0.05 ? String(format: "%.1f MB saved", mb) : ""
        }
    }
}
