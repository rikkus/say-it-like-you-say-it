import SwiftUI

/// The main screen: one line at a time, what the recogniser is hearing as you
/// say it, and a running panel of everything settled so far.
struct PlayView: View {
    let model: GameModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var listening = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 20) {
                    main.frame(maxWidth: .infinity)
                    PanelList(model: model)
                        .frame(width: 330)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        main
                        PanelList(model: model)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Spacer(minLength: 0)
            LineCard(line: model.line, listening: listening)

            if listening {
                TranscriptView(engine: model.engine)
            }

            if let outcome = model.outcome {
                OutcomeCard(outcome: outcome, model: model)
            }

            Spacer(minLength: 0)

            if model.outcome == nil {
                MicButton(listening: listening, level: model.engine.level, verb: micVerb) {
                    if listening {
                        listening = false
                        Task { await model.finishSpeaking() }
                    } else {
                        listening = true
                        Task { await model.startSpeaking() }
                    }
                }
                if !listening && model.canGoBack {
                    Button("Back a line") { model.goBack() }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Calibration lines are word lists, not sentences.
    private var micVerb: String {
        switch model.line.kind {
        case .calibrateVowels, .calibrateSibilants: return "Speak the words"
        case .choice, .pronounce: return "Speak the line"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: model.round.name)
                Spacer()
                Eyebrow(text: "line \(model.lineIndex + 1) of \(model.round.lines.count)")
            }
            ProgressView(value: Double(model.answeredCount), total: 60)
                .tint(.settledAccent)
            if model.lineIndex == 0 {
                Text(model.round.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - the line to read

struct LineCard: View {
    let line: Line
    let listening: Bool

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(line.text)
                    .font(.reading(listening ? 26 : 29))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = line.hint {
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                } else if case .choice = line.kind {
                    Text("Read it out, and say your own word where it stops.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if case .pronounce = line.kind {
                    Text("Just read it, at a normal pace.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(listening ? Color.liveAccent : Color.clear)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

// MARK: - live transcript

struct TranscriptView: View {
    let engine: SpeechEngine

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "hearing")
                Group {
                    if engine.settledText.isEmpty && engine.volatileText.isEmpty {
                        Text("go ahead…").foregroundStyle(.tertiary)
                    } else {
                        (Text(engine.settledText).foregroundStyle(.primary)
                         + Text(engine.volatileText.isEmpty ? "" : " " + engine.volatileText)
                            .foregroundStyle(.tertiary))
                    }
                }
                .font(.reading(20))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.default, value: engine.settledText)
            }
        }
    }
}

// MARK: - what came of it

struct OutcomeCard: View {
    let outcome: LineOutcome
    let model: GameModel

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                if let note = outcome.note {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(Color.warnAccent)
                } else if !outcome.missing.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("I didn't catch \(list(outcome.missing))",
                              systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(Color.warnAccent)
                        Text("Nothing has been recorded for \(outcome.missing.count == 1 ? "it" : "those"). Say the line again — a bit slower is usually enough.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !outcome.heard.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "heard")
                        Text(outcome.heard).font(.reading(17)).foregroundStyle(.secondary)
                    }
                }

                ForEach(outcome.entries) { entry in
                    EntryRow(entry: entry)
                }

                HStack(spacing: 10) {
                    Button("Say it again") { model.retry() }
                        .font(.label(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

                    Button(outcome.worked ? "Next" : "Keep it anyway") { model.advance() }
                        .font(.label(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(outcome.worked ? Color.settledAccent : Color(uiColor: .tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(outcome.worked ? .white : .primary)
                        .disabled(outcome.entries.isEmpty && outcome.note != nil)
                        .opacity(outcome.entries.isEmpty && outcome.note != nil ? 0.4 : 1)
                }
                .padding(.top, 2)
            }
        }
    }

    private func list(_ words: [String]) -> String {
        if words.count == 1 { return "“\(words[0])”" }
        let quoted = words.map { "“\($0)”" }
        return quoted.dropLast().joined(separator: ", ") + " or " + quoted.last!
    }
}

struct EntryRow: View {
    let entry: PanelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.spoken).font(.reading(19))
                Text(entry.detail)
                    .font(entry.isPronunciation ? .data(17) : .callout)
                    .foregroundStyle(entry.isPronunciation ? Color.settledAccent : .secondary)
                Spacer()
                if !entry.confident {
                    Text("check").font(.data(10)).tracking(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.warnAccent.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.warnAccent)
                }
            }
            Text(entry.evidence)
                .font(.data(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - the running panel

struct PanelList: View {
    let model: GameModel

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "what you've said")
                    Spacer()
                    Text("\(model.answeredCount)/60").font(.data(12)).foregroundStyle(.secondary)
                }
                if model.panel.isEmpty {
                    Text("Your words and pronunciations collect here as you go.")
                        .font(.footnote).foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.panel.reversed()) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.spoken)
                                        .font(.reading(16))
                                        .lineLimit(1)
                                    Text(entry.detail)
                                        .font(entry.isPronunciation ? .data(14) : .caption)
                                        .foregroundStyle(entry.isPronunciation ? Color.settledAccent : .secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                }
            }
        }
    }
}

// MARK: - the microphone

struct MicButton: View {
    let listening: Bool
    let level: Float
    var verb: String = "Speak the line"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if listening {
                        Circle()
                            .fill(.white.opacity(0.28))
                            .frame(width: 26 + CGFloat(level) * 22, height: 26 + CGFloat(level) * 22)
                            .animation(.easeOut(duration: 0.1), value: level)
                    }
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(width: 48, height: 26)
                Text(listening ? "Done — that's me" : verb)
                    .font(.label(17))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(listening ? Color.liveAccent : Color.liveAccent.opacity(0.92), in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
