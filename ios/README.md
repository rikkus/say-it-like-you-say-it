# Say It — the iPad app

The native version, and the reason for it: on iOS a web page gets the microphone
for *one* consumer at a time, so the browser version has to choose between
hearing your words and recording your voice. Here one `AVAudioEngine` tap feeds
both a live `SpeechTranscriber` and a raw PCM buffer at once.

The second win is timing. `SpeechTranscriber` with `attributeOptions:
[.audioTimeRange]` returns per-word time ranges, so a target word can be found
anywhere inside a passage. The web version had to put every measured word at the
end of a phrase, because energy segmentation was the only way to locate it.

## Building

```
cd ios
xcodegen generate          # project.yml is the source of truth, not the .xcodeproj
open SayIt.xcodeproj
```

Pick your team under Signing & Capabilities, choose your iPad, run. Needs iOS 26
or later — `SpeechAnalyzer` is the whole point.

Command line, for the simulator:

```
xcodebuild -project SayIt.xcodeproj -scheme SayIt \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -derivedDataPath /tmp/sayit-dd CODE_SIGNING_ALLOWED=NO build
```

`-startPlaying` and `-startPractice` as launch arguments open the app straight on
those screens, for looking at layout without talking to it.

## Layout

| file | what it holds |
|---|---|
| `DSP.swift` | formants, sibilant centre of gravity, voicing, syllable nuclei, closures — on Accelerate. Pure functions over `[Float]`. |
| `Calibration.swift` | your own vowel space and sibilants; everything else is judged relative to it |
| `Verdicts.swift` | one measurement per question type → an option id, an IPA reading, the numbers behind it, a confidence |
| `SpeechEngine.swift` | the one-microphone-two-consumers wiring |
| `AudioBridge.swift` | the only thing the real-time audio thread touches |
| `Model.swift` | questions, lines, rounds, the submission URL |
| `ScriptWordChoice.swift` | the rounds where the word is yours |
| `ScriptPronunciation.swift` | calibration, and the rounds where the sound is the point |
| `GameModel.swift` | the state machine — and the rule that nothing advances without a tap |
| `PlayView.swift`, `Views.swift`, `Style.swift` | the interface |

`Resources/questions.json` is generated from
[tjstum/dialect](https://github.com/tjstum/dialect), not written by hand.

## Rules that must not be undone

- **Nothing advances on its own.** Every line ends with what was heard, what was
  decided, and two buttons. If a required word wasn't recognised the app says so
  by name and records nothing for it. The web version's silence detector guessed,
  and guessed wrong.
- **The audio thread touches only `AudioBridge`.** Under Swift 6 strict
  concurrency the tap closure must capture locals and nothing main-actor.
- **Convert every buffer to the analyser's format.** A mismatch compiles cleanly
  and transcribes nothing at all.
- **Calibration is the yardstick.** Judging vowels against the speaker's own
  space is what makes an American quiz answerable in a northern English accent,
  and it cancels the formant estimator's systematic bias.
