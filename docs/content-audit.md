# Auditing what the games actually ask

A learner meets this app as a few hundred generated questions. Whether those
questions are *sound* — answerable, correctly keyed, fairly distracted,
age-appropriate — is not something the test suite can assert, and playing the
games one round at a time surfaces a handful of items an hour.

`test/audit/challenge_dump_test.dart` prints them instead, in bulk, as text or
JSON, so a reviewer or an agent can read hundreds at once.

```sh
tools/audit/dump.sh --list                       # the games, and their packs
tools/audit/dump.sh --game definition_quiz --grade 4 --count 30
tools/audit/dump.sh --lang de --pack-de ~/grundwortschatz.db --json
tools/audit/dump.sh --check                      # assert instead of print
```

`--check` runs `test/audit/challenge_contract_test.dart` (below). The German
pack is a download, so `--lang de` needs `--pack-de` pointing at a decompressed
copy; the English pack ships as an asset.

The script is a wrapper: the harness itself is driven by environment variables
and can be run directly.

```sh
WU_DUMP=all WU_DUMP_COUNT=25 flutter test test/audit/challenge_dump_test.dart
WU_DUMP=homophone_drill WU_DUMP_GRADE=4 WU_DUMP_FORMAT=json \
  flutter test test/audit/challenge_dump_test.dart
```

| variable | meaning |
|---|---|
| `WU_DUMP` | `all`, `list`, or a comma-separated list of generators |
| `WU_DUMP_COUNT` | items per generator (default 20) |
| `WU_DUMP_GRADE` | grade band to generate for (default 3) |
| `WU_DUMP_LANG` | `en` (default) or `de` |
| `WU_DUMP_FORMAT` | `text` (default) or `json` — one JSON object per line |
| `WU_DUMP_SEED` | RNG seed, so a review is reproducible (default 1) |
| `WU_DUMP_OUT` | write to a file instead of stdout |
| `WU_PACK_DE` | decompressed German pack, required for `WU_DUMP_LANG=de` |

The dump asserts nothing: the output is the product. Each item shows the
prompt, the options, which option is keyed correct, and the data behind it, so
a reviewer can judge whether the question is answerable, whether the marked
answer is right, and whether the distractors are fair. What *can* be judged
without a person is in the contract test below.

## What it found on its first run

- **Word of the day walked the dictionary.** The index was the date seed itself
  and the pool arrives in catalogue order, so consecutive days gave consecutive
  entries: *complicated, compound, compromise, con, concentrate, concentration,
  concept, concern, concerned, concerning, concerns…* through January, and
  *Lexikon, lila, Limonade, Lineal, links, Lippe, Lob…* in German. Fixed by
  scattering the seed; the word for a given day is still the same for everyone.
- **Inflected forms were offered as headwords**, and noun plurals still took a
  singular article from `displayName` — "an elements", "a laughs", "an arms".
  Fixed by restricting the pool to entries whose spelling is their own lemma.
- Both were invisible to the test suite and to ordinary play, and obvious
  within seconds of reading a dump. Later runs added: a cloze sentence that
  said the answer again beside the gap, Translation Flash asking cognates
  ("What is *das Hobby* in English?"), and names the packs do not flag sitting
  among the options — *hannibal*, offered as a meaning of *detector*.

## What reading 1,500 items found

A pass over every game at every grade of both packs, after the contract test
was green. The contract catches what is mechanically wrong; a reader catches
what is merely useless.

- **Questions that answered themselves.** Sentence Completion blanked a word
  out of a sentence that said it again; Synonym Flash asked *"which word means
  the same as high-pitched?"* and keyed **high**, and *white → lily-white* the
  other way round; Translation Flash asked cognates in both directions.
- **Questions with no meaning in them.** The packs carry parses as glosses —
  *"Partizip Präsens des Verbs wüten"*, *"plural of passerby"*, *"simple past
  and past participle of annoint"* — plus abbreviations (*"Abbreviation of
  July."*), bare domain labels (*"Botanik:"*) and one-word glosses that point
  at another misspelling (*residental* → *"residentiary"*). None of them is
  something to ask a learner. `isUsableDefinition` is the rule now.
- **Wrong answers.** Conjugation Drill asked *"geschehen: ich ___"* and keyed
  *geschieht*: it mapped Wiktionary's present forms positionally, and an
  impersonal verb lists only the third person. Großstadt framed *"WIR
  [aufbleiben]"*, where German writes *wir bleiben auf*.
- **A game that only ever showed one side of its own contrast.** 29 of 33
  Trennbare Verben tiles were ZUSAMMEN, and four grades had no GETRENNT tile
  at all — answering "together" every time scored full marks. It looked for
  the literal string "stehe auf", which German never writes contiguously.
