import SwiftUI

struct ContentView: View {
    @StateObject private var reader = Reader()
    @State private var editing = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraStage(camera: reader.camera, region: $reader.region, editing: editing)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                Spacer()
                if editing {
                    editBanner
                } else {
                    caption
                    controls
                }
            }
            .padding(20)

            PermissionOverlay(camera: reader.camera)
        }
        .onAppear {
            reader.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showSettings) {
            SettingsView(reader: reader, camera: reader.camera, cast: reader.cast, editing: $editing)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            StatusPill(camera: reader.camera, listener: reader.listener, listening: reader.listening,
                       hearing: reader.quietWhenGameTalks)
            if !reader.game.isEmpty {
                Label(reader.game, systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            if let status = reader.status {
                Text(status)
                    .font(.footnote)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .onTapGesture { reader.status = nil }
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title2)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let who = reader.lastSpeaker {
                    Text(who)
                        .font(.headline)
                        .foregroundStyle(.yellow)
                }
                if reader.lastLineWasVoiced {
                    Label("The game said this", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
            Text(reader.lastLine.isEmpty ? "Point the camera at the screen. I'll read the words in the box out loud."
                                         : reader.lastLine)
                .font(.system(.title2, design: .rounded).weight(.medium))
                .foregroundStyle(reader.lastLine.isEmpty ? .secondary : .primary)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.cyan.opacity(reader.isSpeaking ? 0.9 : 0), lineWidth: 3)
                .animation(.easeInOut(duration: 0.25), value: reader.isSpeaking)
        )
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { reader.listening.toggle() } label: {
                Label(reader.listening ? "Pause" : "Listen",
                      systemImage: reader.listening ? "pause.fill" : "ear.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 150, height: 64)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Button { reader.repeatLast() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 40, weight: .bold))
                    .frame(width: 104, height: 104)
                    .background(Circle().fill(Color.cyan.gradient))
                    .foregroundStyle(.black)
                    .shadow(color: .cyan.opacity(0.5), radius: 14)
            }
            .accessibilityLabel("Say it again")
            .disabled(reader.lastLine.isEmpty)
            Button { reader.readNow() } label: {
                Label("Read now", systemImage: "text.viewfinder")
                    .font(.title3.weight(.semibold))
                    .frame(width: 150, height: 64)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .foregroundStyle(.white)
    }

    private var editBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.draw.fill").font(.title)
            Text("Drag the yellow box over where the words appear. Drag the dot to resize it.")
                .font(.headline)
            Spacer(minLength: 0)
            Button("Done") { editing = false }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: 820)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct StatusPill: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var listener: VoiceListener
    let listening: Bool
    let hearing: Bool

    var body: some View {
        let seeing = listening && !camera.rows.isEmpty
        HStack(spacing: 8) {
            Circle()
                .fill(!listening ? Color.gray : (seeing ? Color.green : Color.orange))
                .frame(width: 12, height: 12)
            Text(!listening ? "Paused" : (seeing ? "I see words" : "Looking for words"))
                .font(.footnote.weight(.semibold))
            if listening && hearing && listener.gameTalking {
                Divider().frame(height: 14)
                Image(systemName: "waveform").foregroundStyle(.purple)
                Text("Game is talking").font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: listener.gameTalking)
    }
}

struct PermissionOverlay: View {
    @ObservedObject var camera: CameraModel

    var body: some View {
        if camera.authorized == false {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill").font(.system(size: 48))
                Text("Sidekick needs the camera to see the game's words.")
                    .font(.title3.weight(.semibold))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
