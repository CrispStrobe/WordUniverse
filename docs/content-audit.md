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

Some findings belong to the packs rather than the app. Two are fixed *in* the
packs now, by `tools/pack/repair_pack.py`: names are typed `proper_noun`, and
a leading gloss that is a parse rather than a meaning is dropped so a real
sense comes first. `tools/pack/quality_report.py` shows what every content
rule excludes and, in the column to read first, how much of that is attested
vocabulary.

These are still open, and belong to the pack pipeline: the Fry list that
contains "jun", "jul", "html" and "linux"; `fart`, whose LLM-written grade
examples are read out to a ten-year-old; Wiktionary's noisier antonyms
(*Nebel* → *Smog*, *Auge* → *Ohr*); and LLM grade examples that are simply
wrong — "The book has a pair of pages." is the English pack's sentence for
*pair*, and the Homophone Drill can only blank a word out of what it is
given.

## English, and the other half of the question

The German check asks whether a form the app *composed* is one the pack
knows. English needs a different question, because the app composes almost no
English: it blanks a word out of a sentence the pack wrote, redacts a headword
out of a gloss, offers a translation the pack lists. The sentence was
grammatical when the pack shipped it. What can go wrong is the transformation.

`test/live/item_provenance_live_test.dart` undoes each one and compares:

| | |
|---|---|
| cloze, expression, proverb | `before + the blanked form + after` is the source text, character for character |
| sentence completion | the same, against one of the pack's own grade examples |
| homophone drill | filling the gap back in gives a sentence the pack ships |
| definition quiz | the prompt is a pack gloss with the headword redacted |
| syllable count | the keyed bucket is the pack's hyphenation, counted |
| phrasal verbs | the keyed option is one of the phrasal's particles, and it is in what the learner reads |
| translation flash | the answer is one the pack lists for that word |

Mutation-checked: moving the end of a blank by one character fails it with
*"He wants to retireat 55." ≠ "He wants to retire at 55."*

Two of these were written stricter and then relaxed for a reason worth
recording. Requiring the phrasal *verb* to appear fails on every conjugated
sentence — "carry out" is taught and the sentence says "carries out" — and
nothing here can lemmatise English. And the keyed particle is not the last
word of the phrasal: "get on with" is keyed on *on*. A check that has to be
weakened is worth weakening precisely, not deleting.

## Having a model read them

`tools/audit/review.py` asks a model the four questions a teacher would ask of
each generated item — is it answerable, is the marked answer right and every
other option wrong, is every sentence grammatical, would you put it in front
of a ten-year-old — and writes one verdict per item.

```sh
tools/audit/dump.sh --lang de --pack-de pack.db --count 200 --json --out items.jsonl
python3 tools/audit/review.py items.jsonl --model <name> --out verdicts.jsonl
python3 tools/audit/review.py items.jsonl --report verdicts.jsonl
```

It flags; it does not fix. A flag is a claim with a reason attached, which is
what makes it cheap to dismiss when the model is wrong — and the model will be
wrong, so the output is a triage list for a person, never a gate. `--dry-run`
prints the rubric and one batch without calling anything; the run is
resumable, so a long sweep can be stopped and continued.

Any OpenAI-compatible endpoint works. Free tiers rate-limit per key *and* per
model, and they say so with a 429 rather than with a budget, so the tool
spreads the work over lanes — a lane being one key on one model — and sends
each batch to whichever lane comes free first:

```sh
python3 tools/audit/review.py items.jsonl --replicas 2 \
  --lane "https://openrouter.ai/api/v1|OR_KEY|nvidia/nemotron-3-ultra-550b-a55b:free" \
  --lane "https://api.groq.com/openai/v1|GROQ_KEY|openai/gpt-oss-120b" \
  --lane "https://openrouter.ai/api/v1|OR_KEY|z-ai/glm-5.2:free"
```

Which lanes are worth opening, measured over a 120-item run rather than
guessed. Nemotron judged all 120 and gpt-oss-120b 104, so those two carry a
run between them. `z-ai/glm-5.2:free` finished 16: it spends most of a run
rate-limited, which makes it a third opinion rather than a workhorse.
`thinkingmachines/inkling:free` answered 403 to every request across four
rounds and has never judged a single item — it is not in the list above, and
that is deliberate.

