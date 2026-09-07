import Foundation

struct Verdict: Sendable {
    var optionID: String
    /// What was heard, in IPA where that means anything.
    var ipa: String
    /// The measurement in plain numbers.
    var evidence: String
    var confidence: Double
    var confident: Bool { confidence >= 0.55 }
}

enum Analysis {

    /// Tighten a word's time range onto the actual speech inside it.
    static func region(for word: TimedWord, in rec: Recording) -> Range<Int>? {
        guard let padded = rec.range(for: word) else { return nil }
        let slice = Array(rec.samples[padded])
        let inner = DSP.segmentRegions(slice, rate: rec.rate, gapMs: 90, floorRatio: 0.12, minMs: 60)
        guard let biggest = inner.max(by: { $0.count < $1.count }) else { return padded }
        let from = padded.lowerBound + biggest.lowerBound
        let to = padded.lowerBound + biggest.upperBound
        return from < to ? from..<to : padded
    }

    static func nuclei(_ rec: Recording, _ range: Range<Int>) -> [DSP.Nucleus] {
        DSP.syllableNuclei(rec.samples, rate: rec.rate, range: range)
    }

    /// Formants around nucleus `index` (1-based, negative counts from the end).
    static func vowel(_ rec: Recording, _ range: Range<Int>, nucleus index: Int) -> DSP.VowelMeasurement? {
        let found = nuclei(rec, range)
        guard !found.isEmpty else {
            return DSP.vowel(rec.samples, rate: rec.rate, range: range)
        }
        var i = index < 0 ? found.count + index : index - 1
        i = max(0, min(found.count - 1, i))
        let half = Int(rec.rate * 0.045)
        let from = max(range.lowerBound, found[i].centre - half)
        let to = min(range.upperBound, found[i].centre + half)
        guard from < to else { return nil }
        return DSP.vowel(rec.samples, rate: rec.rate, range: from..<to)
    }

    static func hz(_ v: DSP.VowelMeasurement) -> String {
        "F1 \(Int(v.f1)) Hz · F2 \(Int(v.f2)) Hz"
    }

    // MARK: - the evaluator

