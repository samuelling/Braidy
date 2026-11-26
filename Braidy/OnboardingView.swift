import SwiftUI

/// First-run setup, written for a parent: what Braidy does, where to put the device, privacy,
/// permissions (explained before iOS asks), the game, optional extras, then placing the reading box.
struct OnboardingView: View {
    @ObservedObject var reader: Reader
    /// Called when done; true means "go straight to placing the reading box".
    var finish: (Bool) -> Void

    @State private var page = 0
    @State private var askedPermissions = false
    @State private var showPicker = false
    @State private var showExtras = false
    @State private var showPrivacy = false
    private let pages = 7

    var body: some View {
        ZStack {
            ArcadeBackground()
            VStack(spacing: 0) {
                HStack {
                    ProgressDots(count: pages, current: page)
                    Spacer()
                    if page < pages - 1 {
                        Button("Skip") { finish(false) }
                            .font(Theme.body(16, .bold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24).padding(.top, 18)

                TabView(selection: $page) {
                    welcome.tag(0)
                    howItWorks.tag(1)
                    setUpSpot.tag(2)
                    privacy.tag(3)
                    permissions.tag(4)
                    chooseGame.tag(5)
                    ready.tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                bottomBar
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            NavigationStack { PlatformPickerView(reader: reader) }
                .fontDesign(.rounded).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showExtras) {
            NavigationStack {
                ExtrasSetupView(reader: reader)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showExtras = false } } }
            }
            .fontDesign(.rounded).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivacy = false } } }
            }
            .fontDesign(.rounded).preferredColorScheme(.dark)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardPage {
            Image("Mascot").resizable().scaledToFit().frame(width: 170, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: Theme.cyan.opacity(0.5), radius: 24)
                .bounceIn()
            Text("Hi, I'm Braidy!").font(Theme.title(40)).foregroundStyle(Theme.yellow)
            Text("I read the words in video games out loud, so kids who are still learning to read can play on their own.")
                .font(Theme.body(20)).multilineTextAlignment(.center).foregroundStyle(.white)
            Text("Setup takes about two minutes.").font(Theme.body(16)).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var howItWorks: some View {
        OnboardPage(title: "How it works") {
            HStack(spacing: 10) {
                StepTile(icon: "tv.fill", color: Theme.cyan, text: "Words show up in the game")
                Arrow()
                StepTile(icon: "camera.viewfinder", color: Theme.yellow, text: "Braidy sees them through the camera")
                Arrow()
                StepTile(icon: "speaker.wave.3.fill", color: Theme.pink, text: "…and reads them out loud")
            }
            Text("Each character gets their own voice. When the game's own actors are talking, Braidy stays quiet. Tap the big pink button to hear a line again.")
                .font(Theme.body(17)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
        }
    }

    private var setUpSpot: some View {
        OnboardPage(title: "Find a good spot") {
            HStack(spacing: 28) {
                Image(systemName: "ipad.landscape").font(.system(size: 64, weight: .regular)).foregroundStyle(Theme.cyan)
                Image(systemName: "arrow.right").font(.system(size: 30, weight: .black)).foregroundStyle(.white.opacity(0.6))
                Image(systemName: "tv").font(.system(size: 80, weight: .regular)).foregroundStyle(Theme.yellow)
            }
            .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 12) {
                Check("Prop this device up so the **whole TV screen** is in view (a stand or a stack of books works).")
                Check("Keep it **steady**. Next to your child is perfect.")
                Check("Close enough to **hear the TV**, so Braidy knows when the game is talking.")
                Check("Avoid **lamps or windows** reflecting in the TV.")
                Check("For long play, keep it **plugged in**. The screen stays on.")
            }
        }
    }

    private var privacy: some View {
        OnboardPage(title: "Your privacy") {
            Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 12) {
                Check("Everything happens **on this device**.")
                Check("The camera picture and sound are **never recorded or saved**.")
                Check("**No accounts, no ads, no tracking.** Your child never types anything.")
                Check("Optional extras send only what they need, and **only if you turn them on**.")
            }
            Button("Read the full details") { showPrivacy = true }
                .font(Theme.body(17, .bold)).foregroundStyle(Theme.cyan)
        }
    }

