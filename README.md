# Say It Like You Say It

A spoken front end to the [mydialect.us](https://mydialect.us) dialect quiz.

The quiz normally asks you to pick answers off a list. This asks you to talk. You
read short lines aloud; where the word is up to you the line leaves a gap, and you
say whatever you'd actually say.

## What it measures

It opens with a calibration round — *bee, bit, bet, bat / bar, cot, caught, but /
book, boot, bird / sock, shock, zoo / Mary, merry, marry* — which maps your own
vowel space and your own sibilants. Everything after that is judged relative to
**your** vowels rather than a General American yardstick, and your cot/caught and
Mary/merry/marry answers fall straight out of it.

Then, per question:

| signal | technique | questions |
|---|---|---|
| sibilant place | spectral centre of gravity vs your own *sock* / *shock* | anniversary, grocery, nursery |
| frication voicing | low-band energy vs your own *sock* / *zoo* | chromosome, Presley |
| syllable count | peak picking on the 250–1100 Hz energy envelope | caramel, mayonnaise, mischievous, poem, crayon |
| vowel quality | LPC envelope formants, nearest calibrated vowel in Bark space | aunt, been, creek, route, Florida, syrup, … |
| glide / diphthong | F1–F2 trajectory across the nucleus | Craig, lawyer, coupon, Monday |
| stop closures | energy dips inside the word | garage, candidate, almond |

Each verdict shows the IPA and the raw numbers, reads itself back over
text-to-speech, and is flagged **confident** or **check this**. Any answer can be
overridden with a tap. At the end all 60 answers are base64-encoded into
`quiz-standard.html?state=…` and handed to the real quiz page, which draws the map.

## Running it

It is one static HTML file with no build step and no dependencies beyond Google
Fonts. Open `index.html` over HTTPS.

- **Chrome on desktop or Android** is the best case: microphone and speech
  recognition both work and the flow runs hands-free.
- **iPhone and iPad: use Safari itself.** Every iOS browser is WebKit underneath
  — Chrome for iOS is a wrapper, not Blink — but the Web Speech API belongs to
  Safari rather than to WebKit, so it is absent or errors with
  `service-not-allowed` in Chrome, Firefox, Edge and in-app browsers. The page
  detects this and drops the word questions to a tap; the 36 pronunciation
  questions still work anywhere, because they are measured from the audio
  through `getUserMedia`, which WKWebView does expose.
  In Safari, also: don't add it to the Home Screen (speech recognition reports
  itself available in standalone mode and then never returns a word), enable
  Settings → General → Keyboard → Dictation, and expect to tap to begin each
  line — iOS only opens the microphone from a gesture, and hands it to one
  consumer at a time, which is why word lines listen and pronunciation lines
  record but never both at once.

  (The UK CMA ruled in March 2026 that Apple must allow alternative engines by
  1 January 2027. Nothing has shipped yet, so for now this is the situation.)
- **Firefox on desktop** has no speech recognition, so word questions need a
  tap. The pronunciation half still works.

There is also a tap-only mode for when there is no microphone at all.

## Credits

Questions and scoring from [mydialect.us](https://mydialect.us) by Tim Stumbaugh
and Jenil Kansara, built on the Harvard Dialect Survey (Bert Vaux & Scott Golder),
CC BY-NC-SA 3.0.
