import SwiftUI
import UIKit

/// Braidy's look: a night-sky arcade. Deep indigo panels, chunky rounded type, neon accents,
/// buttons that press down like real controller buttons.
enum Theme {
    static let night = Color(red: 0.07, green: 0.04, blue: 0.18)      // backdrop
    static let panel = Color(red: 0.13, green: 0.08, blue: 0.30)      // dialogue box, cards
    static let panelEdge = Color(red: 0.42, green: 0.34, blue: 0.85)
    static let cyan = Color(red: 0.24, green: 0.96, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.31, blue: 0.72)
    static let yellow = Color(red: 1.00, green: 0.85, blue: 0.30)
    static let green = Color(red: 0.36, green: 1.00, blue: 0.62)
    static let violet = Color(red: 0.58, green: 0.42, blue: 1.00)

    static let backdrop = LinearGradient(colors: [Color(red: 0.10, green: 0.05, blue: 0.26), night,
                                                  Color(red: 0.20, green: 0.05, blue: 0.24)],
                                         startPoint: .top, endPoint: .bottom)

    /// Chunky arcade type.
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// A button that sits on a darker "base" and squashes down when pressed, with a haptic tap.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.cyan
    var textColor: Color = Theme.night
    var shape: AnyShape = AnyShape(Capsule())
    var depth: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(textColor)
            .background(shape.fill(color.gradient))
            .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 2).padding(1).mask(
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .background(shape.fill(color.opacity(0.55).shadow(.inner(color: .black.opacity(0.5), radius: 2)))
                .offset(y: pressed ? 1 : depth))
            .offset(y: pressed ? depth - 1 : 0)
            .shadow(color: color.opacity(0.45), radius: pressed ? 4 : 12)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
            .onChange(of: pressed) { _, isDown in if isDown { Theme.tap(.light) } }
    }
}

/// A dark panel with a glowing edge, like a game's dialogue box or menu card.
struct GamePanel: ViewModifier {
    var edge: Color = Theme.panelEdge
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.panel.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(edge, lineWidth: 3))
                    .overlay(RoundedRectangle(cornerRadius: radius - 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 2).padding(5))
                    .shadow(color: edge.opacity(0.35), radius: 14)
            )
    }
}

extension View {
    func gamePanel(edge: Color = Theme.panelEdge, radius: CGFloat = 22) -> some View {
        modifier(GamePanel(edge: edge, radius: radius))
    }
}

/// Twinkling pixel stars behind menus.
struct StarField: View {
    var count = 70

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                var rng = SeededRandom(seed: 7)
                for _ in 0..<count {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    let s = 2 + rng.next() * 3
                    let phase = rng.next() * 6.28
                    let a = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * (0.6 + rng.next()) + phase))
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// The full menu background: gradient night sky with stars.
struct ArcadeBackground: View {
    var body: some View {
        ZStack {
            Theme.backdrop
            StarField()
        }
        .ignoresSafeArea()
    }
}

/// A small rounded badge, like a HUD chip.
struct HUDChip<Content: View>: View {
    var tint: Color = Theme.panelEdge
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(Theme.body(14, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.panel.opacity(0.88)))
            .overlay(Capsule().strokeBorder(tint, lineWidth: 2))
    }
}
