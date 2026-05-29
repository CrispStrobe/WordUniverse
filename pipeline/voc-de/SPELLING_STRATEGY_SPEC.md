# Spelling-strategy classifier — science-grounded spec

Status: **IMPLEMENTED & shipped** (2026-05-29). Supersedes the worksheet-fitted
classifier. The taxonomy is grounded in the orthographic principles of German
(phonographisch / silbisch / morphologisch / morphematisch / syntaktisch), per
Eisenberg & Fuhrhop, Maas, Gallmann, Schmidt/Fuhrhop, the amtliches Regelwerk
(Rat für deutsche Rechtschreibung, 2024), and **Günther Thomé's Basiskonzept
Rechtschreiben** (Basisgrapheme vs Orthographeme).

The old `532Strategien.csv` (an NRW classroom worksheet) is **demoted** from
gold standard to an at-most-advisory smell test: it splits identical cases
(`Tasse` vs `Puppe`) and mis-files rule-governed words as "Merken". The new
regression reference is the principle-based exemplar gold at the end of this
doc (`spelling_strategy_gold.csv`).

> **Terminology rule:** the method-brand term and its didactic jargon are not
> used anywhere in this project. Only linguistic-scientific terms and our own
> neutral category tokens appear in code, docs, tests, filenames, and app text.

## Framework decisions (confirmed)

1. **Doubling = Thomé function-based.** All short-vowel consonant doublings are
   **one** category (`doppelkonsonant`), regardless of position:
   `Tasse` = `Puppe` = `Wasser` = `Mann` = `Ball` = `Bett` = `Glück`. This
   matches Thomé's "13 Konsonantenverdoppelungen zur Markierung von Kurzvokalen"
   and our surface-named token (`Mann` visibly has a doubled consonant). The
   Eisenberg/Maas refinement (intervocalic = Silbengelenk/silbisch vs
   monosyllabic = morphological Stammkonstanz, found via the Erweiterungsprobe
   `Mann→Männer`) is preserved **in the per-word explanation**, not as a
   separate category.
