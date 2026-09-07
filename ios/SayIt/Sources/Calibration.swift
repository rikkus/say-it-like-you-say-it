import Foundation

/// Your own vowel space and your own sibilants.
///
/// Everything the game decides is relative to this rather than to a General
/// American yardstick — which is what lets a northern English speaker take an
/// American quiz honestly, and what cancels the systematic bias in the formant
/// estimator, since the reference and the measurement go through the same code.
struct Calibration: Sendable {

    struct Vowel: Sendable {
        var f1: Double
        var f2: Double
    }

    var vowels: [String: Vowel] = [:]
    var sibilantS: Double = 6200      // centre of gravity of your [s]
    var sibilantSh: Double = 3300     // …and your [ʃ]
    var voicingS: Double = 0.06       // low-band share through your [s]
    var voicingZ: Double = 0.30       // …and your [z]
    /// Median distance between your own vowels — the yardstick for "these two are the same".
    var spread: Double = 3

    static let referenceWords: [String: String] = [
        "i": "bee", "ɪ": "bit", "ɛ": "bet", "æ": "bat", "ɑ": "bar", "ɒ": "cot",
        "ɔ": "caught", "ʌ": "but", "ʊ": "book", "u": "boot", "ɜ": "bird"
    ]

    var isUsable: Bool { vowels.count >= 8 }

    mutating func record(symbol: String, f1: Double, f2: Double) {
        vowels[symbol] = Vowel(f1: f1, f2: f2)
        recomputeSpread()
    }

    mutating func recomputeSpread() {
        let all = Array(vowels.values)
        guard all.count > 2 else { return }
        var distances: [Double] = []
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                distances.append(DSP.vowelDistance(f1a: all[i].f1, f2a: all[i].f2,
                                                   f1b: all[j].f1, f2b: all[j].f2))
            }
        }
        distances.sort()
        spread = distances[distances.count / 2]
    }

    struct Match: Sendable {
        var symbol: String
        var distance: Double
        var runnerUp: String?
        var confidence: Double
    }

    /// Which of your own vowels is this closest to?
    func nearest(f1: Double, f2: Double, restrictedTo allowed: [String]? = nil) -> Match? {
        let candidates = vowels.filter { allowed?.contains($0.key) ?? true }
        guard !candidates.isEmpty else { return nil }
        var best: (String, Double)?
        var second: (String, Double)?
        for (symbol, v) in candidates {
            let d = DSP.vowelDistance(f1a: f1, f2a: f2, f1b: v.f1, f2b: v.f2)
            if best == nil || d < best!.1 {
                second = best
                best = (symbol, d)
            } else if second == nil || d < second!.1 {
                second = (symbol, d)
            }
        }
        guard let best else { return nil }
        let margin = second.map { ($0.1 - best.1) / max(0.4, best.1) } ?? 1
        return Match(symbol: best.0, distance: best.1, runnerUp: second?.0,
                     confidence: min(1, 0.35 + margin * 0.5))
    }

    struct Sameness: Sendable {
        var same: Bool
        var distance: Double
        var threshold: Double
        var confidence: Double
    }

    /// Are these two vowels the same one, for this speaker?
    func sameVowel(_ a: Vowel, _ b: Vowel) -> Sameness {
        let d = DSP.vowelDistance(f1a: a.f1, f2a: a.f2, f1b: b.f1, f2b: b.f2)
        let threshold = max(0.75, 0.30 * spread)
        return Sameness(same: d < threshold, distance: d, threshold: threshold,
                        confidence: min(1, 0.35 + abs(d - threshold) / threshold * 0.6))
    }

    /// [s] or [ʃ], judged against your own pair rather than a fixed cutoff.
    func sibilant(centreOfGravity cog: Double) -> (symbol: String, confidence: Double) {
        let midpoint = (sibilantS + sibilantSh) / 2
        let symbol = cog > midpoint ? "s" : "ʃ"
        let spreadHz = max(400, abs(sibilantS - sibilantSh))
        return (symbol, min(1, 0.4 + abs(cog - midpoint) / spreadHz * 0.9))
    }

    /// [s] or [z], against your own sock/zoo pair.
    func voicing(_ ratio: Double) -> (symbol: String, confidence: Double) {
        let midpoint = (voicingS + voicingZ) / 2
        let symbol = ratio > midpoint ? "z" : "s"
        let range = max(0.05, abs(voicingZ - voicingS))
        return (symbol, min(1, 0.4 + abs(ratio - midpoint) / range * 0.8))
    }
}
