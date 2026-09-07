import Foundation
import Observation

/// What one spoken line produced. Nothing advances until this says it worked,
/// or until you decide it did.
struct LineOutcome: Sendable {
    var heard: String
    var entries: [PanelEntry]
    var missing: [String]
    var note: String?

    var worked: Bool { missing.isEmpty && note == nil && !entries.isEmpty }
}

@MainActor
@Observable
final class GameModel {

    enum Stage: Equatable {
        case welcome
        case gettingReady
        case practice
        case playing
        case finished
    }

    var stage: Stage = .welcome
    var roundIndex = 0
    var lineIndex = 0

    private(set) var answers: [String: String] = [:]
    private(set) var panel: [PanelEntry] = []
    private(set) var calibration = Calibration()
    private(set) var outcome: LineOutcome?
    private(set) var practiceHeard: String?

    let engine = SpeechEngine()

    var round: Round { Script.rounds[min(roundIndex, Script.rounds.count - 1)] }
    var line: Line { round.lines[min(lineIndex, round.lines.count - 1)] }
    var isLastLineOfRound: Bool { lineIndex >= round.lines.count - 1 }
    var answeredCount: Int { answers.count }

    var canGoBack: Bool { roundIndex > 0 || lineIndex > 0 }

    // MARK: - flow

    func begin() async {
        stage = .gettingReady
        await engine.prepare()
        if case .ready = engine.phase { stage = .practice }
    }

    func startSpeaking() async {
        outcome = nil
        engine.discard()
        try? await engine.startListening()
    }

    /// Practice: one word, just to prove the microphone and the recogniser work.
    func finishPractice() async {
        let recording = await engine.stopListening()
        practiceHeard = recording.words.map(\.text).joined(separator: " ")
    }

    func leavePractice() {
        stage = .playing
        roundIndex = 0
        lineIndex = 0
        outcome = nil
    }

    func finishSpeaking() async {
        let recording = await engine.stopListening()
        outcome = process(line: line, recording: recording)
    }

    /// Accept the outcome and move on. Only ever called by a tap.
    func advance() {
        if let outcome {
            for entry in outcome.entries {
                answers[entry.questionID] = entry.optionID
                panel.removeAll { $0.questionID == entry.questionID }
                panel.append(entry)
            }
        }
        outcome = nil
        engine.discard()

        if lineIndex < round.lines.count - 1 {
            lineIndex += 1
        } else if roundIndex < Script.rounds.count - 1 {
            roundIndex += 1
            lineIndex = 0
        } else {
            stage = .finished
        }
    }

    /// Throw the attempt away and stay exactly where you are.
    func retry() {
        outcome = nil
        engine.discard()
    }

    func goBack() {
        outcome = nil
        engine.discard()
        if lineIndex > 0 {
            lineIndex -= 1
        } else if roundIndex > 0 {
            roundIndex -= 1
            lineIndex = round.lines.count - 1
        }
        for id in line.questionIDs {
            answers.removeValue(forKey: id)
            panel.removeAll { $0.questionID == id }
        }
    }

    /// Change an answer by hand, from the panel.
    func override(questionID: String, optionID: String) {
        answers[questionID] = optionID
        if let index = panel.firstIndex(where: { $0.questionID == questionID }) {
            panel[index].optionID = optionID
            panel[index].confident = true
        }
    }

    var submissionURL: URL? { Quiz.submissionURL(answers: answers) }

    // MARK: - turning a recording into answers