2. **`dehnung` is a 7th category** (Thomé's "13 Langvokalmarkierungen"). Folding
   it into `merkwort`/`klangtreu` would contradict the science.
3. **Intervocalic doubling is NOT `klangtreu`.** Under every account the doubling
   is an orthographic marking (Orthographem). This reverses the prior
   classifier, which wrongly filed `alle`/`Wasser`/`Tasse` as `klangtreu`.
4. **Umlaut-constancy and Auslautverhärtung are `verwandt`** (morphological
   Stammkonstanz), **not** `merkwort`.
5. **silbentrennendes-h** (`gehen`, `sehen`) is rule-governed, **not** `merkwort`
   — see §dehnung for where it lands.

## The seven categories

Each entry: **principle** · **decision rule** (algorithmic) · **citation** ·
**explanation** (kid/parent-facing, scientifically correct).

### 1. `klangtreu` — phonographisches Prinzip (Basisgraphem)
- **Rule:** residual. Assigned when no Orthographem/marker fires (Großschreibung
  is orthogonal). The word is written with the default grapheme per phoneme.
- **Citation:** Thomé — 41 Basisgrapheme, ~90.5% of written units; Eisenberg/
  Fuhrhop phonographisches Prinzip.
- **Explanation:** „Du schreibst das Wort so, wie du es langsam und deutlich
  sprichst — jeder Laut bekommt seinen üblichen Buchstaben."
- **Examples:** `malen`, `lesen`, `Nase`, `Blume`, `rot`, `Schule`.

### 2. `doppelkonsonant` — Schärfung / Konsonantenverdopplung (Orthographem)
- **Rule:** short **stressed** vowel immediately followed by a doubled consonant
  (`bb dd ff gg ll mm nn pp rr ss tt`) **or** `ck` **or** `tz` — at any position
  (intervocalic *or* word-final/pre-consonantal).
- **Citation:** amtliches Regelwerk §2; Thomé group 1; Eisenberg/Fuhrhop
  Silbengelenk; Gallmann (Erweiterungsprobe for monosyllables).
- **Explanation:** „Nach einem kurzen, betonten Selbstlaut schreibst du den
  folgenden Mitlaut doppelt (oder `ck`/`tz`). Du hörst ihn nur einmal."
  *Optional derivation hint:* „Bei kurzen Wörtern kannst du verlängern, um es zu
  hören: `Mann` → `Männer`, `Ball` → `Bälle`. Bei längeren Wörtern liegt der
  doppelte Mitlaut zwischen den Silben: `Tas-se`, `Pup-pe`."
- **Examples:** `Tasse`, `Puppe`, `Wasser`, `alle`, `rennen`, `Mann`, `Ball`,
  `Bett`, `Glück`, `Katze`, `Platz`.

### 3. `dehnung` — Langvokalmarkierung (Orthographem) *(new)*
- **Rule:** long **stressed** vowel marked by **(a)** Dehnungs-h: vowel + `h` +
  {l,m,n,r} (`Bahn`, `Stuhl`, `mehr`, `fehlen`); **(b)** double vowel `aa/ee/oo`
  (`Saal`, `Meer`, `Boot`); **(c)** `ie` for long [iː] (`Brief`, `lieben`,
  `Tier`). **silbentrennendes-h** (intervocalic `h` in `gehen`, `sehen`, `Ruhe`)
  is included here as a length/h-marker for the learner, with the scientific
  note that its *function* is a syllable boundary, not vowel length.
- **Citation:** Thomé group 2; Wikipedia/Duden Dehnungs-h vs Silbenfugen-h;
  Schmidt/Fuhrhop on the silbeninitiale `h`.
- **Explanation:** „Ein lang gesprochener Selbstlaut wird besonders markiert —
  mit einem stummen `h` (`Bahn`, `Stuhl`), einem doppelten Selbstlaut (`Saal`,
  `Boot`) oder mit `ie` (`Brief`)."
- **Examples:** `Bahn`, `Stuhl`, `mehr`, `Saal`, `Boot`, `Meer`, `Brief`,
  `Tier`, `gehen`, `Ruhe`.

### 4. `verwandt` — morphologisches Prinzip / Stammkonstanz
- **Rule:** the spelling is recovered from a related form. Fires on **(a)**
  Auslautverhärtung — final `b/d/g` (and `-ig`) whose IPA is voiceless
  [p/t/k/ç] (`Hund`→[hʊnt], `Berg`→[bɛʁk], `lustig`→[lʊstɪç]); **(b)** Umlaut
  `ä/äu` traceable to an `a/au` base via the inflection/derivation table
  (`Hände`←`Hand`, `Bäume`←`Baum`, `läuft`←`laufen`).
- **Citation:** Eisenberg/Fuhrhop (`<wald>` unterspezifiziert); Schmidt/Fuhrhop
  Stammkonstanz "Kronzeuge … unstrittig"; Thomé group 3 (stem-preservation:
  d/g/b, ä/äu, -ig).
- **Explanation:** „Den richtigen Buchstaben findest du über ein verwandtes
  Wort. Am Wortende klingt es hart, aber du schreibst den Stamm-Buchstaben:
  `Hund` (wegen `Hunde`). Bei `ä`/`äu` denkst du ans Stammwort: `Hände` (wegen
  `Hand`), `Bäume` (wegen `Baum`)."
- **Examples:** `Hund`, `Tag`, `Wald`, `Berg`, `lustig`, `Hände`, `Bäume`,
  `läuft`, `kälter`.

### 5. `morphem` — morphematisches Prinzip (Wortbausteine)
- **Rule:** the word is built from recognizable morphemes — a high-confidence
  inseparable prefix (`ver/vor/ent/zer/über/unter/…`), a derivational suffix
  (`ung/heit/keit/schaft/lich/bar/…`), a compound boundary, or a separable
  particle read off the inflection table (`baue ab`).
- **Citation:** Eisenberg/Fuhrhop morphematisches Prinzip; Thomé Wortstamm/
  word-formation.
- **Explanation:** „Das Wort besteht aus Bausteinen — Vorsilbe, Nachsilbe oder
  mehreren Wörtern. Kennst du die Bausteine, schreibst du es richtig:
  `un-freund-lich`, `Haus-tür`, `Freund-schaft`."
- **Examples:** `verstehen`, `Freundschaft`, `unglaublich`, `Haustür`,
  `abbauen`, `Geburtstag`.

### 6. `merkwort` — genuine exception (sonstige Orthographeme)
- **Rule:** a grapheme that cannot be derived by the rules above — IPA-confirmed
  irregular mappings: `v`→[f] in a native word (`Vater`, `Vogel`), word-initial
  `ch`→[k] (`Chor`, `Charakter`), foreign `th/ph/rh` (`Theater`, `Physik`),
  word-initial `c`→[ts]/[s] (`Cent`). **Narrowed**: high error-rate or "it's a
  function word" do **not** trigger merkwort.
- **Citation:** Thomé group 4 ("11 sonstige Orthographeme"); etymologisches
  Prinzip.
- **Explanation:** „Dieses Wort folgt keiner einfachen Regel — seine Schreibung
  musst du dir merken. Oft kommt es aus einer anderen Sprache: `Chor` (`ch` wie
  k), `Vater` (`v` wie f), `Theater` (`th`)."
- **Examples:** `Vater`, `Vogel`, `Chor`, `Theater`, `Cent`, `Rhythmus`.

### 7. `grossschreibung` — syntaktisches/wortübergreifendes Prinzip
- **Rule:** the word is a noun (word_type = substantiv, or article der/die/das).
- **Citation:** amtliches Regelwerk Großschreibung; syntaktisches Prinzip.
- **Explanation:** „Nomen (Namenwörter) schreibt man groß: `der Hund`, `die
  Schule`, `das Haus`."
- **Examples:** every noun — cross-cutting; combines with any other tag.

## Primary-category pick (when several fire)

`grossschreibung` is orthogonal (a noun can also be a doubling/dehnung/… word).
Among the orthographic strategies, primary = the most marked / highest-leverage
"teaching point", with `klangtreu` last as the residual:

```
merkwort > verwandt > doppelkonsonant > dehnung > morphem > klangtreu
```
`grossschreibung` is primary **only** when the word is a noun whose other
strategies are all `klangtreu` (e.g. `Nase`, `Schule`) — i.e. capitalization is
the sole notable feature; otherwise it is secondary. *(This rule is tunable
against the exemplar gold; it fixes the prior classifier's over-dominant
grossschreibung-primary at 49%.)*

## Multi-feature words (worked examples)

| word | tags | primary | why |
|---|---|---|---|
| `Mann` | doppelkonsonant, grossschreibung | doppelkonsonant | short a + nn; noun |
| `Schule` | grossschreibung | grossschreibung | long u, no marker (regular); noun |
| `Stuhl` | dehnung, grossschreibung | dehnung | long u + h; noun |
| `Hund` | verwandt, grossschreibung | verwandt | final d→[t]; noun |
| `Hände` | verwandt, grossschreibung | verwandt | ä←Hand; noun |
| `Freundschaft` | morphem, verwandt, grossschreibung | verwandt | -schaft; d→[t]; noun |
| `Vater` | merkwort, grossschreibung | merkwort | v→[f]; noun |
| `gehen` | dehnung | dehnung | silbentrennendes h |
| `alle` | doppelkonsonant | doppelkonsonant | short a + ll (was wrongly klangtreu) |

## Validation & build plan (after this spec is approved)

1. Build `spelling_strategy_gold.csv` (principle-based, hand-verified — draft
   below) as the regression fixture; keep `532Strategien.csv` only for a
   "do we wildly diverge?" advisory diff.
2. Rewrite the classifier (renamed `spelling_strategy_classifier.py`), feature
   extractor, validator, tests — no method-brand terms; emit `spellingStrategy`
   (list), `spellingStrategyPrimary`, the Thomé 5→ now-aligned view, **and a new
   `spellingExplanation`** field per word.
3. Re-tag the DB, re-ship the asset, rewrite PLAN §6, update the app-facing
   license/about text to the linguistic framing.

## Draft exemplar gold (for review — ~per category)

`primary` | `all` (space-sep) | word
- klangtreu: `malen` `lesen` `Nase`(+gross) `Blume`(+gross) `rot` `Hose`(+gross)
- doppelkonsonant: `Tasse`(+gross) `Puppe`(+gross) `Wasser`(+gross) `alle` `rennen` `Mann`(+gross) `Ball`(+gross) `Bett`(+gross) `Glück`(+gross) `Katze`(+gross) `Platz`(+gross) `schnell`
- dehnung: `Bahn`(+gross) `Stuhl`(+gross) `mehr` `Saal`(+gross) `Boot`(+gross) `Meer`(+gross) `Brief`(+gross) `Tier`(+gross) `gehen` `Ruhe`(+gross)
- verwandt: `Hund`(+gross) `Tag`(+gross) `Wald`(+gross) `Berg`(+gross) `lustig` `Hände`(+gross) `Bäume`(+gross) `läuft` `Dieb`(+gross)
- morphem: `verstehen` `Freundschaft`(+gross) `unglaublich` `Haustür`(+gross) `abbauen` `Geburtstag`(+gross,+verwandt)
- merkwort: `Vater`(+gross) `Vogel`(+gross) `Chor`(+gross) `Theater`(+gross) `Cent`(+gross) `viel`
- grossschreibung-primary: `Nase` `Schule` `Banane` `Tomate` `Auto`

(The final CSV will carry the full tag set + a one-line note per word.)
