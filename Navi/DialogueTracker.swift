import Foundation

/// Decides when a dialogue box has finished appearing and whether it is new.
///
/// Games reveal dialogue a few letters at a time, and OCR from a camera jitters frame to frame.
/// So a line is "settled" once several consecutive reads agree closely and the text has stopped
/// growing. A settled line is spoken once; later reads of the same box are ignored. When the box
/// goes away for a while, the memory clears so a repeated line can be read again.
struct DialogueTracker {
    /// Consecutive matching reads needed before speaking (~0.4–0.6 s at the camera's analysis rate).
    var framesToSettle = 3
    /// Blank reads after which the last spoken line is forgotten.
    var framesToForget = 20

    private var candidate = ""
    private var settledCount = 0
    private var blankCount = 0
    private(set) var lastSpoken = ""

    /// Feed one frame's body text. Returns text to speak when a new line settles.
    mutating func ingest(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = Self.normalize(text)
        if norm.count < 4 {
            blankCount += 1
            candidate = ""
            settledCount = 0
            if blankCount >= framesToForget { lastSpoken = "" }
            return nil
        }
        blankCount = 0

        let candNorm = Self.normalize(candidate)
        let growing = norm.count > candNorm.count + 2
        if !candidate.isEmpty && !growing && Self.similarity(norm, candNorm) >= 0.9 {
            settledCount += 1
            candidate = text
        } else {
            candidate = text
            settledCount = 1
        }
        guard settledCount == framesToSettle else { return nil }
        return commit(candidate)
    }

    /// Record a line that was spoken by hand ("Read now") so it isn't repeated automatically.
    mutating func markSpoken(_ text: String) {
        lastSpoken = text
    }

    private mutating func commit(_ text: String) -> String? {
        let n = Self.normalize(text)
        let l = Self.normalize(lastSpoken)
        if !l.isEmpty && Self.similarity(n, l) >= 0.8 { return nil }
        let previous = lastSpoken
        lastSpoken = text

        // A line that paused mid-reveal and then carried on: say only the new words.
        let newWords = text.split(separator: " ").map(String.init)
        let oldWords = previous.split(separator: " ")
        if oldWords.count >= 3, newWords.count > oldWords.count {
            let head = newWords.prefix(oldWords.count).joined(separator: " ")
            if Self.similarity(Self.normalize(head), l) >= 0.85 {
                return newWords.dropFirst(oldWords.count).joined(separator: " ")
            }
        }
        return text
    }

    // MARK: - Text comparison

    /// Lowercased letters and digits, single-spaced.
    static func normalize(_ s: String) -> String {
        var out = ""
        var lastWasSpace = true
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// 1 − normalized Levenshtein distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        var cur = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}
