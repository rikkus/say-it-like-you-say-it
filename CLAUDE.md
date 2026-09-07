# Say It Like You Say It

A spoken front end to the [mydialect.us](https://mydialect.us) dialect quiz. The
player reads short lines aloud; the page measures the audio, derives IPA, picks
the quiz answers, and hands all 60 to the real quiz page.

## Shape of the thing

One file: `index.html`. No build step, no dependencies except Google Fonts.
Deployed to GitHub Pages. Keep it that way — the single file is the point, and
it has to run from `file://`, from Pages, and inside a Claude artifact iframe.

The source is organised as seven `<script>` blocks in reading order:

1. `DSP` — FFT, RMS envelope, silence segmentation, syllable nuclei, decimation,
   LPC formants, frication statistics, closure detection. Pure functions over
   `Float32Array`; no DOM, no browser APIs. This is the part worth unit testing.
2. `Q` / `QORDER` — the 60 Standard-quiz questions, generated verbatim from
   `dialect-data-survey.js` in <https://github.com/tjstum/dialect>. The Standard
   set is `QUESTIONS.filter(q => q.hq !== undefined).slice(0, 60)`. Do not edit
   by hand; regenerate if the upstream data changes.
3. `H` / `vowelVerdict` / `syllVerdict` — helpers that turn a measurement into an
   option id plus an IPA reading, a human-readable detail string and a
   confidence in 0..1.
4. `ROUNDS` — the script the player reads. 13 rounds. Each line is either a
   word-choice line (`q`, `pre`, `post`, `match`, `dflt`) resolved from the
   speech-recognition transcript, or a pronunciation line (`say`, `word`,
   `targets`) resolved from the audio. Each target owns an `fn(ctx)`.
5. Audio capture and speech recognition.
6. Analysis dispatch and all UI rendering.
7. Flow control, submission, boot.

## The central idea

Round 0 is calibration: eleven reference words plus *sock / shock / zoo*. That
builds `App.cal.vowels` (F1/F2 per IPA symbol) and `App.cal.sib` (the speaker's
own [s] and [ʃ] centres of gravity, and voicing ratios for [s] and [z]).

Every later judgement is **speaker-relative** — nearest calibrated vowel in Bark
space, sibilants against that speaker's own pair. This is why it works for a
northern English speaker on an American quiz, and it also cancels systematic
bias in the formant estimator: a low-F1 vowel measures ~20% high, but so does
the calibration anchor it is compared against.

Two questions fall straight out of calibration: `q_28` (cot/caught) and `q_15`
(Mary/merry/marry), both by inter-vowel distance against a threshold derived
from the speaker's own vowel spread.

## Constraints that bit, and must not be undone

- **Targets are phrase-final.** Pronunciation lines end `— word.` so the target
  is the last region after silence segmentation. There is no forced aligner;
  this is what replaces one. Do not move a target into the middle of a line.
- **iOS hands the microphone to one consumer at a time.** Word lines run speech
  recognition with the recording stream released; pronunciation lines record
  with recognition aborted. Never both at once. No question needs both.
- **Speech recognition is Safari's, not WebKit's.** It is absent or throws
  `service-not-allowed` in Chrome/Firefox/Edge for iOS and in-app browsers, and
  it silently returns nothing in Home Screen standalone mode. `NOT_SAFARI`
  detects the shell; `ASR.onerror` demotes to tap-to-answer for the rest of the
  run rather than stalling for 14 s a line.
- **iOS only opens the microphone from a gesture**, hence `TAP_TO_START`.
- **`ScriptProcessorNode`, not `AudioWorklet`.** A worklet needs `addModule` on a
  blob URL, which the artifact CSP blocks.
- **No `color-mix()` in canvas `fillStyle`** — it is silently ignored. Theme
  colours are parsed from the CSS custom properties to rgba.
- The submission URL must `encodeURIComponent` the base64, or `+` decodes as a
  space in `URLSearchParams` and `atob` fails upstream.

## Submitting

`https://mydialect.us/quiz-standard.html?state=<encodeURIComponent(btoa(JSON))>`
where the payload is `{answers: {qid: optionId}, active_qids: [...]}`. The site
rebuilds the quiz from `active_qids` and scores whatever answers are present, so
a partial run still draws a map.

## Testing

The DSP layer is testable headlessly: extract the script blocks, synthesise
vowels with a source-filter model (impulse train through two resonators) and
check formant recovery, syllable counts and sibilant separation. The last run
recovered 9 of 11 synthetic vowels within 12%, counted 1/2/3-syllable words
correctly, and separated s-like (6280 Hz) from sh-like (4143 Hz) centres of
gravity. Anything touching the microphone needs a real browser.

## Credits

Questions and scoring from mydialect.us by Tim Stumbaugh and Jenil Kansara,
built on the Harvard Dialect Survey (Bert Vaux & Scott Golder), CC BY-NC-SA 3.0.
