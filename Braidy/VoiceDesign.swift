import AVFoundation
import SwiftUI

/// Design a one-of-a-kind ElevenLabs voice for a character: describe it, hear three samples, keep one.
struct VoiceDesignView: View {
    @ObservedObject var reader: Reader
    @ObservedObject var cast: CastStore
    let key: String

    @State private var description = ""
    @State private var samples: [ElevenClient.VoicePreview] = []
    @State private var working = false
    @State private var saving: String?
    @State private var message: String?
    @State private var player: AVAudioPlayer?
    @State private var playing: String?
    @Environment(\.dismiss) private var dismiss

    private var profile: CharacterProfile? { cast.cast(for: reader.game).first { $0.key == key } }

    var body: some View {
        let name = profile?.name ?? "this character"
        Form {
            Section {
                TextEditor(text: $description)
                    .frame(minHeight: 110)
                    .font(Theme.body(16))
            } header: {
                ArcadeHeader("How should \(name) sound?")
            } footer: {
                Text(profile?.voiceDescription == nil
                     ? "A starting point from what Braidy knows. Describe age, pitch, accent and personality, then make samples."
                     : "Written by Claude from what it knows about \(name). Change anything you like, then make samples.")
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        Label(samples.isEmpty ? "Make 3 sample voices" : "Make 3 new samples", systemImage: "wand.and.stars")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || description.trimmingCharacters(in: .whitespaces).count < 20)
            } footer: {
                Text(slotNote)
            }

            if !samples.isEmpty {
                Section {
                    ForEach(Array(samples.enumerated()), id: \.element.id) { i, sample in
                        HStack {
                            Button {
                                play(sample)
                            } label: {
                                Label("Sample \(i + 1)",
                                      systemImage: playing == sample.id ? "speaker.wave.2.fill" : "play.circle.fill")
                                    .font(Theme.body(17))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            Button {
                                keep(sample)
                            } label: {
                                if saving == sample.id { ProgressView() } else { Text("Use this voice") }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.pink)
                            .disabled(saving != nil)
                        }
                    }
                } header: {
                    ArcadeHeader("Pick one")
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(Theme.pink) }
            }
        }
        .arcadeForm()
        .navigationTitle("Custom voice")
        .onAppear {
            if description.isEmpty, let p = profile { description = reader.voiceDescription(for: p) }
            Task { await reader.refreshVoiceSlots() }
        }
        .onDisappear { player?.stop() }
    }

    private var slotNote: String {
        var note = "Each set of samples uses a little ElevenLabs credit. Keeping one saves it to your ElevenLabs account and uses a voice slot"
        if let s = reader.voiceSlots, s.limit > 0 {
            note += " (\(s.used) of \(s.limit) used)"
        }
        if profile?.designedVoiceID != nil { note += ". This replaces \(profile?.name ?? "the character")'s current custom voice, so no extra slot" }
        return note + "."
    }

    private func generate() {
        working = true
        message = nil
        player?.stop()
        playing = nil
        let text = description
        Task { @MainActor in
            do {
                samples = try await reader.designSamples(text)
                if samples.isEmpty { message = "ElevenLabs didn't send any samples. Try again or change the description." }
                else if let first = samples.first { play(first) }
            } catch {
                message = ElevenClient.friendly(error)
            }
            working = false
        }
    }

    private func play(_ sample: ElevenClient.VoicePreview) {
        player?.stop()
        guard let p = try? AVAudioPlayer(data: sample.audio) else { return }
        player = p
        playing = sample.id
        p.play()
        Theme.tap()
    }

    private func keep(_ sample: ElevenClient.VoicePreview) {
        saving = sample.id
        message = nil
        player?.stop()
        let text = description
        Task { @MainActor in
            do {
                try await reader.keepDesignedVoice(sample, key: key, description: text)
                Theme.success()
                reader.test(profile)
                dismiss()
            } catch {
                message = ElevenClient.friendly(error)
            }
            saving = nil
        }
    }
}
