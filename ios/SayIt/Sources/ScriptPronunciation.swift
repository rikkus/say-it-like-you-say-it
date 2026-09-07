import Foundation

/// Calibration, and the rounds where it's the sound that matters rather than the
/// word. Word timings from the recogniser locate each target inside the passage,
/// so these can be ordinary sentences rather than everything wedged onto the end.
enum PronunciationRounds {

    static func say(_ id: String, _ text: String, _ targets: [Target], hint: String? = nil) -> Line {
        Line(id: id, text: text, hint: hint, kind: .pronounce(targets))
    }
    static func vowel(_ q: String, _ word: String, nucleus: Int, _ map: [String: String],
                      fallback: String, label: String) -> Target {
        Target(questionID: q, word: word,
               measure: .vowel(nucleus: nucleus, map: map, fallback: fallback, label: label))
    }
    static func syllables(_ q: String, _ word: String, _ map: [Int: String], fallback: String) -> Target {
        Target(questionID: q, word: word, measure: .syllables(map: map, fallback: fallback))
    }

    // MARK: - calibration

    static let calibration = Round(
        id: "calibration", name: "Tuning to your voice",
        blurb: "Eleven words that map your own vowels, and three that map your s and sh. Say each one on its own, with a clear beat between them.",
        lines: [
            Line(id: "cal1", text: "bee · bit · bet · bat",
                 hint: "Four separate words, a beat between each.",
                 kind: .calibrateVowels(symbols: ["i", "ɪ", "ɛ", "æ"], words: ["bee", "bit", "bet", "bat"])),
            Line(id: "cal2", text: "bar · cot · caught · but",
                 hint: "Four more. Cot and caught matter — say them as you'd normally say them.",
                 kind: .calibrateVowels(symbols: ["ɑ", "ɒ", "ɔ", "ʌ"], words: ["bar", "cot", "caught", "but"])),
            Line(id: "cal3", text: "book · boot · bird",
                 hint: "Three separate words.",
                 kind: .calibrateVowels(symbols: ["ʊ", "u", "ɜ"], words: ["book", "boot", "bird"])),
            Line(id: "cal4", text: "sock · shock · zoo",
                 hint: "These set your s, sh and z references.",
                 kind: .calibrateSibilants),
            Line(id: "cal5", text: "Mary · merry · marry",
                 hint: "Three separate words, however they come out.",
                 kind: .pronounce([Target(questionID: "q_15", word: "mary", measure: .tripleMerger)]))
        ])

    // MARK: - the pronunciation rounds