Their flag rates — 13.3% and 16.3% — are too close to say which is the better
judge. Answering that needs a set of items somebody has labelled by hand to
score them against, and until that exists no claim about one model being
better than another is coming from evidence.

### Two opinions, not one

`--replicas 2` sends each batch to two *different* lanes. A lane that has
already answered is excluded from the second draw, so the same model is never
asked twice and its own echo counted as agreement; asked for two opinions
where only one lane exists, it returns the one it has.

`--agreement <verdicts.jsonl>` then reports what that bought. Over 120 items
judged twice:

| | |
|---|---:|
| both lanes passed | 80.3% |
| only one lane flagged — the pile worth reading | 12.0% |
| both flagged something | 7.7% |
| both flagged the same field — act on these | 6.0% |

Agreement halves the actionable set, from a single lane's one item in seven to
one in sixteen, and the part needing a person's eye becomes fourteen items
rather than all of them. That matches what triage kept finding by hand: about
half of a single model's flags were the model's own error. The lanes agree on
95.7% of individual judgements, so disagreement is rare enough to read.

One caution worth stating: two models agreeing is still a flag, not a defect.
Every fix this file describes came from a model *finding* something and a
measured rule fixing it. Agreement is a better filter, not an authority.

A 429 parks its lane for the time the provider asks for (`Retry-After`) or an
exponential backoff; a refusal — a gated model, a wrong name, no credit —
retires the lane for the run rather than being retried into the ground; and
`--pace` keeps a minimum gap between two requests on the same lane. When every
lane is parked the batch is given up rather than hung on, and those items
simply stay unjudged: a resumed run picks them up.

`--model a,b,c` with a single `--endpoint` is the short form of the same
thing. A local server works too. It is worth saying plainly that a small local model is not good enough
for this: judging whether *du sprichst* is right takes a model that knows
German well. Run it where a capable one is, on the JSONL — that is the whole
reason the dump speaks JSON.

### Scoring the judges

`--sheet N` writes the same items as a numbered sheet for a person instead,
N per game, spread across the file rather than taken from the front. An hour
of a teacher's time on what the machine flagged is worth more than a day of
unguided reading.

Beside the sheet it writes `<sheet>.items.jsonl`, which says which item each
number is. That is what turns a read sheet into a measurement: on the verdict
line write `ok`, or the names of whatever is wrong — `answerable`, `keyed`,
`grammatical`, `appropriate` — and a reason after a dash for the next person.
A line left blank means nobody got to that item, which is not the same as
passing it and is not counted.

```sh
python3 tools/audit/review.py items.jsonl --sheet 3 --out sheet.txt
# ... somebody fills in the verdict lines ...
python3 tools/audit/review.py x --score sheet.txt --against verdicts.jsonl
```

That prints, per lane, precision — of what it flagged, how much a person
agreed was wrong — and recall — of what a person called wrong, how much it
caught. Until a sheet exists with enough items on it, no claim that one model
judges better than another is coming from evidence, however plausible it
sounds. Two lanes' flag rates being 13.3% and 16.3% says nothing about which
is right more often.

`tools/audit/review_test.py` checks the plumbing against a stub endpoint: that
a flag survives the round trip with its reason, that a model answering about
fewer items than it was asked does not silently flag the rest, and that a
resumed run skips what it already judged.

## How much of this is actually checked

| | |
|---|---|
| structural rules, every push | 1,260 English items; German too, since CI fetches the pack |
| structural rules, nightly | 500 per game per grade, sharded twelve ways |
| German the app composes itself | 3,240 Großstadt frames, 3,531 drill forms, 328 verb tiles, 359 compounds — every one against the pack's own tables |
| every string a game shows, back against its source | ~3,700 items across both packs: blanked sentences, definition prompts, syllable keys, homophone gaps, phrasal particles, translations |
| the frozen sample | four items per game, both packs, as a diff |
| meaning | nothing automated; read by hand |

The games can produce on the order of a hundred thousand distinct items —
Definition Quiz alone gave 4,000 at English grade 3 without running out — so
ten items per game per grade is a tripwire, not a proof. Three reading passes
found twenty-one content bugs in a sample that size.