- **Rounds with one answer.** Word Class Flash dealt six nouns in a row in
  German, where nouns outnumber everything else; the classes take turns now.
- **Misspellings as vocabulary.** English grade 6 was full of *residental*,
  *controversal*, *undesireable* and *resistent*, as prompts and as options.
  The packs mark them, but in `tags`, and only `sources` was being read.
- **Wrong articles.** The English pack stores the indefinite article by a
  naive vowel rule: *an user*, *an university*. It also made the prompt
  disagree with the answer — *Find "a vegetable"* over a grid holding
  `vegetable`. The article is German-only now; English has no gender to teach.
- **Word of the day was "a jun", "a html", "a linux", "a jul"** at English
  grade 5, repeating every five days. Those four carry `source:fry`, so the
  curriculum preference chose them: the pack's Fry list imported badly, and
  the five curriculum words at that band are four pieces of junk. A pool too
  small to last a fortnight is passed over now, and the card verifies the
  gloss after hydrating.

A second pass, on a different seed, found seven more:

- **The word of the day walked the alphabet again** — das Dorf, elf, feiern,
  früher, der Grad, hoch, krank, der Mensch. The stride that guarantees a full
  cycle without repeats steps through a pool that arrives in catalogue order,
  and for that pool size it stepped alphabetically. The pool is permuted per
  year now (a stable hash of the word, so every device agrees), and the
  candidates a day falls back on walk by their own stride — with one stride,
  today's second candidate was tomorrow's first, and "sorry" came up twice in
  a row.
- **Spelling Spotter padded its options with other words' misspellings** —
  "Which spelling is correct? tüb / ales / nehbehn / Typ", where only one
  option even resembles the word. A padded distractor now has to start with
  the same letter and be within an edit distance of half the word, and two
  plausible options beat four where three are noise.
- **Großstadt drilled "kacken" and "furzen"** — words a spelling-error corpus
  contributes with no gloss, no grade and nothing else. The games' pools
  require a usable definition now; that is a new feature bit, so the packs'
  own filtering agrees with the app's.
- **"jesus" reached an English grade 3 definition quiz**, keyed against
  "batman" and "cam".
- **Truncated glosses**: "eine Hupe am Kraftfahrzeug betätigen, um", "Eine
  Alternative ist,.".
- **"Lünen"**, a town, in a German word snake: the pack writes place glosses
  appositively ("eine Stadt in Nordrhein-Westfalen") as well as as sentences.

Some findings belong to the packs rather than the app, and are left as they
are: that Fry list; `fart`, whose LLM-written grade examples are read out to a
ten-year-old; Hypernym Flash, nearly empty in German because the pack rarely
holds a hypernym with the same word class as the prompt; Wiktionary's noisier
antonyms (*Nebel* → *Smog*, *Auge* → *Ohr*); and LLM grade examples that are
simply wrong — "The book has a pair of pages." is the English pack's sentence
for *pair*, and the Homophone Drill can only blank a word out of it.

## The contract test

`test/audit/challenge_contract_test.dart` runs every generator over grades 1-6
of both packs — 1,214 English items and 1,568 German ones — and asserts what
does not need a person:

- the prompt is not blank, and carries no stray `null`
- every option is non-blank, and no two options are the same
- the keyed answer is among the options
- the prompt does not contain its own answer
- every game fills a round, at more than one grade band

Each rule was a real bug first. The last one is the widest: Translation Flash
was in the menu with an empty pool for weeks, because the feature bit it
filtered on read a JSON key neither pack uses, and nothing failed.

Exemptions are declared in the test with a reason — games whose prompt names
the word on purpose (*Find "x" in the grid*), and the three where two options
differing only in case *is* the question (Wortfalle's *Wagen* / *wagen*). A new
game that needs an exemption should say why it needs one.

CI runs the English half, since that pack ships as an asset. The German half
skips unless `WU_PACK_DE` points at a decompressed pack.

## Coverage, and how to widen it

All 31 games in the menu are reachable: every one builds its challenges in a
service under `lib/features/games/services/`, and the screen only draws what
the service returns. A run ends with the generator count, and names any game
that is not reachable — today none are.

Keep it that way when adding a game: put the challenge construction in a
service that takes data and returns data, and register it in the `generators`
map in `test/audit/challenge_dump_test.dart`. A game whose challenges are built
inside its widget cannot be reviewed except by playing it.

Several games share one service — `cloze_service.dart` backs cloze, expression
and proverb; `adaptive_word_selection.dart` backs six practice games; the SRI
review game reuses `definition_quiz_service.dart` so both inherit the same
fairness rules (headword redaction, no name glosses, article-labelled options).
A fix in one is a fix in all of them, which is the point.