    static let all: [Round] = [

        Round(id: "sibilants", name: "Sibilants",
              blurb: "Ordinary sentences now — read them straight through. The underlined words are the ones being measured.",
              lines: [
                say("sib1", "Ten years married today, so happy anniversary to us.",
                    [Target(questionID: "q_30", word: "anniversary", measure: .sibilant(s: "a", sh: "b"))]),
                say("sib2", "In America they don't say supermarket, they say grocery store.",
                    [Target(questionID: "q_36", word: "grocery", measure: .sibilant(s: "a", sh: "b"))]),
                say("sib3", "The room where the baby sleeps is the nursery.",
                    [Target(questionID: "q_38", word: "nursery", measure: .sibilant(s: "a", sh: "b"))]),
                say("sib4", "Every cell keeps its DNA coiled up in a chromosome.",
                    [Target(questionID: "q_33", word: "chromosome",
                            measure: .fricativeVoicing(voiceless: "a", voiced: "b"))]),
                say("sib5", "The King of Rock and Roll was Elvis Presley.",
                    [Target(questionID: "q_39", word: "presley",
                            measure: .fricativeVoicing(voiceless: "a", voiced: "b"))]),
                say("sib6", "I keep the car in the garage.",
                    [Target(questionID: "q_35", word: "garage",
                            measure: .affricate(plain: "a", affricated: "b"))])
              ]),

        Round(id: "clusters", name: "Clusters and hidden consonants",
              blurb: "Five sentences. Say them at a normal pace — the point is how you say them when you aren't thinking about it.",
              lines: [
                say("cl1", "The little star symbol on the keyboard is an asterisk.",
                    [Target(questionID: "q_31", word: "asterisk",
                            measure: .finalCluster(ks: "a", sk: "b", kOnly: "c", fallback: "d"))]),
                say("cl2", "Standing for election makes you a candidate.",
                    [Target(questionID: "q_32", word: "candidate",
                            measure: .medialStop(present: "a", absent: "b"))]),
                say("cl3", "And so on and so on, et cetera, et cetera.",
                    [syllables("q_34", "cetera", [4: "a", 3: "b", 2: "b"], fallback: "e")],
                    hint: "Say it in full — not \"etc\"."),
                say("cl4", "That is not just big, that is huge.",
                    [Target(questionID: "q_37", word: "huge",
                            measure: .aspiration(present: "a", absent: "b"))]),
                say("cl5", "The nut you find inside marzipan is an almond.",
                    [Target(questionID: "q_29", word: "almond",
                            measure: .lateral(withL: "a", map: ["ɑ": "b", "ɔ": "c", "ɒ": "c"], fallback: "e"))])
              ]),

        Round(id: "syllables", name: "Counting syllables",
              blurb: "How many beats you give each word is the whole question here.",
              lines: [
                say("sy1", "Boiled sugar and butter, chewy and golden — caramel.",
                    [syllables("q_4", "caramel", [2: "a", 3: "b"], fallback: "e")]),
                say("sy2", "The pale sauce that goes on chips is mayonnaise.",
                    [syllables("q_16", "mayonnaise", [2: "a", 3: "b"], fallback: "d")]),
                say("sy3", "The cat is up to no good again, thoroughly mischievous.",
                    [syllables("q_18", "mischievous", [3: "a", 4: "b"], fallback: "e")]),
                say("sy4", "Fourteen rhyming lines make a sonnet, and a sonnet is a poem.",
                    [syllables("q_22", "poem", [1: "a", 2: "b"], fallback: "b")]),
                say("sy5", "Children colour things in with a wax crayon.",
                    [Target(questionID: "q_9", word: "crayon", measure: .crayon)])
              ]),

        Round(id: "stress", name: "Stress and colour",
              blurb: "Where the weight falls, and what colour the vowel is.",
              lines: [
                say("st1", "That American pie made with nuts is pecan pie.",
                    [Target(questionID: "q_21", word: "pecan", measure: .pecan)]),
                say("st2", "The striped things you sleep in are pyjamas.",
                    [vowel("q_20", "pyjamas", nucleus: 2, ["æ": "a", "ɑ": "b", "ɒ": "b"],
                           fallback: "c", label: "second vowel")],
                    hint: "Pyjamas or pajamas — however you say it."),
                say("st3", "My mother's sister is my aunt.",
                    [vowel("q_1", "aunt", nucleus: 1, ["ɑ": "a", "æ": "b", "ɒ": "c", "ɔ": "c"],
                           fallback: "h", label: "vowel")]),
                say("st4", "Where on earth have you been all day?",
                    [vowel("q_2", "been", nucleus: 1, ["ɪ": "a", "i": "b", "ɛ": "c"],
                           fallback: "d", label: "vowel")]),
                say("st5", "You get money off at the till if you bring the coupon.",
                    [Target(questionID: "q_7", word: "coupon", measure: .yod(without: "a", with: "b"))])
              ]),

        Round(id: "length", name: "Long and short",
              blurb: "One list, then three sentences.",
              lines: [
                Line(id: "ln1", text: "roof · room · broom · root",
                     hint: "Four separate words, a beat between each.",
                     kind: .pronounce([Target(questionID: "q_25", word: "roof",
                         measure: .fourWords(words: ["roof", "room", "broom", "root"],
                                             allLong: "a", allShort: "b", mixed: "c"))])),
                say("ln2", "The little stream at the bottom of the field is a creek.",
                    [vowel("q_10", "creek", nucleus: 1, ["i": "a", "ɪ": "b"], fallback: "f", label: "vowel")]),
                say("ln3", "The way you take from A to B is the route.",
                    [Target(questionID: "q_26", word: "route",
                            measure: .route(hoot: "a", out: "b", fallback: "f"))]),
                say("ln4", "The big knife that Jim carried is called a Bowie.",
                    [Target(questionID: "q_3", word: "bowie", measure: .bowie(oh: "a", oo: "b"))])
              ]),

        Round(id: "wild", name: "Vowels in the wild",
              blurb: "Six sentences, six vowels.",
              lines: [
                say("wi1", "Disney World is in Florida.",
                    [vowel("q_11", "florida", nucleus: 1, ["ɒ": "c", "ɑ": "b", "ɔ": "d", "u": "a", "ʊ": "a"],
                           fallback: "e", label: "first vowel")]),
                say("wi2", "Give the ending a bit of a flourish.",
                    [vowel("q_12", "flourish", nucleus: 1, ["ɜ": "a", "ɔ": "b", "ʌ": "c", "ɒ": "b"],
                           fallback: "d", label: "first vowel")]),
                say("wi3", "A cure that nobody can explain is a miracle.",
                    [vowel("q_17", "miracle", nucleus: 1, ["i": "a", "ɪ": "b", "ɛ": "c"],
                           fallback: "e", label: "first vowel")]),
                say("wi4", "Pancakes are much better with maple syrup.",
                    [vowel("q_27", "syrup", nucleus: 1, ["i": "a", "ɪ": "b", "ɜ": "c", "ʌ": "c"],
                           fallback: "d", label: "first vowel")]),
                say("wi5", "The pale vegetable that looks like white broccoli is cauliflower.",
                    [vowel("q_5", "cauliflower", nucleus: 2, ["i": "a", "ɪ": "b"],
                           fallback: "c", label: "second vowel")]),
                say("wi6", "Into your pocket goes a neatly folded handkerchief.",
                    [vowel("q_13", "handkerchief", nucleus: -1, ["i": "a", "ɪ": "b"],
                           fallback: "c", label: "last vowel")])
              ]),

        Round(id: "names", name: "Names and days",
              blurb: "The last five.",
              lines: [
                say("nm1", "Half man and half horse, that is a centaur.",
                    [vowel("q_6", "centaur", nucleus: -1, ["ɑ": "a", "ɒ": "b", "ɔ": "d"],
                           fallback: "e", label: "last vowel")]),
                say("nm2", "The Scottish name spelt C R A I G is Craig.",
                    [Target(questionID: "q_8", word: "craig",
                            measure: .glide(steady: "a", gliding: "b",
                                            steadyMap: ["ɛ": "a", "i": "c", "ɪ": "c", "æ": "d"]))]),
                say("nm3", "The one who argues your case in court is a lawyer.",
                    [Target(questionID: "q_14", word: "lawyer",
                            measure: .risingGlide(flat: "b", rising: "a"))]),
                say("nm4", "The worst day of the week is Monday.",
                    [Target(questionID: "q_19", word: "monday",
                            measure: .glide(steady: "a", gliding: "a", steadyMap: ["i": "b"]))]),
                say("nm5", "Do you actually mean that? Really?",
                    [Target(questionID: "q_23", word: "really", measure: .really)])
              ])
    ]
}

enum Script {
    static let rounds: [Round] =
        [PronunciationRounds.calibration] + WordChoiceRounds.all + PronunciationRounds.all

    static var totalQuestions: Int { rounds.flatMap(\.questionIDs).count + 1 }  // +1 for cot/caught
}
