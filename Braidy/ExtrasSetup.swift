import SwiftUI

/// Optional extras, explained for parents: what each adds, what it costs, and exactly how to connect it.
struct ExtrasSetupView: View {
    @ObservedObject var reader: Reader

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Braidy works on its own. These two extras make it smarter and sound better. Each one connects with your own account using a **key**: a long secret code that lets Braidy use that service for you. You copy it from their website and paste it here once.")
                    .font(Theme.body(16, .medium))
                    .foregroundStyle(.white.opacity(0.9))

                ExtraCard(
                    kind: .claude,
                    title: "Smarter characters",
                    by: "with Claude, by Anthropic",
                    icon: "sparkles", color: Theme.cyan,
                    adds: [
                        "Finds any game, even brand-new ones",
                        "Knows who each character is (a giant, a tiny fairy, a grandpa) to pick voices that fit",
                        "Teaches Braidy how to say made-up names",
                        "Can recognize the game from the screen",
                    ],
                    cost: "Pay as you go. Setting up a game costs a few cents, plus about a cent when a new character appears. Reading itself costs nothing. Add $5 of credit and it lasts a long time.",
                    note: "A Claude.ai subscription (Pro or Max) can't be used here. Anthropic needs a separate developer key, made on their developer site.",
                    steps: [
                        "Tap **Open the Claude Console** below and sign in (your usual Claude email is fine).",
                        "Open **Billing** and add a little credit (keys don't work with $0).",
                        "Open **API Keys**, tap **Create Key**, and name it \u{201C}Braidy\u{201D}.",
                        "Tap **Copy**. The key starts with **sk-ant-** and is shown only once.",
                        "Come back here and tap **Paste key**.",
                    ],
                    link: URL(string: "https://platform.claude.com/settings/keys")!,
                    linkTitle: "Open the Claude Console",
                    reader: reader)

                ExtraCard(
                    kind: .eleven,
                    title: "Movie-quality voices",
                    by: "with ElevenLabs",
                    icon: "waveform.circle.fill", color: Theme.pink,
                    adds: [
                        "Natural, expressive voices instead of the device's robot-ish ones",
                        "Each character gets a voice that fits them",
                        "Every line is saved on this device, so repeats are free",
                    ],
                    cost: "Free plan: about half an hour of play a month. Starter ($6/month): about 3 to 5 hours. If you run out, Braidy switches to the device's voice.",
                    note: nil,
                    steps: [
                        "Tap **Open ElevenLabs** below and make a free account. If it asks, choose **ElevenCreative**.",
                        "Go to **Developers › API Keys** and tap **Create Key**. Name it \u{201C}Braidy\u{201D}.",
                        "Set permissions: **Text to Speech → Access** and **Voices → Read**. Leave everything else on **No access**.",
                        "Optional: set a monthly limit on the key so it can never spend more than your plan.",
                        "Tap **Copy**. The key starts with **sk_**. Come back and tap **Paste key**.",
                    ],
                    link: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
                    linkTitle: "Open ElevenLabs",
                    reader: reader)

                Text("Keys are stored in this device's secure Keychain and only ever sent to that company. See Privacy for exactly what each extra receives.")
                    .font(Theme.body(13)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ArcadeBackground())
        .navigationTitle("Extras")
        .tint(Theme.cyan)
    }
}

/// One extra: benefits, cost, step-by-step, then Paste key → instant check.
struct ExtraCard: View {
    enum Kind { case claude, eleven }
    enum Check: Equatable { case idle, checking, ok(String), failed(String) }

    let kind: Kind
    let title: String
    let by: String
    let icon: String
    let color: Color
    let adds: [String]
    let cost: String
    let note: String?
    let steps: [String]
    let link: URL
    let linkTitle: String
    @ObservedObject var reader: Reader

    @Environment(\.openURL) private var openURL
    @State private var check: Check = .idle
    @State private var showSteps = false

