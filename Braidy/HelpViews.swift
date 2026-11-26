import SwiftUI

/// One illustrated row: icon tile, title, explanation.
struct ExplainRow: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.night)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.title(18)).foregroundStyle(.white)
                Text(text).font(Theme.body(15, .medium)).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HowItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Braidy watches the game screen through the camera and reads the words out loud, like a friend sitting next to your child.")
                    .font(Theme.body(17)).foregroundStyle(.white.opacity(0.9))
                ExplainRow(icon: "camera.viewfinder", color: Theme.cyan, title: "1 · Look",
                           text: "Several times a second, the camera picture inside the yellow reading box is turned into text by Apple's built-in text recognition, right on this device.")
                ExplainRow(icon: "hourglass", color: Theme.yellow, title: "2 · Wait for the whole line",
                           text: "Games type words out a letter at a time, so Braidy waits until the text stops changing, then reads it once. It won't repeat a line unless you tap AGAIN.")
                ExplainRow(icon: "person.2.wave.2.fill", color: Theme.pink, title: "3 · Who's talking?",
                           text: "Many games show the speaker's name above the words. Braidy spots it and gives each character their own voice. Text is read left to right, so answers to choose from come after the question.")
                ExplainRow(icon: "speaker.wave.3.fill", color: Theme.green, title: "4 · Speak",
                           text: "Lines are read with the device's own voices (free), or with ElevenLabs' natural voices if you turn that extra on.")
                ExplainRow(icon: "waveform", color: Theme.violet, title: "5 · Don't talk over the game",
                           text: "When a game has voice actors, Braidy hears them through the microphone and stays quiet, showing the words instead. The sound is only checked for \"is someone talking?\", never recorded.")
                ExplainRow(icon: "sparkles", color: Theme.cyan, title: "6 · Learn the game (optional)",
                           text: "With the Claude extra, Braidy looks up the game's characters (who's a giant, who's a tiny fairy) to pick fitting voices, and learns how to say made-up names.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips for the best results").font(Theme.title(18)).foregroundStyle(Theme.yellow)
                    Text("• Prop the device where it can see the whole TV, steady and level.\n• Move the reading box to cover only where words appear, so maps and menus aren't read.\n• Avoid lamps or windows reflecting in the TV.\n• If it's far away, use Zoom in Options.\n• Grown-ups: press and hold the gear to open Options.")
                        .font(Theme.body(15, .medium)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(18)
                .gamePanel(edge: Theme.yellow)
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ArcadeBackground())
        .navigationTitle("How Braidy works")
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The short version").font(Theme.title(22)).foregroundStyle(Theme.green)
                    Text("Braidy works entirely on this device. Nothing is recorded, nothing is sent to us, and there are no accounts, ads or tracking. The optional extras only send what they need, and only if you turn them on.")
                        .font(Theme.body(17)).foregroundStyle(.white)
                }
                .padding(18)
                .gamePanel(edge: Theme.green)

                Text("ON THIS DEVICE ONLY").font(Theme.title(14)).tracking(1.5).foregroundStyle(Theme.yellow)
                ExplainRow(icon: "camera.fill", color: Theme.cyan, title: "Camera",
                           text: "The picture is read for words right here, a few times a second, and then thrown away. It's never saved or sent anywhere.")
                ExplainRow(icon: "mic.fill", color: Theme.violet, title: "Microphone",
                           text: "Used only to tell whether the game is speaking, so Braidy doesn't talk over it. Apple's on-device sound check answers \"speech or not?\". Audio is never recorded, saved or sent.")
                ExplainRow(icon: "internaldrive.fill", color: Theme.pink, title: "What's kept",
                           text: "Your settings, the reading box and character list for each game, and (with ElevenLabs) the saved audio of lines already read. You can clear the saved audio in Options. Deleting the app removes everything.")
                ExplainRow(icon: "person.crop.circle.badge.xmark", color: Theme.green, title: "No accounts, ads or tracking",
                           text: "Braidy has no sign-up, no analytics, no ads and no tracking. Your child never types anything into it.")

                Text("ONLY IF YOU TURN ON AN EXTRA").font(Theme.title(14)).tracking(1.5).foregroundStyle(Theme.yellow)
                ExplainRow(icon: "sparkles", color: Theme.cyan, title: "Claude (by Anthropic)",
                           text: "Receives the game's name, character names Braidy sees on screen, and anything you type in the game search. If you tap \"Ask Claude which game is on screen\", one camera picture is sent for that question. The words being read aloud are never sent to Claude.")
                ExplainRow(icon: "waveform.circle.fill", color: Theme.pink, title: "ElevenLabs",
                           text: "Receives the text of each line so it can turn it into speech. The audio comes back and is saved on this device, so the same line isn't sent twice. ElevenLabs may keep a history of generated audio in your ElevenLabs account. If you design custom character voices, it also receives each voice's written description, and the voices are saved in your ElevenLabs account until you remove them.")
                ExplainRow(icon: "key.fill", color: Theme.yellow, title: "Your keys",
                           text: "The keys that connect the extras are stored in this device's secure Keychain and only ever sent to that company. Remove them any time in Options › Extras.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Those companies' own privacy policies apply to what they receive:")
                        .font(Theme.body(14)).foregroundStyle(.white.opacity(0.8))
                    Link("Anthropic privacy policy", destination: URL(string: "https://www.anthropic.com/legal/privacy")!)
                    Link("ElevenLabs privacy policy", destination: URL(string: "https://elevenlabs.io/privacy-policy")!)
                }
                .font(Theme.body(15, .bold))
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ArcadeBackground())
        .navigationTitle("Privacy")
        .tint(Theme.cyan)
    }
}
