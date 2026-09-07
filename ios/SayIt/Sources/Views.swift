import SwiftUI

struct RootView: View {
    @State private var model: GameModel

    init() {
        let model = GameModel()
        // A way to open the app straight on a screen, for looking at layout
        // without talking to it. Harmless in normal use.
        if CommandLine.arguments.contains("-startPlaying") { model.stage = .playing }
        if CommandLine.arguments.contains("-startPractice") { model.stage = .practice }
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.stage {
            case .welcome:      WelcomeView(model: model)
            case .gettingReady: GettingReadyView(model: model)
            case .practice:     PracticeView(model: model)
            case .playing:      PlayView(model: model)
            case .finished:     FinishedView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.stage)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - welcome

struct WelcomeView: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Eyebrow(text: "Harvard Dialect Survey · spoken")
            Text("Say It Like\nYou Say It")
                .font(.system(size: 44, weight: .bold, design: .default))
                .kerning(-1)
                .padding(.top, 6)
            Text("The dialect quiz normally asks you to pick answers off a list. This one asks you to talk.")
                .font(.reading(19))
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            Text("You'll read short lines aloud. Where the word is yours to choose, the line leaves a gap. Everything is measured on this iPad — nothing is uploaded.")
                .font(.reading(17))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            Spacer(minLength: 0)
            Button {
                Task { await model.begin() }
            } label: {
                Text("Begin")
                    .font(.label(18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(.liveAccent)
            Text("It asks for the microphone next, and may download a voice model once.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(28)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - getting ready

struct GettingReadyView: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 18) {
            switch model.engine.phase {
            case .unavailable(let why):
                Image(systemName: "mic.slash").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Can't listen").font(.label(20))
                Text(why).font(.reading(16)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .preparing(let what):
                ProgressView().controlSize(.large)
                Text(what).font(.reading(17)).foregroundStyle(.secondary)
            default:
                ProgressView().controlSize(.large)
                Text("Getting ready…").font(.reading(17)).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: 480)
    }
}

// MARK: - practice

struct PracticeView: View {
    let model: GameModel
    @State private var listening = false

    private var heardSomething: Bool {
        !(model.practiceHeard ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "First, a quick check")
            Text("Say one word")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 6)
            Text("Tap the button, say **bee**, then tap it again. Nothing is being scored — this is just to see that the microphone is reaching me.")
                .font(.reading(17))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Text("bee")
                .font(.reading(52))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 34)

            if let heard = model.practiceHeard {
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: heardSomething ? "I heard" : "I heard nothing")
                        Text(heardSomething ? heard : "silence")
                            .font(.reading(24))
                            .foregroundStyle(heardSomething ? Color.settledAccent : Color.warnAccent)
                        if !heardSomething {
                            Text("Check the mute switch and that nothing else is using the microphone, then try once more.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 14)
            }

            Spacer(minLength: 0)

            MicButton(listening: listening, level: model.engine.level, verb: "Say the word") {
                if listening {
                    listening = false
                    Task { await model.finishPractice() }
                } else {
                    listening = true
                    Task { await model.startSpeaking() }
                }
            }

            if heardSomething {
                Button("That's working — start the quiz") { model.leavePractice() }
                    .font(.label(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.settledAccent, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 10)
            } else {
                Button("Skip this") { model.leavePractice() }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(28)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - finished

struct FinishedView: View {
    let model: GameModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Done")
            Text("\(model.answeredCount) of 60 answered")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 6)
            Text("These go to mydialect.us, which draws the map. It opens in Safari.")
                .font(.reading(17)).foregroundStyle(.secondary).padding(.top, 10)

            PanelList(model: model)
                .padding(.top, 18)

            Spacer(minLength: 0)

            Button {
                if let url = model.submissionURL { openURL(url) }
            } label: {
                Text("See my map")
                    .font(.label(18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(.settledAccent)
            .disabled(model.submissionURL == nil)
        }
        .padding(24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}
