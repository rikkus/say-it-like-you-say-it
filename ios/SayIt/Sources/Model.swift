import Foundation

// MARK: - the quiz itself

struct Option: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

struct Question: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let options: [Option]

    func label(for optionID: String) -> String {
        options.first { $0.id == optionID }?.label ?? "—"
    }
}

enum Quiz {
    /// The 60 Standard-quiz questions, lifted verbatim from mydialect.us
    /// (Harvard Dialect Survey, Vaux & Golder, CC BY-NC-SA 3.0).
    static let questions: [Question] = {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Question].self, from: data)
        else { return [] }
        return decoded
    }()

    static let byID: [String: Question] = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
    static let order: [String] = questions.map(\.id)

    static func question(_ id: String) -> Question? { byID[id] }

    /// The payload mydialect.us expects, base64'd into ?state=
    static func submissionURL(answers: [String: String]) -> URL? {
        let payload: [String: Any] = ["answers": answers, "active_qids": order]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let encoded = json.base64EncodedString()
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "https://mydialect.us/quiz-standard.html?state=\(encoded)")
    }
}

// MARK: - what a line asks of you

/// A word-choice question: read the line, say your own word in the gap.
struct ChoiceSpec: Sendable {
    var questionID: String
    /// The last words before the gap, used to find the gap in the transcript.
    var anchor: [String]
    /// A few words on what the question was about, for the running panel.
    var gloss: String
    /// Ordered patterns; first match wins.
    var matches: [(pattern: String, option: String)]
    var fallback: String
}

/// How a pronunciation target is decided from the audio.
enum Measure: Sendable {
    /// Nearest calibrated vowel at nucleus `n` (1-based; negative counts back).
    case vowel(nucleus: Int, map: [String: String], fallback: String, label: String)
    case syllables(map: [Int: String], fallback: String)
    case sibilant(s: String, sh: String)
    case fricativeVoicing(voiceless: String, voiced: String)
    /// pecan: stress placement crossed with the second vowel
    case pecan
    /// garage: a stop closure before the final frication means an affricate
    case affricate(plain: String, affricated: String)
    /// coupon: a [j] glide before the vowel
    case yod(without: String, with: String)
    /// Craig, Monday: does the vowel travel?
    case glide(steady: String, gliding: String, steadyMap: [String: String])
    /// lawyer: does F2 rise through the first syllable?
    case risingGlide(flat: String, rising: String)
    /// route: a steady [u] or a diphthong towards "out"
    case route(hoot: String, out: String, fallback: String)
    /// almond: is there an [l]?
    case lateral(withL: String, map: [String: String], fallback: String)
    /// candidate: is the first d actually said?
    case medialStop(present: String, absent: String)
    /// asterisk: which order does the final cluster come in?
    case finalCluster(ks: String, sk: String, kOnly: String, fallback: String)
    /// huge: is the h there?
    case aspiration(present: String, absent: String)
    /// crayon: syllable count crossed with the vowel
    case crayon
    /// really: three syllables, or the quality of the first vowel
    case really
    /// Bowie: [oʊ] or [uː]
    case bowie(oh: String, oo: String)
    /// roof / room / broom / root, said in a row
    case fourWords(words: [String], allLong: String, allShort: String, mixed: String)
    /// Mary / merry / marry, said in a row
    case tripleMerger
}

struct Target: Sendable {
    var questionID: String
    /// The word to locate in the transcript.
    var word: String
    var measure: Measure
}

struct Line: Identifiable, Sendable {
    var id: String
    /// What to read aloud. A "___" marks a gap you fill yourself.
    var text: String
    var hint: String?
    var kind: Kind

    enum Kind: Sendable {
        /// Isolated reference words that pin down your vowel space.
        case calibrateVowels(symbols: [String], words: [String])
        /// sock / shock / zoo — your own sibilants.
        case calibrateSibilants
        case choice(ChoiceSpec)
        case pronounce([Target])
    }

    var questionIDs: [String] {
        switch kind {
        case .calibrateVowels, .calibrateSibilants: return []
        case .choice(let spec): return [spec.questionID]
        case .pronounce(let targets): return targets.map(\.questionID)
        }
    }

    /// Words the recogniser must find for this line to have worked.
    var requiredWords: [String] {
        switch kind {
        case .calibrateVowels(_, let words): return words
        case .calibrateSibilants: return ["sock", "shock", "zoo"]
        case .choice: return []
        case .pronounce(let targets): return targets.map(\.word)
        }
    }
}

struct Round: Identifiable, Sendable {
    var id: String
    var name: String
    var blurb: String
    var lines: [Line]
    var questionIDs: [String] { lines.flatMap(\.questionIDs) }
}

// MARK: - what comes back

/// One settled answer, as shown in the running panel.
struct PanelEntry: Identifiable, Sendable {
    let id = UUID()
    var questionID: String
    /// The word you actually said.
    var spoken: String
    /// IPA for a pronunciation question, a short gloss for a word choice.
    var detail: String
    /// The measurement in plain numbers, for the curious.
    var evidence: String
    var optionID: String
    var confident: Bool
    var isPronunciation: Bool
}