`tools/pack/consistency_report.py` compares the pack's overlapping fields
against each other. What it found is worth keeping in mind before trusting any
of them: 1,057 German nouns know their gender but carry no article, 693 have a
lemma column that is neither the word nor its lemma ("abbiegen: Abbieg"), and
73 have an article and a gender that contradict each other. Filling the
missing articles from the gender field looks obvious until you read what it
would write — "die Chicago", "das Allah", "der Hunden", "das Landes". The rows
missing an article are mostly the ones that should not be taught at all, and
their gender field is no better than the rest of them.

## What the dump shows

What a generator returns is what the screen shows. The flash games display a
word and its options, with the task carried by the game's own title — so the
items are the word and the options, and the dump prints the localized title
above them. Where the screen composes a sentence (the cloze games, Wortfalle,
Großschreib-Rakete, Sentence Completion, the conjugation drill), the item
carries that sentence.

This matters more than it sounds. The harness used to write its own question
prose, and the one place where its phrasing and the screen's differed hid a
bug for weeks: Spelling Spotter's example sentence, which the screen reveals
only *after* an answer, was being printed as part of the question — where it
gave the spelling away.

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

## Senses, and the data the slimmer had thrown away

Almost every content rule above was written to guess which *sense* of a word a
relation belongs to. "Chicken" arrives with "competition" beside "poultry",
"hand" with "ability" beside "extremity", and nothing said which. So the games
grew heuristics: is the hypernym repeated in the word's own gloss, does the
entry list more than eight, does the catalogue hold it with the prompt's word
class.

They were standing in for data that had been in the pack and was removed.
`tools/pack/slim_pack.py` dropped `wordnetSenses` and `openThesaurus` as "not
in the Dart model at all", which was true when it was written. Both are
sense-grouped:

| | carries | entries | senses |
|---|---|---:|---:|
| English | `wordnetSenses` | 7,367 | 32,534 |
| German | `openThesaurus` | 6,225 | 15,517 |

Reduced to what the games read they cost about a megabyte compressed each.
English gets sense-linked synonyms *and* hypernyms; German gets synonyms only,
because `openThesaurus` carries an empty `hypernyms` on all 15,517 of its
synsets. German hypernyms therefore keep every heuristic; the English
heuristics remain for the 4,000 entries WordNet does not cover.

Three things still have to be true of a sense before it is used.

**It must be about the word, not a name.** WordNet often lists the name sense
first: "frost" leads with Robert Frost, which is where "a frost is a kind of
poet" came from. Three signals, each measured against the 32,534 — the gloss
says so, the synonyms are capitalised while the headword is not (4.1%, which
also catches "add" carrying ADHD), or it is scripture or myth (17 senses).

**There must be a leading sense worth trusting.** WordNet orders senses by
frequency in general writing, which is not what a seven-year-old means:
"plant" leads with the factory. An entry with more than three senses of its own
class is not asked. That keeps 63% of entries and prunes where the polysemy is
— 41% at grade 2, 97% at grade 6.

**The register markers are read, not stripped.** openThesaurus marks 18,610
synonyms `(umgangssprachlich)`, 4,750 `(gehoben)` and 773 `(derb)`. The coarse
ones are dropped outright and the rest come last.

### Glosses

A gloss is shown as the hint beside a word to find, trace, build or sort, and
as the card a memory pair matches. `glossSuitsAChild` rejects two kinds: over
180 characters, which is past the 95th percentile in both packs, and the
taxonomic register — a rank followed by a Latin name, a Latin binomial, or the
hedges Wiktionary writes when it is being careful rather than clear. 4.8% of
English leading glosses and 1.9% of German.

A rejected gloss means **no hint**, not the next definition. Filtering the list
promotes a different *sense* into first place, and doing that explained a
helicopter as "A powered troweling machine with spinning blades used to spread
concrete" across 506 entries before anybody read one.

The exception is an entry with exactly one WordNet sense of its class, where
there is no sense to choose: 105 entries take WordNet's plainer wording
instead.

The other 226 are no longer left alone. They needed a way to say *which* sense
the entry means, and sense order is not it — that looks like the answer and is
worth writing down as a dead end, because WordNet ranks by frequency in a
general corpus:

| word | WordNet's first sense of the class | what the pack means |
|---|---|---|
| bank | sloping land beside a body of water | a financial institution |
| table | a set of data arranged in rows and columns | a piece of furniture |
| light | a divine presence believed by Quakers | electromagnetic radiation |
| crane | United States writer (1871-1900) | a long-necked wading bird |

What does identify the sense is overlap with the pack's own gloss, and that
works precisely because it does not need the pack's gloss to be *readable* —
only to be about the same thing, which is the one thing known here. "An
institution where one can place and borrow money" shares institution and money
with "a financial institution that accepts deposits and channels the money into
lending", and shares nothing with the riverbank.

Two shared content words, strictly more than any other sense of the class, and
then the same child-readability test. 1,759 entries align; 1,270 share nothing
with any sense, 1,734 share a single word, 153 tie. Eighteen read at random were
all the right sense. One word is a coincidence and a tie is a choice this cannot
make: "spring", glossed "An act of springing: a leap, a jump.", shares nothing
with any of its eleven senses and stays unexplained rather than becoming the
season.

### A gloss above its reader

"honest" explained with "scrupulous" was the last thing here that nothing
caught, and it was recorded as needing a frequency list that German compounds
would break. The pack carries a better list than any external one: **its own
graded catalogue**. A content word appearing nowhere in 11,539 English or 13,040
German graded spellings is a word this reader has not met.

The earlier attempt at this failed for two reasons, and both had fixes:

- It read inflections as unknown — "standing", "relating", "consisting",
  "survives" — and every second gloss looked too hard. Crude suffix stripping
  answers it; the only question asked is whether the catalogue holds the word in
  *some* form.
- It scored "Muttertier des Hausrinds" as the hardest gloss in the pack. That
  gloss has two content words. A four-word minimum answers it, and the case the
  objection was built on is now the test for it.

The share is per language, which is calibration rather than policy: German
writes one compound where English writes three words, so "Körpertemperatur"
counts once as unseen where "body temperature" contributes a seen word, and the
same fraction is a stricter test.

| | English | German |
|---|---:|---:|
| > 0.5 | 98 (0.9%) | 1231 (10.4%) |
| > 0.7 | 32 | 465 (3.9%) |

English takes 0.5, where 63 of the 98 have a WordNet sense ready to replace
them. German takes 0.7, because at 0.5 it removes Frosch, Katze, Finger and
Gemüse at grade 1 and German has no WordNet to fall back on, so those entries
would show no meaning at all. At 0.7 it still reaches the glosses that are no
use to anyone: "Fach: der durch das Balkengerüst beziehungsweise die tragenden
Balken begrenzte …" and "Fliege: fliegendes Insekt der Unterordnung Fliegen
(Brachycera)" at grade 1.

It is a fault in the gloss, not the word. "sein", "among" and "ear" keep their
place in the catalogue; the app stops handing those sentences to a learner. It
does **not** promote the next gloss, and that was measured rather than assumed:
promotion takes "ai" from a three-toed sloth to the branch of computer science,
and "post" from a plank in the ground to "A stud; a two-by-four".

Decided when the pack is built, because that is the only place the catalogue is
known in full. Reading the round's sample instead is the bug this codebase has
shipped five times.


## A second reader

`docs/review/gold-set-2026-09-23.txt` was labelled by the assistant that wrote
the rules in this file, which measures how consistent one judgement is rather
than whether it was right. `…second-reader.txt` is the same 155 items labelled
from a blank copy by a separate agent that was told nothing about these rules
and given no access to the first labels.

They agree on **93%** of items — 29 both called wrong, 4 only the first, 7 only
the second. That is close enough to trust either as a rough rate and far enough
apart to be worth the second pass, because the disagreements were not noise.

Three of the seven were faults the first reader had passed:

- **"am falschen ___ sparen" keyed "Platz".** The fixed idiom is *am falschen
  Ende sparen*. Closed on measurement rather than edited: the Platz version is
  what Wiktionary lists under *Platz*, so the pack matches its source, and the
  idiom family is not missing — "sparen" carries *an allen Ecken und Enden
  sparen*. One reader's judgement against a sourced expression is not a rule,
  and there was no gap to fill.