    private var permissions: some View {
        OnboardPage(title: "Two quick permissions") {
            PermissionCards(camera: reader.camera, listener: reader.listener, asked: askedPermissions)
            if !askedPermissions {
                Button {
                    askedPermissions = true
                    reader.start()
                } label: {
                    Text("TURN ON CAMERA & MIC").font(Theme.title(18)).padding(.horizontal, 26).padding(.vertical, 15)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.green, textColor: Theme.night))
            } else {
                Text("You can change these any time in the device's Settings app.")
                    .font(Theme.body(14)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var chooseGame: some View {
        OnboardPage(title: "What are you playing?") {
            if reader.game.isEmpty {
                Text("Pick the console, then the game. Braidy remembers settings for each game.")
                    .font(Theme.body(18)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green)
                    Text(reader.game).font(Theme.title(22)).foregroundStyle(.white)
                }
                .padding(18).gamePanel(edge: Theme.green)
            }
            Button { showPicker = true } label: {
                Label(reader.game.isEmpty ? "CHOOSE THE GAME" : "CHANGE GAME", systemImage: "gamecontroller.fill")
                    .font(Theme.title(18)).padding(.horizontal, 24).padding(.vertical, 15)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.yellow, textColor: Theme.night))
            Text("Not sure? Skip it. Braidy reads any game.").font(Theme.body(14)).foregroundStyle(.white.opacity(0.6))

            VStack(alignment: .leading, spacing: 8) {
                Text("Want it even better? (optional)").font(Theme.title(17)).foregroundStyle(Theme.pink)
                Text("Extras add smarter character voices (Claude) and movie-quality voices (ElevenLabs). They need accounts with those companies, and you can set them up now or later in Options › Extras.")
                    .font(Theme.body(15)).foregroundStyle(.white.opacity(0.8))
                Button("Set up extras") { showExtras = true }
                    .font(Theme.body(16, .bold)).foregroundStyle(Theme.cyan)
            }
            .padding(18)
            .gamePanel(edge: Theme.pink)
        }
    }

    private var ready: some View {
        OnboardPage(title: "Last step!") {
            Image(systemName: "rectangle.dashed").font(.system(size: 72, weight: .bold)).foregroundStyle(Theme.yellow)
                .overlay(Image(systemName: "text.alignleft").font(.system(size: 30, weight: .bold)).foregroundStyle(.white))
            Text("Show Braidy where the words appear. You'll drag a yellow box over the part of the TV where the game's text shows up.")
                .font(Theme.body(19)).multilineTextAlignment(.center).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 10) {
                Check("Grown-ups: **press and hold** the gear to open Options.")
                Check("Kids: the big **pink button** says it again.")
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            if page > 0 {
                Button { page -= 1 } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .black)).frame(width: 56, height: 56)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.panelEdge, textColor: .white, shape: AnyShape(Circle())))
            }
            Spacer()
            Button {
                if page < pages - 1 { page += 1 } else { finish(true) }
            } label: {
                Text(nextTitle).font(Theme.title(20)).padding(.horizontal, 34).padding(.vertical, 16)
            }
            .buttonStyle(ChunkyButtonStyle(color: page == pages - 1 ? Theme.yellow : Theme.cyan, textColor: Theme.night))
            .disabled(page == 4 && !askedPermissions)
            .opacity(page == 4 && !askedPermissions ? 0.5 : 1)
        }
        .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 8)
    }

    private var nextTitle: String {
        switch page {
        case 0: return "LET'S GO!"
        case pages - 1: return "PLACE THE BOX"
        default: return "NEXT"
        }
    }
}

// MARK: - Pieces

struct OnboardPage<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let title {
                    Text(title).font(Theme.title(32)).foregroundStyle(Theme.yellow).multilineTextAlignment(.center)
                }
                content
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct ProgressDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Theme.yellow : .white.opacity(0.25))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3), value: current)
    }
}

struct StepTile: View {
    let icon: String
    let color: Color
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.night)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color.gradient))
            Text(text).font(Theme.body(14, .bold)).multilineTextAlignment(.center).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Arrow: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 18, weight: .black)).foregroundStyle(.white.opacity(0.5))
    }
}

struct Check: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 20))
            Text(LocalizedStringKey(text)).font(Theme.body(17, .medium)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let color: Color
    let title: String
    let why: String
    /// nil = not asked yet, true = allowed, false = declined.
    let state: Bool?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.night)
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(Theme.title(19)).foregroundStyle(.white)
                    Spacer()
                    switch state {
                    case .some(true): Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    case .some(false): Label("Off", systemImage: "xmark.circle.fill").foregroundStyle(Theme.yellow)
                    case .none: EmptyView()
                    }
                }
                .font(Theme.body(15, .bold))
                Text(why).font(Theme.body(15, .medium)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .gamePanel(edge: color)
    }
}

/// A springy entrance for the mascot.
struct BounceIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { shown = true } }
    }
}

extension View {
    func bounceIn() -> some View { modifier(BounceIn()) }
}

/// Observes the camera and microphone so the On/Off marks update as iOS answers.
struct PermissionCards: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var listener: VoiceListener
    let asked: Bool

    var body: some View {
        VStack(spacing: 14) {
            PermissionCard(icon: "camera.fill", color: Theme.cyan, title: "Camera",
                           why: "To see the words on the TV. The picture is read on this device and never saved.",
                           state: camera.authorized)
            PermissionCard(icon: "mic.fill", color: Theme.violet, title: "Microphone",
                           why: "Only to hear when the game itself is talking, so Braidy doesn't talk over it. Nothing is recorded.",
                           state: asked ? listener.available : nil)
        }
    }
}