    private var savedKey: String { kind == .claude ? reader.apiKey : reader.elevenKey }
    private var connected: Bool { kind == .claude ? reader.hasKey : reader.hasElevenKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.night)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title(21)).foregroundStyle(.white)
                    Text(by).font(Theme.body(13)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if connected {
                    Label("ON", systemImage: "checkmark.seal.fill")
                        .font(Theme.title(14)).foregroundStyle(Theme.green)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(adds, id: \.self) { a in
                    Label(a, systemImage: "star.fill")
                        .font(Theme.body(15, .medium)).foregroundStyle(.white.opacity(0.9))
                        .labelStyle(TintedIconLabel(color: Theme.yellow))
                }
            }

            Label { Text(cost) } icon: { Image(systemName: "dollarsign.circle.fill") }
                .font(Theme.body(14, .medium)).foregroundStyle(.white.opacity(0.8))
                .labelStyle(TintedIconLabel(color: Theme.green))
            if let note {
                Label { Text(note) } icon: { Image(systemName: "info.circle.fill") }
                    .font(Theme.body(14, .medium)).foregroundStyle(.white.opacity(0.8))
                    .labelStyle(TintedIconLabel(color: Theme.cyan))
            }

            if connected {
                connectedRow
            } else {
                DisclosureGroup(isExpanded: $showSteps) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)").font(Theme.title(14)).foregroundStyle(Theme.night)
                                    .frame(width: 24, height: 24).background(Circle().fill(color))
                                Text(LocalizedStringKey(step)).font(Theme.body(15, .medium)).foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button { openURL(link) } label: {
                            Label(linkTitle, systemImage: "arrow.up.right.square.fill")
                                .font(Theme.title(16)).padding(.horizontal, 18).padding(.vertical, 12)
                        }
                        .buttonStyle(ChunkyButtonStyle(color: color, textColor: Theme.night))
                        .padding(.top, 4)
                    }
                    .padding(.top, 10)
                } label: {
                    Text("How to connect it (2 minutes)").font(Theme.title(16)).foregroundStyle(color)
                }
                pasteRow
            }
            statusLine
        }
        .padding(20)
        .gamePanel(edge: connected ? Theme.green : color)
    }

    private var pasteRow: some View {
        HStack(spacing: 12) {
            PasteButton(payloadType: String.self) { strings in
                guard let key = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
                Task { @MainActor in await verify(key) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(color)
            Text("Copy the key on their site first, then tap Paste.")
                .font(Theme.body(13)).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var connectedRow: some View {
        HStack {
            Text("Key " + masked(savedKey)).font(.system(.callout, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button("Check") { Task { @MainActor in await verify(savedKey, save: false) } }
                .font(Theme.body(15, .bold))
            Button("Remove", role: .destructive) {
                if kind == .claude { reader.apiKey = "" } else { reader.elevenKey = ""; reader.voiceEngine = "apple" }
                check = .idle
            }
            .font(Theme.body(15, .bold))
            .padding(.leading, 12)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch check {
        case .idle: EmptyView()
        case .checking:
            HStack { ProgressView(); Text("Checking the key…").font(Theme.body(14)) }
        case .ok(let msg):
            Label(msg, systemImage: "checkmark.circle.fill").font(Theme.body(15, .bold)).foregroundStyle(Theme.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").font(Theme.body(15, .bold)).foregroundStyle(Theme.yellow)
        }
    }

    private func masked(_ key: String) -> String {
        guard key.count > 10 else { return "•••" }
        return String(key.prefix(7)) + "…" + String(key.suffix(4))
    }

    @MainActor
    private func verify(_ key: String, save: Bool = true) async {
        let looksRight = kind == .claude ? key.hasPrefix("sk-ant-") : key.hasPrefix("sk_")
        guard looksRight else {
            check = .failed(kind == .claude
                ? "That doesn't look like a Claude key. It should start with sk-ant-."
                : "That doesn't look like an ElevenLabs key. It should start with sk_.")
            return
        }
        check = .checking
        do {
            if kind == .claude {
                try await ClaudeClient(apiKey: key).validate()
                if save { reader.apiKey = key }
                check = .ok("Connected! Braidy can now look up games and characters.")
            } else {
                try await ElevenClient(apiKey: key).validate()
                if save {
                    reader.elevenKey = key
                    reader.voiceEngine = "eleven"
                }
                check = .ok("Connected! Braidy will use ElevenLabs voices.")
            }
            Theme.success()
        } catch {
            check = .failed(Self.plainEnglish(error, kind: kind))
        }
    }

    static func plainEnglish(_ error: Error, kind: Kind) -> String {
        let text = error.localizedDescription
        if text.contains(" 401") || text.contains("error 401") {
            return "That key wasn't accepted. Make sure you copied the whole thing, then paste again."
        }
        if text.contains(" 403") || text.contains("error 403") {
            return kind == .eleven
                ? "The key works but is missing a permission. Give it Text to Speech: Access and Voices: Read."
                : "The key works but isn't allowed to do this. Check it's an active key."
        }
        if (error as? URLError) != nil {
            return "Couldn't reach the internet. Check Wi-Fi and try again."
        }
        return text
    }
}

struct TintedIconLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
