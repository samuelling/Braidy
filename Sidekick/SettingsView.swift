import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var reader: Reader
    @ObservedObject var camera: CameraModel
    @ObservedObject var cast: CastStore
    @Binding var editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                gameSection
                charactersSection
                voiceSection
                GameVoiceSection(reader: reader, listener: reader.listener)
                claudeSection
                cameraSection
                Section("Tips") {
                    Text("Prop the iPad up so the whole TV or Switch screen is in view, then make the reading box cover just the dialogue area so the map and menus aren't read out.")
                    Text("Better voices: on the iPad, open Settings › Accessibility › Spoken Content › Voices › English and download a few Enhanced or Premium voices. They show up here after you reopen Sidekick.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Sidekick")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { keyDraft = reader.apiKey }
        }
    }

    // MARK: Sections

    private var gameSection: some View {
        Section {
            TextField("Which game?", text: $reader.game)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Menu("Choose a game") {
                ForEach(Reader.suggestedGames, id: \.self) { g in
                    Button(g) { reader.game = g }
                }
            }
            Button {
                reader.identifyGame()
            } label: {
                Label("Ask Claude which game is on screen", systemImage: "sparkles")
            }
            .disabled(!reader.hasKey || reader.lookingUp)
        } header: {
            Text("Game")
        } footer: {
            Text("Knowing the game lets Claude look up its characters and give each one a fitting voice.")
        }
    }

    private var charactersSection: some View {
        Section {
            Toggle("A different voice for each character", isOn: $reader.characterVoices)
            Toggle("Say the character's name first", isOn: $reader.sayNames)
            NavigationLink {
                CastView(reader: reader, cast: cast)
            } label: {
                HStack {
                    Text("Characters")
                    Spacer()
                    Text("\(cast.cast(for: reader.game).count)").foregroundStyle(.secondary)
                }
            }
            .disabled(reader.game.isEmpty)
            Button {
                reader.lookUpCast()
            } label: {
                HStack {
                    Label("Look up characters with Claude", systemImage: "person.3.fill")
                    if reader.lookingUp { Spacer(); ProgressView() }
                }
            }
            .disabled(!reader.hasKey || reader.game.isEmpty || reader.lookingUp)
        } header: {
            Text("Characters")
        } footer: {
            Text("Sidekick reads the speaker's name above the dialogue. Characters it hasn't met yet get looked up automatically when a Claude key is set; you can change any voice by hand.")
        }
    }

    private var voiceSection: some View {
        Section("Voice") {
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
        }
    }

    private var claudeSection: some View {
        Section {
            SecureField("Claude API key (sk-ant-…)", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { reader.apiKey = keyDraft }
            HStack {
                Button("Save key") { reader.apiKey = keyDraft }
                    .disabled(keyDraft == reader.apiKey)
                Spacer()
                if reader.hasKey {
                    Label("Key saved", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            if reader.hasKey {
                Button("Remove key", role: .destructive) { keyDraft = ""; reader.apiKey = "" }
            }
            Link("Get an API key at platform.claude.com",
                 destination: URL(string: "https://platform.claude.com/settings/keys")!)
        } header: {
            Text("Claude")
        } footer: {
            Text("Only character lookups use Claude; reading the screen and speaking happen on this iPad. Claude.ai subscriptions can't sign in to other apps, so this uses an API key, billed per use (a cast lookup is a few cents). The key stays in this iPad's Keychain.")
        }
    }

    private var cameraSection: some View {
        Section {
            HStack {
                Text("Zoom")
                Slider(value: $reader.zoom, in: 1...max(1.01, Double(camera.maxZoom)))
                Text(String(format: "%.1f×", reader.zoom)).monospacedDigit().foregroundStyle(.secondary)
            }
            Button("Move the reading box") { editing = true; dismiss() }
            Button("Reset the reading box") { reader.region = Reader.defaultRegion }
        } header: {
            Text("Camera")
        } footer: {
            Text("Zoom in if the iPad sits far from the TV.")
        }
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
                    Text("No characters yet. They're added as Sidekick sees their names, or look them all up with Claude.")
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
                Section("Voice") {
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
            .navigationTitle(p.name)
        } else {
            Text("This character was removed.").foregroundStyle(.secondary)
        }
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
                    Label("Sidekick can't use the microphone. Allow it in the iPad's Settings › Sidekick.",
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
            Text("Sidekick listens for voice acting (on this iPad, nothing is recorded or sent). When a subtitle appears while the game is speaking, Sidekick shows it but doesn't read it; tap the repeat button to hear it anyway. Short grunts and \"Hmm!\" sounds don't count. People talking in the room can also make Sidekick stay quiet, so raise the setting if it skips lines it should read.")
        }
    }
}
