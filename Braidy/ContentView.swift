import SwiftUI

struct ContentView: View {
    @StateObject private var reader = Reader()
    @AppStorage("onboarded") private var onboarded = false
    @State private var editing = false
    @State private var showOptions = false
    @State private var showOnboarding = false

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 600
            ZStack {
                Color.black.ignoresSafeArea()
                CameraStage(camera: reader.camera, region: $reader.region, editing: editing)
                    .ignoresSafeArea()
                // Darken the edges so the HUD reads over any picture.
                LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: compact ? 10 : 14) {
                    TopHUD(reader: reader, compact: compact) { showOptions = true }
                    Spacer(minLength: 0)
                    if editing {
                        EditBanner { editing = false; Theme.success() }
                    } else {
                        DialogueBox(reader: reader, compact: compact)
                        ControlBar(reader: reader, compact: compact)
                    }
                }
                .padding(.horizontal, compact ? 12 : 22)
                .padding(.vertical, compact ? 8 : 16)

                PermissionOverlay(camera: reader.camera)
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if onboarded { reader.start() } else { showOnboarding = true }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showOptions) {
            OptionsView(reader: reader, camera: reader.camera, cast: reader.cast, editing: $editing) {
                showOptions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showOnboarding = true }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(reader: reader) { placeBox in
                onboarded = true
                showOnboarding = false
                reader.start()
                if placeBox { editing = true }
            }
        }
    }
}

// MARK: - Top HUD

struct TopHUD: View {
    @ObservedObject var reader: Reader
    var compact: Bool
    var openOptions: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image("Mascot").resizable().scaledToFit().frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if !compact {
                    Text("BRAIDY").font(Theme.title(18)).tracking(2).foregroundStyle(Theme.yellow)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.panel.opacity(0.88)))
            .overlay(Capsule().strokeBorder(Theme.yellow, lineWidth: 2))

            StatusChip(camera: reader.camera, listener: reader.listener,
                       listening: reader.listening, hearing: reader.quietWhenGameTalks)

            if !reader.game.isEmpty && !compact {
                HUDChip(tint: Theme.green) {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.green)
                    Text(reader.game).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let status = reader.status {
                HUDChip(tint: Theme.cyan) { Text(status).lineLimit(2) }
                    .frame(maxWidth: compact ? 170 : 340, alignment: .trailing)
                    .onTapGesture { reader.status = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ParentGateButton(action: openOptions)
        }
        .animation(.spring(response: 0.35), value: reader.status)
    }
}

/// What Braidy is doing right now.
struct StatusChip: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var listener: VoiceListener
    let listening: Bool
    let hearing: Bool

    var body: some View {
        let seeing = listening && !camera.rows.isEmpty
        let talking = listening && hearing && listener.gameTalking
        HUDChip(tint: !listening ? .gray : (talking ? Theme.violet : (seeing ? Theme.green : Theme.yellow))) {
            Image(systemName: !listening ? "pause.fill" : (talking ? "waveform" : (seeing ? "eye.fill" : "eye")))
                .symbolEffect(.pulse, isActive: listening && !seeing && !talking)
            Text(!listening ? "PAUSED" : (talking ? "GAME TALKING" : (seeing ? "READING" : "LOOKING")))
                .tracking(1)
        }
        .animation(.easeInOut(duration: 0.2), value: seeing)
        .animation(.easeInOut(duration: 0.2), value: talking)
    }
}

/// Options are for grown-ups: press and hold to open, so little fingers don't wander in.
struct ParentGateButton: View {
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var hint = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.panel.opacity(0.9))
            Circle().strokeBorder(Theme.panelEdge, lineWidth: 2)
            Circle().trim(from: 0, to: progress)
                .stroke(Theme.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            Image(systemName: "gearshape.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 48, height: 48)
        .overlay(alignment: .bottomTrailing) {
            if hint {
                Text("Hold to open")
                    .font(Theme.body(12, .bold))
                    .fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.yellow))
                    .foregroundStyle(Theme.night)
                    .offset(x: 0, y: 34)
                    .transition(.opacity)
            }
        }
        .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 30) {
            progress = 0
            Theme.success()
            action()
        } onPressingChanged: { down in
            withAnimation(down ? .linear(duration: 1.0) : .easeOut(duration: 0.2)) { progress = down ? 1 : 0 }
        }
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation { hint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { hint = false } }
        })
        .accessibilityLabel("Options, for grown-ups. Press and hold.")
    }
}

// MARK: - Dialogue box

/// The last line, shown like a game's own dialogue box: name tag, typewriter text, bouncing ▼.
struct DialogueBox: View {
    @ObservedObject var reader: Reader
    var compact: Bool
    @State private var shown = 0
    @State private var bounce = false