- **The Großschreibung rule text.** "sehr" and "dein" were keyed lowercase and
  explained with "Verben und Adjektive werden kleingeschrieben" — one is an
  adverb, the other a possessive determiner. The screen has always drawn only
  nouns, verbs and adjectives and given each its own explanation; the dump drew
  anything, so this was a game nobody plays being reviewed. Fixed.
- **"carthaginian" offered lowercase.** It is a proper adjective. That turned
  out to be a class: **169 English entries are stored lowercase while every
  mid-sentence occurrence in the pack's own prose is capitalised** — january,
  english, christmas, july, friday, chinese, dutch, usa, europe.

### Spellings the pack contradicts

`spellingIsTrustworthy` reads the pack's own glosses, graded examples and book
quotations. Three or more mid-sentence occurrences, all capitalised, and the
lowercase headword is wrong. Sentence-initial occurrences are ignored, because
a capital there proves nothing.

The games that ask a child to find, trace or match a spelling skip those
entries. Word Builder does not need to: it uppercases every letter tile, so the
stored case never reaches the screen.

Exclusion was the first answer and is now the fallback. Read one at a time the
169 turned out to be four different defects wearing the same symptom, and the
worst of them was not about capitals at all.

| | | fix |
|---|---:|---|
| ordinary vocabulary missing its capital | 81 | headword capitalised |
| a name the pack called a word | 53 | typed `proper_noun` |
| not a word at all | 21 | marked not vocabulary |
| gloss and evidence describe different words | 11 | marked not vocabulary |
| correct in both cases | 3 | left to the exclusion filter |

**The gloss/evidence mismatch is the one worth naming.** Evidence that always
capitalises a word says it is a name; a gloss that does not describe a name
says it is not. Both cannot be about the same word, and what the pack has then
stored is a rare homograph of a name carrying the name's sentences:

| entry | grade | gloss |
|---|---|---|
| olympics | 2 | Five consecutive ducks |
| james | 2 | The twentieth book of the New Testament |
| george | 2 | radiotelephony clear-code word for the letter G |
| henry | 3 | the derived unit of electrical inductance |
| leo | 3 | Clipping of leotard |
| joanna | 5 | A piano |
| eric | 3 | A fine paid as compensation for violent crimes |

The gloss loses, because the examples are what a child reads.
`gloss_belongs_to_another_word` in `repair_pack.py` is that rule, and the three
things that make it safe were each measured rather than assumed:

- **Chapter headings are not sentences.** "escape" was the only false positive
  in the 169: its three capitalised uses are Title Case headings — "The Boys
  Escape Jim.—Tom Sawyer's …". Dropping book quotations from the evidence
  entirely would fix it and cost "friday" plus six names; skipping Title Case
  text fixes it alone. Counting the sentence's *own opening word* toward the
  ratio made short sentences ("Each January brings snow.") look like headings,
  which is how the rule got tested.
- **A CEFR level separates the words correct in both cases** — "god", "mommy",
  "pa", "soviet" — from the homographs, 29 times out of 30. A level is assigned
  to a meaning a learner acquires, and there the gloss describes the
  capitalised sense instead of contradicting it. "august" is the exception,
  levelled A1 as the month while glossed as the adjective, and is named in
  `GLOSS_MISMATCHES`.
- **English only.** German capitalises every noun and every nominalised verb,
  so "das Reisen" in an example of "reisen" is correct German and evidence of
  nothing. Before the gate the rule flagged reisen, regeln, donnern, aussagen
  and freie.

Of the 53 names, 18 are reached by gloss shape rather than by a list — `"
commune in "`, `" secret police of "`, `"the fictional "`, `" book of the New
Testament"` — which is the part that will keep working on the next dataset.
The other 35 are listed because nothing in the row can reach them: "lapd" has
no gloss at all. Each added shape is narrower than the glosses invited, and the
narrowing was forced: `"a fictitious "` named "pseudonym", and `" a ruler over
"`, `"the daughter of"` and `" corporation"` would have named king, princess
and any firm. A gloss shape an ordinary word can also wear is not evidence of a
name.

Every rename differs from the old headword only in case, and that is asserted
in code: the pack ships a prebuilt FTS5 index over the words table that cannot
be rebuilt here — it is declared over a `translations` column the table does
not have — and it stays valid only because FTS5 folds case.