    static func evaluate(_ target: Target, in rec: Recording, cal: Calibration) -> Verdict? {
        guard let word = rec.find(target.word), let range = region(for: word, in: rec) else { return nil }
        let ms = Int(Double(range.count) / rec.rate * 1000)

        switch target.measure {

        case let .vowel(nucleus, map, fallback, label):
            guard let v = vowel(rec, range, nucleus: nucleus),
                  let m = cal.nearest(f1: v.f1, f2: v.f2) else {
                return Verdict(optionID: fallback, ipa: "—", evidence: "no steady vowel in \(ms) ms", confidence: 0.15)
            }
            let runner = m.runnerUp.map { " (next closest [\($0)])" } ?? ""
            return Verdict(optionID: map[m.symbol] ?? fallback,
                           ipa: "[\(m.symbol)]",
                           evidence: "\(label) · \(hz(v)) → nearest of your own vowels [\(m.symbol)]\(runner)",
                           confidence: m.confidence)

        case let .syllables(map, fallback):
            let n = nuclei(rec, range).count
            return Verdict(optionID: map[n] ?? fallback,
                           ipa: "\(n) syll",
                           evidence: "\(n) syllable nucleus\(n == 1 ? "" : "es") across \(ms) ms",
                           confidence: n > 0 ? 0.72 : 0.2)

        case let .sibilant(sOption, shOption):
            guard let f = DSP.frication(rec.samples, rate: rec.rate, range: range) else {
                return Verdict(optionID: sOption, ipa: "—", evidence: "no frication found", confidence: 0.15)
            }
            let call = cal.sibilant(centreOfGravity: f.centreOfGravity)
            return Verdict(optionID: call.symbol == "s" ? sOption : shOption,
                           ipa: "[\(call.symbol)]",
                           evidence: "centre of gravity \(Int(f.centreOfGravity)) Hz — your [s] sits at \(Int(cal.sibilantS)), your [ʃ] at \(Int(cal.sibilantSh))",
                           confidence: call.confidence)

        case let .fricativeVoicing(voiceless, voiced):
            guard let f = DSP.frication(rec.samples, rate: rec.rate, range: range) else {
                return Verdict(optionID: voiceless, ipa: "—", evidence: "no frication found", confidence: 0.15)
            }
            let call = cal.voicing(f.voicing)
            return Verdict(optionID: call.symbol == "s" ? voiceless : voiced,
                           ipa: "[\(call.symbol)]",
                           evidence: String(format: "low-band energy through the frication %.3f — your [s] %.3f, your [z] %.3f",
                                            f.voicing, cal.voicingS, cal.voicingZ),
                           confidence: call.confidence)

        case .pecan:
            let found = nuclei(rec, range)
            guard found.count >= 2 else {
                return Verdict(optionID: "h", ipa: "—", evidence: "could not find two syllables", confidence: 0.2)
            }
            let firstStressed = found[0].level > found[1].level
            let v1 = vowel(rec, range, nucleus: 1).flatMap { cal.nearest(f1: $0.f1, f2: $0.f2) }
            let v2 = vowel(rec, range, nucleus: 2).flatMap { cal.nearest(f1: $0.f1, f2: $0.f2) }
            var option: String
            if v1?.symbol == "ɪ" {
                option = (v2?.symbol == "ɑ" || v2?.symbol == "ɒ") ? "f" : "e"
            } else if let s = v2?.symbol, s == "ɑ" || s == "ɒ" || s == "ɔ" {
                option = firstStressed ? "c" : "d"
            } else {
                option = firstStressed ? "a" : "b"
            }
            return Verdict(optionID: option,
                           ipa: "[\(v1?.symbol ?? "?")\(v2?.symbol ?? "?")] stress \(firstStressed ? "1st" : "2nd")",
                           evidence: "syllable 1 at \(Int(found[0].normalised * 100))% level, syllable 2 at \(Int(found[1].normalised * 100))%",
                           confidence: 0.5)

        case let .affricate(plain, affricated):
            let gaps = DSP.closures(rec.samples, rate: rec.rate, range: range)
                .filter { $0.position > 0.45 && $0.position < 0.92 }
            let isAffricate = !gaps.isEmpty
            return Verdict(optionID: isAffricate ? affricated : plain,
                           ipa: isAffricate ? "[dʒ]" : "[ʒ]",
                           evidence: isAffricate
                             ? "a \(Int(gaps[0].lengthMs)) ms closure before the final frication — an affricate"
                             : "frication with no stop closure before it",
                           confidence: 0.58)

        case let .yod(without, with):
            guard let v = vowel(rec, range, nucleus: 1) else {
                return Verdict(optionID: without, ipa: "—", evidence: "no clear first vowel", confidence: 0.2)
            }
            let hasYod = v.earlyF2 > v.lateF2 + 320 && v.earlyF2 > 1500
            return Verdict(optionID: hasYod ? with : without,
                           ipa: hasYod ? "[kjuː-]" : "[kuː-]",
                           evidence: "F2 starts at \(Int(v.earlyF2)) Hz and \(hasYod ? "falls to \(Int(v.lateF2)) Hz — a [j] glide" : "stays near \(Int(v.lateF2)) Hz — no [j]")",
                           confidence: 0.52)

        case let .glide(steady, gliding, steadyMap):
            guard let v = vowel(rec, range, nucleus: -1) else {
                return Verdict(optionID: steady, ipa: "—", evidence: "no clear vowel", confidence: 0.2)
            }
            if v.glide > 1.2 {
                return Verdict(optionID: gliding, ipa: "[eɪ]",
                               evidence: String(format: "%@ · travels Δ%.1f — a diphthong", hz(v), v.glide),
                               confidence: 0.6)
            }
            let m = cal.nearest(f1: v.f1, f2: v.f2)
            let symbol = m?.symbol ?? "?"
            return Verdict(optionID: steadyMap[symbol] ?? steady,
                           ipa: "[\(symbol)]",
                           evidence: "\(hz(v)) → [\(symbol)], steady",
                           confidence: (m?.confidence ?? 0.4) * 0.9)

        case let .risingGlide(flat, rising):
            guard let v = vowel(rec, range, nucleus: 1) else {
                return Verdict(optionID: flat, ipa: "—", evidence: "no clear first vowel", confidence: 0.2)
            }
            let rises = v.lateF2 > v.earlyF2 + 280
            return Verdict(optionID: rises ? rising : flat,
                           ipa: rises ? "[lɔɪ-]" : "[lɔː-]",
                           evidence: "F2 \(Int(v.earlyF2)) → \(Int(v.lateF2)) Hz — \(rises ? "a rising glide, \"loyer\"" : "flat, \"law-yer\"")",
                           confidence: 0.52)

        case let .route(hoot, out, fallback):
            guard let v = vowel(rec, range, nucleus: 1), let m = cal.nearest(f1: v.f1, f2: v.f2) else {
                return Verdict(optionID: fallback, ipa: "—", evidence: "no clear vowel", confidence: 0.2)
            }
            let diphthong = v.glide > 1.5 && v.earlyF1 > v.lateF1 + 90
            let option = diphthong ? out : (m.symbol == "u" || m.symbol == "ʊ" ? hoot : fallback)
            return Verdict(optionID: option,
                           ipa: diphthong ? "[aʊt]" : "[r\(m.symbol)t]",
                           evidence: diphthong
                             ? "F1 \(Int(v.earlyF1)) → \(Int(v.lateF1)) Hz, a strong glide — rhymes with \"out\""
                             : "\(hz(v)) → [\(m.symbol)], steady — rhymes with \"hoot\"",
                           confidence: 0.58)

        case let .lateral(withL, map, fallback):
            guard let v = vowel(rec, range, nucleus: 1) else {
                return Verdict(optionID: fallback, ipa: "—", evidence: "no clear first vowel", confidence: 0.15)
            }
            let darkL = v.lateF2 < v.earlyF2 - 140 && v.lateF2 < 1300
            if darkL {
                return Verdict(optionID: withL, ipa: "[ɑːl-]",
                               evidence: "F2 falls to \(Int(v.lateF2)) Hz — a dark [l] is in there",
                               confidence: 0.55)
            }
            let m = cal.nearest(f1: v.f1, f2: v.f2)
            let symbol = m?.symbol ?? "?"
            return Verdict(optionID: map[symbol] ?? fallback, ipa: "[\(symbol)]",
                           evidence: "\(hz(v)) → [\(symbol)]; F2 stays level — no [l]",
                           confidence: 0.5)

        case let .medialStop(present, absent):
            let gaps = DSP.closures(rec.samples, rate: rec.rate, range: range, minMs: 18)
                .filter { $0.position > 0.28 && $0.position < 0.7 }
            let there = !gaps.isEmpty
            return Verdict(optionID: there ? present : absent,
                           ipa: there ? "[kændɪdeɪt]" : "[kænɪdeɪt]",
                           evidence: there
                             ? "a \(Int(gaps[0].lengthMs)) ms stop closure after the nasal — the first d is there"
                             : "no stop closure after the nasal — the first d is dropped",
                           confidence: 0.5)

        case let .finalCluster(ks, sk, kOnly, fallback):
            guard let f = DSP.frication(rec.samples, rate: rec.rate, range: range), f.position > 0.5 else {
                return Verdict(optionID: kOnly, ipa: "[…k]", evidence: "no sibilant in the final cluster", confidence: 0.4)
            }
            let gaps = DSP.closures(rec.samples, rate: rec.rate, range: range).filter { $0.position > 0.6 }
            let stopAfterHiss = gaps.contains { $0.position > f.position }
            _ = fallback
            return Verdict(optionID: stopAfterHiss ? sk : ks,
                           ipa: stopAfterHiss ? "[…sk]" : "[…ks]",
                           evidence: "final sibilant at \(Int(f.position * 100))% of the word; stop closure \(stopAfterHiss ? "after" : "before") it",
                           confidence: 0.45)

        case let .aspiration(present, absent):
            let found = nuclei(rec, range)
            guard let first = found.first else {
                return Verdict(optionID: absent, ipa: "—", evidence: "no vowel found", confidence: 0.2)
            }
            let onsetRange = range.lowerBound..<min(first.centre, range.upperBound)
            guard onsetRange.count > Int(rec.rate * 0.02) else {
                return Verdict(optionID: absent, ipa: "[juːdʒ]", evidence: "no room for an [h] before the vowel", confidence: 0.45)
            }
            let onsetMs = Double(onsetRange.count) / rec.rate * 1000
            let breathy = DSP.frication(rec.samples, rate: rec.rate, range: onsetRange) != nil
            let there = onsetMs > 55 && breathy
            return Verdict(optionID: there ? present : absent,
                           ipa: there ? "[hjuːdʒ]" : "[juːdʒ]",
                           evidence: "\(Int(onsetMs)) ms before the vowel\(breathy ? ", broadband — an [h] is being made" : ", no broadband friction")",
                           confidence: 0.48)

        case .crayon:
            let found = nuclei(rec, range)
            let n = found.count
            guard let v = vowel(rec, range, nucleus: n >= 2 ? 2 : 1),
                  let m = cal.nearest(f1: v.f1, f2: v.f2) else {
                return Verdict(optionID: "e", ipa: "\(n) syll", evidence: "syllables counted, vowel unclear", confidence: 0.25)
            }
            if n <= 1 {
                return Verdict(optionID: v.glide > 1.4 ? "d" : "a", ipa: "[\(m.symbol)]",
                               evidence: "one syllable · \(hz(v))", confidence: 0.5)
            }
            let option = m.symbol == "ɑ" ? "b" : ((m.symbol == "ɒ" || m.symbol == "ɔ") ? "c" : "e")
            return Verdict(optionID: option, ipa: "[eɪ\(m.symbol)]",
                           evidence: "\(n) syllables · second vowel \(hz(v)) → [\(m.symbol)]",
                           confidence: m.confidence * 0.9)

        case .really:
            let n = nuclei(rec, range).count
            if n >= 3 {
                return Verdict(optionID: "c", ipa: "[iːəli]", evidence: "three syllable nuclei — \"ree-uh-ly\"", confidence: 0.55)
            }
            guard let v = vowel(rec, range, nucleus: 1), let m = cal.nearest(f1: v.f1, f2: v.f2) else {
                return Verdict(optionID: "d", ipa: "—", evidence: "no clear first vowel", confidence: 0.2)
            }
            let map = ["i": "a", "ɪ": "b"]
            return Verdict(optionID: map[m.symbol] ?? "d", ipa: "[\(m.symbol)]",
                           evidence: "first vowel \(hz(v)) → [\(m.symbol)]", confidence: m.confidence)

        case let .bowie(oh, oo):
            guard let v = vowel(rec, range, nucleus: 1),
                  let m = cal.nearest(f1: v.f1, f2: v.f2, restrictedTo: ["u", "ʊ", "ɔ", "ɒ", "ɑ", "ʌ"]) else {
                return Verdict(optionID: oh, ipa: "—", evidence: "no clear first vowel", confidence: 0.2)
            }
            let isOo = m.symbol == "u" || m.symbol == "ʊ"
            return Verdict(optionID: isOo ? oo : oh,
                           ipa: isOo ? "[buːi]" : "[bəʊi]",
                           evidence: "\(hz(v)) → nearest [\(m.symbol)]",
                           confidence: m.confidence * 0.85)

        case .fourWords, .tripleMerger:
            return nil   // handled as a whole line, not a single word
        }
    }

    // MARK: - lines measured as a set

    /// roof / room / broom / root — do they all share a vowel?
    static func fourWords(_ rec: Recording, words: [String], cal: Calibration,
                          allLong: String, allShort: String, mixed: String) -> Verdict? {
        var symbols: [String] = []
        var bits: [String] = []
        for name in words {
            guard let w = rec.find(name), let r = region(for: w, in: rec),
                  let v = DSP.vowel(rec.samples, rate: rec.rate, range: r),
                  let m = cal.nearest(f1: v.f1, f2: v.f2, restrictedTo: ["u", "ʊ", "ʌ", "ɜ", "ɔ"]) else {
                bits.append("\(name) —")
                continue
            }
            symbols.append(m.symbol)
            bits.append("\(name) [\(m.symbol)] \(Int(v.f1))/\(Int(v.f2))")
        }
        guard symbols.count == words.count else { return nil }
        let unique = Set(symbols)
        let option = unique.count > 1 ? mixed : (symbols[0] == "u" ? allLong : (symbols[0] == "ʊ" ? allShort : mixed))
        return Verdict(optionID: option,
                       ipa: symbols.map { "[\($0)]" }.joined(separator: " "),
                       evidence: bits.joined(separator: " · "),
                       confidence: unique.count > 1 ? 0.6 : 0.65)
    }

    /// Mary / merry / marry — which of them, if any, are the same for you?
    static func tripleMerger(_ rec: Recording, cal: Calibration) -> Verdict? {
        let names = ["mary", "merry", "marry"]
        var measured: [Calibration.Vowel] = []
        var bits: [String] = []
        for name in names {
            guard let w = rec.find(name), let r = region(for: w, in: rec),
                  let v = DSP.vowel(rec.samples, rate: rec.rate, range: r) else { return nil }
            measured.append(Calibration.Vowel(f1: v.f1, f2: v.f2))
            bits.append("\(name) \(Int(v.f1))/\(Int(v.f2))")
        }
        let maryMerry = cal.sameVowel(measured[0], measured[1])
        let merryMarry = cal.sameVowel(measured[1], measured[2])
        let maryMarry = cal.sameVowel(measured[0], measured[2])

        let option: String
        if maryMerry.same && merryMarry.same { option = "a" }
        else if maryMerry.same { option = "c" }
        else if merryMarry.same { option = "d" }
        else if maryMarry.same { option = "e" }
        else { option = "b" }

        return Verdict(optionID: option,
                       ipa: "\(maryMerry.same ? "=" : "≠") \(merryMarry.same ? "=" : "≠")",
                       evidence: String(format: "%@ Hz — gaps of %.2f and %.2f Bark against a %.2f threshold",
                                        bits.joined(separator: " · "),
                                        maryMerry.distance, merryMarry.distance, maryMerry.threshold),
                       confidence: min(maryMerry.confidence, merryMarry.confidence))
    }

    /// cot / caught, straight out of calibration.
    static func cotCaught(_ cal: Calibration) -> Verdict? {
        guard let cot = cal.vowels["ɒ"], let caught = cal.vowels["ɔ"] else { return nil }
        let s = cal.sameVowel(cot, caught)
        return Verdict(optionID: s.same ? "b" : "a",
                       ipa: s.same ? "[kɒt] = [kɒt]" : "[kɒt] ≠ [kɔːt]",
                       evidence: String(format: "cot %d/%d Hz vs caught %d/%d Hz — %.2f Bark apart, and %.2f is your own threshold for \"different\"",
                                        Int(cot.f1), Int(cot.f2), Int(caught.f1), Int(caught.f2),
                                        s.distance, s.threshold),
                       confidence: s.confidence)
    }
}
