import CoreGraphics
import Foundation

/// One line of text recognized on screen, top-to-bottom order.
struct TextRow: Equatable {
    var text: String
    /// Normalized to the camera image, top-left origin.
    var box: CGRect
    /// Which block of text this line belongs to (a dialogue box, a choice list…), in reading order.
    var block: Int = 0

    /// Lines in reading order, with a sentence break between blocks so speech pauses
    /// between, say, the dialogue and the choices next to it.
    static func joined<S: Sequence>(_ rows: S) -> String where S.Element == TextRow {
        var out = ""
        var lastBlock: Int?
        for r in rows {
            if out.isEmpty {
                out = r.text
            } else if r.block != lastBlock {
                let ended = out.last.map { ".!?…:".contains($0) } ?? true
                out += (ended ? " " : ". ") + r.text
            } else {
                out += " " + r.text
            }
            lastBlock = r.block
        }
        return out
    }
}

/// Splits a dialogue box into its speaker label and body.
///
/// Zelda (and many other games) print the speaker's name on a short line above the dialogue.
/// The first row counts as a name if it matches a known character for the current game, or if
/// it looks like one: short, capitalized, no sentence punctuation, and narrower than the text
/// beneath it.
enum SpeakerParser {
    static func split(_ rows: [TextRow], knownNames: [String]) -> (speaker: String?, body: String) {
        let all = TextRow.joined(rows)
        guard rows.count >= 2 else { return (nil, all) }

        var first = rows[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.hasSuffix(":") { first.removeLast() }
        let body = TextRow.joined(rows.dropFirst())
        let firstNorm = DialogueTracker.normalize(first)
        guard !firstNorm.isEmpty else { return (nil, all) }

        // 1. Matches a character we already know for this game.
        for name in knownNames {
            let n = DialogueTracker.normalize(name)
            if !n.isEmpty, DialogueTracker.similarity(firstNorm, n) >= 0.8 {
                return (name, body)
            }
        }

        // 2. Looks like a name label.
        let words = first.split(separator: " ")
        let connectors: Set<String> = ["the", "of", "de", "von", "and"]
        let capitalized = words.allSatisfy { w in
            connectors.contains(w.lowercased()) || (w.first?.isUppercase ?? false)
        }
        let punctuation = CharacterSet(charactersIn: ".,!?…")
        let hasPunctuation = first.unicodeScalars.contains { punctuation.contains($0) }
        let narrow = rows[1].block == rows[0].block && rows[0].box.width < rows[1].box.width * 0.6
        if words.count <= 3, first.count <= 24, capitalized, !hasPunctuation, narrow {
            return (first, body)
        }
        return (nil, all)
    }
}