    private var text: String {
        reader.lastLine.isEmpty ? "Point me at the screen and I'll read the words out loud!" : reader.lastLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text((reader.lastSpeaker ?? "Braidy").uppercased())
                    .font(Theme.title(compact ? 14 : 17)).tracking(1)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.yellow))
                    .foregroundStyle(Theme.night)
                if reader.lastLineWasVoiced {
                    Label("THE GAME SAID THIS", systemImage: "speaker.wave.2.fill")
                        .font(Theme.body(12, .heavy))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.violet))
                        .foregroundStyle(.white)
                }
            }
            .offset(x: 18, y: 14)
            .zIndex(1)

            ZStack(alignment: .bottomTrailing) {
                Text(String(text.prefix(shown)))
                    .font(Theme.body(compact ? 19 : 25, .bold))
                    .foregroundStyle(reader.lastLine.isEmpty ? .white.opacity(0.7) : .white)
                    .lineLimit(compact ? 5 : 4)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 22)
                    // Reserve the full height so the box doesn't jump while typing.
                    .background(alignment: .topLeading) {
                        Text(text).font(Theme.body(compact ? 19 : 25, .bold)).lineLimit(compact ? 5 : 4)
                            .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 22).hidden()
                    }
                if shown >= text.count {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Theme.cyan)
                        .offset(y: bounce ? 2 : -4)
                        .padding(14)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { bounce = true }
                        }
                }
            }
            .gamePanel(edge: reader.isSpeaking ? Theme.cyan : Theme.panelEdge)
        }
        .frame(maxWidth: 900)
        .animation(.easeInOut(duration: 0.25), value: reader.isSpeaking)
        // Typewriter reveal, roughly at speaking pace.
        .task(id: text) {
            shown = 0
            bounce = false
            let count = text.count
            let step = max(0.012, min(0.045, 2.2 / Double(max(count, 1))))
            for i in stride(from: 0, through: count, by: 2) {
                shown = i
                try? await Task.sleep(nanoseconds: UInt64(step * 2 * 1_000_000_000))
                if Task.isCancelled { return }
            }
            shown = count
        }
    }
}

// MARK: - Controls

struct ControlBar: View {
    @ObservedObject var reader: Reader
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 14 : 26) {
            Button { reader.listening.toggle() } label: {
                VStack(spacing: 2) {
                    Image(systemName: reader.listening ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 22 : 26, weight: .black))
                    Text(reader.listening ? "PAUSE" : "GO").font(Theme.title(compact ? 11 : 13)).tracking(1)
                }
                .frame(width: compact ? 78 : 112, height: compact ? 62 : 72)
            }
            .buttonStyle(ChunkyButtonStyle(color: reader.listening ? Theme.violet : Theme.green, textColor: .white,
                                           shape: AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))))

            // The big "A" button: say it again.
            Button { reader.repeatLast() } label: {
                VStack(spacing: 0) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: compact ? 34 : 44, weight: .black))
                    Text("AGAIN").font(Theme.title(compact ? 12 : 14)).tracking(1)
                }
                .frame(width: compact ? 96 : 124, height: compact ? 96 : 124)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.pink, textColor: .white, shape: AnyShape(Circle()), depth: 8))
            .disabled(reader.lastLine.isEmpty)
            .opacity(reader.lastLine.isEmpty ? 0.6 : 1)
            .accessibilityLabel("Say it again")

            Button { reader.readNow() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "text.viewfinder").font(.system(size: compact ? 22 : 26, weight: .black))
                    Text("READ").font(Theme.title(compact ? 11 : 13)).tracking(1)
                }
                .frame(width: compact ? 78 : 112, height: compact ? 62 : 72)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.cyan, textColor: Theme.night,
                                           shape: AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))))
            .accessibilityLabel("Read what's on screen now")
        }
        .padding(.bottom, 6)
    }
}

struct EditBanner: View {
    var done: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.draw.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("Move the reading box").font(Theme.title(20)).foregroundStyle(.white)
                Text("Drag the yellow box over where the words show up. Drag the dot to resize it.")
                    .font(Theme.body(15)).foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            Button(action: done) {
                Text("DONE").font(Theme.title(16)).padding(.horizontal, 22).padding(.vertical, 12)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.yellow, textColor: Theme.night))
        }
        .padding(18)
        .frame(maxWidth: 900)
        .gamePanel(edge: Theme.yellow)
    }
}

struct PermissionOverlay: View {
    @ObservedObject var camera: CameraModel

    var body: some View {
        if camera.authorized == false {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill").font(.system(size: 46, weight: .bold)).foregroundStyle(Theme.yellow)
                Text("Braidy needs the camera to see the game's words.")
                    .font(Theme.title(22)).multilineTextAlignment(.center).foregroundStyle(.white)
                Text("Nothing is recorded or sent anywhere. The picture is read right here on this device.")
                    .font(Theme.body(16)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("OPEN SETTINGS").font(Theme.title(17)).padding(.horizontal, 24).padding(.vertical, 14)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.yellow, textColor: Theme.night))
            }
            .padding(30)
            .frame(maxWidth: 520)
            .gamePanel(edge: Theme.yellow)
            .padding()
        }
    }
}
