import Foundation

/// The rounds where the word is yours to choose. Read the line; where it stops,
/// say whatever you'd actually say. The anchor words locate the gap in the
/// transcript so two questions in one passage can't be confused with each other.
enum WordChoiceRounds {

    static func line(_ id: String, _ text: String, q: String, anchor: [String], gloss: String,
                     _ matches: [(String, String)], fallback: String, hint: String? = nil) -> Line {
        Line(id: id, text: text, hint: hint,
             kind: .choice(ChoiceSpec(questionID: q, anchor: anchor, gloss: gloss,
                                      matches: matches.map { (pattern: $0.0, option: $0.1) },
                                      fallback: fallback)))
    }

    static let all: [Round] = [

        Round(id: "shop", name: "The corner shop",
              blurb: "Read the whole passage straight through. Where a line stops, say your own word and carry on.",
              lines: [
                line("shop1", "On the table there was a glass of sweetened carbonated drink — a glass of ___.",
                     q: "q_105", anchor: ["glass", "of"], gloss: "the fizzy drink word",
                     [("fizzy", "h"), ("soft drink", "e"), ("\\bpop\\b", "b"), ("\\bsoda\\b", "a"),
                      ("coke|cola", "c"), ("lemonade", "f"), ("tonic", "d"), ("dope", "i")],
                     fallback: "j"),
                line("shop2", "At the till they packed the lot into a paper ___.",
                     q: "q_109", anchor: ["paper"], gloss: "what shopping is carried in",
                     [("\\bbag\\b", "a"), ("\\bsack\\b", "b"), ("\\bpoke\\b", "c")], fallback: "d"),
                line("shop3", "I had pushed it all round the shop in a big wheeled ___.",
                     q: "q_75", anchor: ["wheeled"], gloss: "the wheeled thing in a supermarket",
                     [("trolley", "g"), ("shopping cart", "a"), ("shopping wagon", "b"), ("grocery cart", "c"),
                      ("shopping carriage", "d"), ("carriage", "e"), ("buggy", "f"), ("\\bcart\\b", "a")],
                     fallback: "h"),
                line("shop4", "And to drink with it, milk blended with ice cream — a ___.",
                     q: "q_63", anchor: ["ice", "cream"], gloss: "milk blended with ice cream",
                     [("thick ?shake", "e"), ("milk ?shake|\\bshake\\b", "a"), ("frappe|frappé", "b"),
                      ("cabinet", "c"), ("velvet", "d")], fallback: "f")
              ]),

        Round(id: "about", name: "Out and about", blurb: "Same again — one passage, your own words in the gaps.",
              lines: [
                line("about1", "To cross the country quickly you get on a big fast road — a ___.",
                     q: "q_79", anchor: ["fast", "road"], gloss: "the big fast road",
                     [("motorway|dual carriage", "j"), ("highway", "a"), ("freeway", "b"), ("parkway", "c"),
                      ("turnpike", "d"), ("expressway", "e"), ("thru ?way|through ?way", "f")], fallback: "j"),
                line("about2", "Where several roads meet in a circle and you drive round and come off — that is a ___.",
                     q: "q_84", anchor: ["that", "is", "a"], gloss: "roads meeting in a circle",
                     [("roundabout", "b"), ("rotary", "a"), ("traffic circle", "d"), ("traffic circus", "e"),
                      ("circle", "c"), ("island", "g")], fallback: "g"),
                line("about3", "The strip of grass between the pavement and the road is called the ___.",
                     q: "q_60", anchor: ["called", "the"], gloss: "grass between pavement and road",
                     [("verge", "g"), ("berm", "a"), ("tree lawn", "c"), ("terrace", "d"),
                      ("curb strip|kerb strip", "e"), ("beltway", "f"), ("parking", "b"),
                      ("nothing|no word|no name|don'?t have", "h")], fallback: "i"),
                line("about4", "The house on the far corner of the crossroads is ___ from mine.",
                     q: "q_76", anchor: ["crossroads", "is"], gloss: "diagonally opposite",
                     [("kitty ?cross", "e"), ("kitty ?wampus|catty ?wampus", "f"), ("kitty ?corner", "a"),
                      ("kitacorner", "b"), ("cater ?corner|catercorner", "c"), ("catty ?corner", "d"),
                      ("diagonal", "g"), ("nothing|no word|no term", "h")], fallback: "i")
              ]),

        Round(id: "creatures", name: "Small creatures", blurb: "Four small animals, four gaps.",
              lines: [
                line("cre1", "In the stream there is a little freshwater lobster — a ___.",
                     q: "q_66", anchor: ["lobster"], gloss: "small freshwater lobster",
                     [("crayfish", "b"), ("crawfish", "a"), ("crawdad", "e"), ("mudbug", "f"),
                      ("crowfish", "d"), ("\\bcraw\\b", "c"), ("no word|no idea|don'?t know", "g")], fallback: "h"),
                line("cre2", "Under the log, the little grey armoured thing that rolls into a ball — a ___.",
                     q: "q_74", anchor: ["into", "a", "ball"], gloss: "grey bug that rolls into a ball",
                     [("wood ?louse|wood ?lice", "i"), ("roly ?poly|rolie|roley", "d"), ("pill ?bug", "a"),
                      ("doodle ?bug", "b"), ("potato bug", "c"), ("sow ?bug", "e"), ("basketball", "f"),
                      ("twiddle", "g"), ("roll ?up", "h"), ("millipede", "j"), ("centipede", "k"),
                      ("no word|no name", "l"), ("no idea", "m")], fallback: "n"),
                line("cre3", "The American summer beetle whose back end glows in the dark is a ___.",
                     q: "q_65", anchor: ["dark", "is", "a"], gloss: "beetle that glows in the dark",
                     [("fire ?fly|fire ?flies", "b"), ("lightning ?bug", "a"), ("both|interchange", "c"),
                      ("peenie", "d"), ("no word|nothing", "e")], fallback: "f"),
                line("cre4", "At school you would go and get a drink of water from the ___.",
                     q: "q_103", anchor: ["water", "from", "the"], gloss: "where you drink water at school",
                     [("water bubbler", "b"), ("bubbler", "a"), ("drinking fountain", "c"),
                      ("water fountain", "d"), ("fountain", "d"), ("\\btap\\b|sink", "e")], fallback: "e")
              ]),

        Round(id: "things", name: "Shoes, sandwiches, cake",
              blurb: "Four more. Say the line, then your word.",
              lines: [
                line("th1", "For games at school you need the rubber-soled ones — a pair of ___.",
                     q: "q_73", anchor: ["pair", "of"], gloss: "rubber-soled sports shoes",
                     [("trainers", "i"), ("sneakers", "a"), ("gym ?shoes", "c"), ("sand ?shoes", "d"),
                      ("jumpers", "e"), ("tennis shoes", "f"), ("running shoes", "g"), ("runners", "h"),
                      ("plimsolls|pumps|daps", "k"), ("\\bshoes\\b", "b")], fallback: "k"),
                line("th2", "A long bread roll full of cold meat and salad is a ___.",
                     q: "q_64", anchor: ["salad", "is", "a"], gloss: "long filled bread roll",
                     [("baguette", "h"), ("\\bsub\\b|submarine", "a"), ("grinder", "b"), ("hoagie", "c"),
                      ("\\bhero\\b", "d"), ("poor ?boy|po ?boy", "e"), ("bomber", "f"), ("italian", "g"),
                      ("sarnie|sarney", "i"), ("no word", "j")], fallback: "k"),
                line("th3", "The sweet stuff you spread over the top of a cake is ___.",
                     q: "q_94", anchor: ["cake", "is"], gloss: "sweet spread on a cake",
                     [("icing", "b"), ("frosting", "a"), ("\\bboth\\b", "d"), ("neither", "e"),
                      ("butter ?cream", "f")], fallback: "f"),
                line("th4", "Selling your unwanted things off a table or out of the car is a ___.",
                     q: "q_58", anchor: ["car", "is", "a"], gloss: "selling unwanted things",
                     [("car ?boot sale", "j"), ("car ?boot", "k"), ("jumble", "i"), ("tag sale", "a"),
                      ("yard sale", "b"), ("garage sale", "c"), ("rummage", "d"), ("thrift", "e"),
                      ("stoop", "f"), ("carport", "g"), ("sidewalk", "h"), ("patio", "l")], fallback: "m")
              ]),

        Round(id: "odds", name: "Odds and ends", blurb: "Six short ones to finish the word-choice half.",
              lines: [
                line("od1", "Speaking to two or more people at once, I would call them ___.",
                     q: "q_50", anchor: ["call", "them"], gloss: "addressing a group",
                     [("you lot", "c"), ("y'? ?all|yall", "i"), ("you all", "a"), ("yous|youse", "b"),
                      ("you guys", "d"), ("you ?'?uns", "e"), ("yins|yinz", "f"),
                      ("everyone|everybody|folks|lads|chaps|people", "h"), ("\\byou\\b", "g")], fallback: "h"),
                line("od2", "The night before Halloween, the thirtieth of October, I call ___.",
                     q: "q_110", anchor: ["i", "call"], gloss: "the night before Halloween",
                     [("mischief night", "c"), ("gate night", "a"), ("trick night", "b"), ("cabbage", "d"),
                      ("goosy|goosey", "e"), ("devil'?s night", "f"), ("devil'?s eve", "g"),
                      ("nothing|no word|no name|don'?t have|not a thing|the thirtieth|hallowe?en eve", "h")],
                     fallback: "i", hint: "If you don't have a name for it, say so — \"nothing\" is a real answer."),
                line("od3", "Rain falling while the sun is still shining — I call that ___.",
                     q: "q_80", anchor: ["call", "that"], gloss: "rain while the sun shines",
                     [("sun ?shower", "a"), ("wolf", "b"), ("beating his wife", "c"), ("monkey'?s wedding", "d"),
                      ("fox'?s wedding", "e"), ("pineapple", "f"), ("liquid sun", "g"),
                      ("nothing|no word|no term|don'?t have|sun and rain|a rainbow", "h")], fallback: "i"),
                line("od4", "The outdoor thing the hose screws onto, that water comes out of, I call a ___.",
                     q: "q_41", anchor: ["call", "a"], gloss: "outdoor water tap",
                     [("spicket", "a"), ("spigot", "b"), ("\\bboth\\b", "c"),
                      ("neither|outside tap|garden tap|\\btap\\b|standpipe|don'?t use", "f")], fallback: "g"),
                line("od5", "I ___ her lifeless body from the pool.",
                     q: "q_49", anchor: ["i"], gloss: "past tense of drag",
                     [("dragged", "a"), ("\\bdrug\\b", "b"), ("\\bboth\\b", "c"), ("pulled|hauled", "a")],
                     fallback: "d", hint: "The gap is in the middle this time — say the whole sentence."),
                line("od6", "Someone whose job is selling houses is called a ___.",
                     q: "q_24", anchor: ["called", "a"], gloss: "someone who sells houses",
                     [("realtor|realter|realator", "a"), ("estate agent", "d"), ("real estate", "e")],
                     fallback: "e")
              ])
    ]
}