    private func process(line: Line, recording: Recording) -> LineOutcome {
        let heard = recording.words.map(\.text).joined(separator: " ")

        guard recording.spokeAtAll else {
            return LineOutcome(heard: heard, entries: [], missing: [],
                               note: "I didn't hear anything that time. Nothing has been recorded — have another go.")
        }

        switch line.kind {

        case let .calibrateVowels(symbols, words):
            var missing: [String] = []
            var entries: [PanelEntry] = []
            for (symbol, word) in zip(symbols, words) {
                guard let found = recording.find(word),
                      let range = Analysis.region(for: found, in: recording),
                      let v = DSP.vowel(recording.samples, rate: recording.rate, range: range) else {
                    missing.append(word)
                    continue
                }
                calibration.record(symbol: symbol, f1: v.f1, f2: v.f2)
                entries.append(PanelEntry(questionID: "cal-\(symbol)", spoken: word,
                                          detail: "[\(symbol)]",
                                          evidence: "F1 \(Int(v.f1)) Hz · F2 \(Int(v.f2)) Hz",
                                          optionID: "", confident: true, isPronunciation: true))
            }
            // cot and caught arrive together, and answer a question between them
            var note: String?
            if symbols.contains("ɒ"), symbols.contains("ɔ"), missing.isEmpty,
               let verdict = Analysis.cotCaught(calibration) {
                entries.append(entry(for: "q_28", spoken: "cot / caught", verdict: verdict, pronunciation: true))
            }
            if !missing.isEmpty {
                note = nil
            }
            return LineOutcome(heard: heard, entries: entries, missing: missing, note: note)

        case .calibrateSibilants:
            var missing: [String] = []
            var entries: [PanelEntry] = []
            let wanted = ["sock", "shock", "zoo"]
            var measured: [String: DSP.FricationMeasurement] = [:]
            for word in wanted {
                guard let found = recording.find(word),
                      let range = Analysis.region(for: found, in: recording),
                      let f = DSP.frication(recording.samples, rate: recording.rate, range: range) else {
                    missing.append(word)
                    continue
                }
                measured[word] = f
            }
            if let sock = measured["sock"] { calibration.sibilantS = sock.centreOfGravity; calibration.voicingS = sock.voicing }
            if let shock = measured["shock"] { calibration.sibilantSh = shock.centreOfGravity }
            if let zoo = measured["zoo"] { calibration.voicingZ = zoo.voicing }
            if missing.isEmpty {
                entries.append(PanelEntry(questionID: "cal-sib", spoken: "sock / shock / zoo",
                                          detail: "[s] [ʃ] [z]",
                                          evidence: "your [s] \(Int(calibration.sibilantS)) Hz · your [ʃ] \(Int(calibration.sibilantSh)) Hz",
                                          optionID: "", confident: true, isPronunciation: true))
            }
            return LineOutcome(heard: heard, entries: entries, missing: missing, note: nil)

        case let .choice(spec):
            guard let question = Quiz.question(spec.questionID) else {
                return LineOutcome(heard: heard, entries: [], missing: [], note: "Question missing.")
            }
            let span = spanAfter(anchor: spec.anchor, in: recording.words)
            let haystack = " " + span.map(\.normalised).joined(separator: " ") + " "
            var chosen: String?
            var matchedOn: String?
            for match in spec.matches {
                if let range = haystack.range(of: match.pattern, options: [.regularExpression]) {
                    chosen = match.option
                    matchedOn = String(haystack[range]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            let spokenWords = span.map(\.text).joined(separator: " ")
            if span.isEmpty {
                return LineOutcome(heard: heard, entries: [], missing: [],
                                   note: "I couldn't find your word in that. Try the line again, and pause a beat before the word you choose.")
            }
            let optionID = chosen ?? spec.fallback
            let entry = PanelEntry(
                questionID: spec.questionID,
                spoken: matchedOn ?? spokenWords,
                detail: spec.gloss,
                evidence: chosen != nil
                    ? "matched “\(matchedOn ?? "")” → \(question.label(for: optionID))"
                    : "not one of the American options — filed under \(question.label(for: optionID))",
                optionID: optionID,
                confident: chosen != nil,
                isPronunciation: false)
            return LineOutcome(heard: heard, entries: [entry], missing: [], note: nil)

        case let .pronounce(targets):
            var entries: [PanelEntry] = []
            var missing: [String] = []
            for target in targets {
                switch target.measure {
                case let .fourWords(words, allLong, allShort, mixed):
                    let absent = words.filter { recording.find($0) == nil }
                    if !absent.isEmpty { missing.append(contentsOf: absent); continue }
                    if let verdict = Analysis.fourWords(recording, words: words, cal: calibration,
                                                        allLong: allLong, allShort: allShort, mixed: mixed) {
                        entries.append(entry(for: target.questionID, spoken: words.joined(separator: " / "),
                                             verdict: verdict, pronunciation: true))
                    } else {
                        missing.append(contentsOf: words)
                    }
                case .tripleMerger:
                    let names = ["Mary", "merry", "marry"]
                    let absent = names.filter { recording.find($0) == nil }
                    if !absent.isEmpty { missing.append(contentsOf: absent); continue }
                    if let verdict = Analysis.tripleMerger(recording, cal: calibration) {
                        entries.append(entry(for: target.questionID, spoken: names.joined(separator: " / "),
                                             verdict: verdict, pronunciation: true))
                    } else {
                        missing.append(contentsOf: names)
                    }
                default:
                    guard recording.find(target.word) != nil else {
                        missing.append(target.word)
                        continue
                    }
                    guard let verdict = Analysis.evaluate(target, in: recording, cal: calibration) else {
                        missing.append(target.word)
                        continue
                    }
                    entries.append(entry(for: target.questionID, spoken: target.word,
                                         verdict: verdict, pronunciation: true))
                }
            }
            return LineOutcome(heard: heard, entries: entries, missing: missing, note: nil)
        }
    }

    private func entry(for questionID: String, spoken: String, verdict: Verdict, pronunciation: Bool) -> PanelEntry {
        PanelEntry(questionID: questionID, spoken: spoken, detail: verdict.ipa,
                   evidence: verdict.evidence, optionID: verdict.optionID,
                   confident: verdict.confident, isPronunciation: pronunciation)
    }

    /// The words that follow the anchor phrase — where your own choice lives.
    private func spanAfter(anchor: [String], in words: [TimedWord]) -> [TimedWord] {
        guard !words.isEmpty else { return [] }
        let normalisedAnchor = anchor.map { TimedWord.normalise($0) }.filter { !$0.isEmpty }
        guard !normalisedAnchor.isEmpty else { return Array(words.suffix(4)) }

        var bestEnd: Int?
        var index = 0
        while index + normalisedAnchor.count <= words.count {
            let window = words[index..<(index + normalisedAnchor.count)].map(\.normalised)
            if window == normalisedAnchor { bestEnd = index + normalisedAnchor.count }
            index += 1
        }
        // fall back on just the last anchor word
        if bestEnd == nil, let last = normalisedAnchor.last,
           let position = words.lastIndex(where: { $0.normalised == last }) {
            bestEnd = position + 1
        }
        guard let start = bestEnd, start < words.count else {
            return Array(words.suffix(4))
        }
        return Array(words[start...].prefix(6))
    }
}
