# Games review — findings & fix tracker

## Progress log
- **2026-05-30 — Tier 1 (crashes/hangs/mis-teaching) done & committed:**
  word_find `firstWhere` crash (+ space-strip match) ✓ · space_word_rescue
  `words.first` crash ✓ · word_type_whirl empty-validTypes hang ✓ · hypernym
  exclude-all-hypernyms ✓ · definition_quiz def-leak + double-shuffle ✓ ·
  conjugation plural==infinitive giveaway ✓ · grossstadt malformed nominalization
  (now skips unsafe -e/-el/-er) ✓ · grossschreib proper-noun filter ✓ (DE-guard
  moot: menu-gated) · sentence_completion blank-suffix bound + drop wrong-case
  article ✓ · reverse_translation reverse-synonym guard (+ thin-pool) ✓ ·
  wortbaumeister most-balanced compound split ✓ · verbtrenner mapping
  **verified correct, not a bug**.
- **2026-05-30 — Tier 2 done & committed:** C5 thin-pool — require a full
  option set in translation, expression, spelling_spotter, reverse_translation
  (Tier 1), and both phrasal builders (≥3 options) ✓. **C6 falling-timer race —
  VERIFIED FALSE ALARM**: wortbaumeister/verbtrenner/grossstadt all set
  `_feedbackState` synchronously in both `_handleChoice` and `_handleMiss`, and
  `stop()` completes the TickerFuture immediately — no double-count possible.
- **2026-05-30 — Tier 3 done & committed:** C11 label — `gameCorrectOfTotal`
  now uses `_total` (answered count) not `_index+1` in false_friends, wortfalle,
  phrasal_match, phrasal_power ✓ (homophone/conjugation use hardcoded strings →
  Tier 4). C10 sri_review — now pulls the DUE queue (`getItemsForReview`,
  excludes mastered/not-due) ranked by difficulty, falls back to hardest-overall
  only when nothing's due ✓; records via the item's recovered base id so it
  UPDATES the reviewed item instead of creating a lemma-keyed duplicate ✓.
  (word_builder/word_find/verbtrenner SRI-keying consistency → deferred to Tier 6.)
- **2026-05-30 — Tier 4 batch 1 done & committed** (parallel fixer agents +
  central ARB consolidation, +101 localized keys): **homophone_drill** (was
  ZERO l10n → fully localized + a11y + scroll), **word_builder** (German
  labels → S; fixed per-second whole-board rebuild via `_TimePill`/`read`;
  48dp targets), **word_snake** (educational German → S; empty-state instead of
  silent pop; stale-feedback-timer guard), **space_word_rescue** (German → S;
  `WidgetsBindingObserver` pause-on-background; uniform article-strip), **word_memory**
  (German → S; synchronous tap-race lock; painter repaint gate), **word_sort**
  (German hints/Semantics → S; empty-state; double-drop guard; hoisted lookup).
  Full analyze clean, 465 tests pass.
- **2026-05-30 — Tier 4 batch 2 done & committed** (8 games, +35 keys):
  word_type_whirl, word_find, translation_flash, expression_flash, proverb_cloze,
  conjugation_drill, grossschreib, spelling_spotter (i18n + a11y + the C4 cloze
  fix for expression/proverb + spelling badge-on-wrong). Full analyze, 465 tests.
- **2026-05-30 — Tier 4 batch 3 + Tier 5/6 finish done & committed** (8 games,
  no new keys — reused visible text for Semantics): antonym_flash, synonym_flash,
  hypernym_flash, word_class_flash, cloze_flash (C4 + POS distractors + timer
  pause), definition_quiz (scroll + tap-to-advance + state semantics),
  sentence_completion (scroll + comment fix), grossstadt (isProperNoun filter +
  ms duration + log guards). C2 distractor POS-filtering applied to the semantic
  flash trio; synonym ASCII-regex fixed (keeps ä/ö/ü/ß). a11y `Semantics(button)`
  + ≥48dp across the option-based games. Full analyze clean.
- **Tier 7 (dedup refactors) — DEFERRED (recommended).** Every game now works
  correctly; extracting shared flash/falling/quiz bases is a large structural
  refactor touching ~20 files at once, with regression risk that outweighs the
  maintainability gain at this point. Best done as its own focused effort with
  the games stable. Documented as optional.
- **2026-05-30 — post-sweep follow-ups (separate from the game findings):**
  declined-German-download now falls back to the bundled English DB instead of
  failing app load; Karteikasten skill badges localized; App Store icon
  alpha-flattened; CI auto-deploy to Vercel wired (see root `PLAN.md` #41–#45
  and `README.md → Deploying`).

---


Source: 11 parallel read-only reviewer agents, one family per agent, every game
reviewed individually (2026-05-30). Severity: **[H]** correctness/crash/mis-teach,
**[M]** pedagogy/UX/i18n, **[L]** nit/quality. Check the box when fixed.

> Line numbers are from the review snapshot and may drift — verify against current
> code before editing.

---

## Cross-cutting themes (fix once, help many)

- [ ] **C1 — Hardcoded strings bypass `S`** (i18n + screen-reader a11y). Worst:
  `word_builder` (EN+DE!), `homophone_drill` (no l10n at all), plus German
  Semantics labels in `word_snake`, `space_word_rescue`, `word_memory`,
  `word_sort`, `word_type_whirl`, `translation/reverse/expression_flash`,
  `proverb_cloze`, `conjugation_drill`, `grossschreib`, `grossstadt`, `word_find`.
- [ ] **C2 — Distractors ignore part-of-speech & grade band** → trivially
  eliminable or off-grade-hard. Semantic flash, translation games, `cloze_flash`,
  `definition_quiz`, phrasal verbs.
- [ ] **C3 — Accidentally-*correct* distractors** (real bug): `hypernym_flash`
  (other valid hypernyms), `reverse_translation` (Frau/Ehefrau), `conjugation`
  (plural form == shown infinitive), `definition_quiz` (synonyms / headword in def).
- [ ] **C4 — Lemma-vs-inflected-form mismatch** in cloze games (`cloze_flash`,
  `proverb_cloze`, `expression_flash`, `sentence_completion`): blank shows
  inflected form, options/answer are lemmas.
- [ ] **C5 — Thin-pool 2-option bug**: `if (distractors.isEmpty) return null`
  allows a 2-option MCQ. `translation`, `reverse_translation`, `expression`,
  `spelling_spotter`, both phrasal builders. Require `≥ optionCount-1`.
- [ ] **C6 — Falling-animation timer race** (double-score): `.forward().then(_handleMiss)`
  not cancelled by `stop()`. `wortbaumeister`, `verbtrenner`, `grossstadt`,
  `space_word_rescue`, `word_snake`.
- [ ] **C7 — No pause-on-background**: arcade games lack `WidgetsBindingObserver`
  (`space_word_rescue`, `grossstadt`, `word_snake`, `word_memory`).
- [ ] **C8 — A11y baseline**: options are bare `GestureDetector`, no
  `Semantics(button:true)`, tap targets near/under 48 dp; no reduced-motion.
- [ ] **C9 — Grade difficulty all-or-nothing** (`≥10 in grade else ALL grades`);
  no proximity weighting. Universal.
- [ ] **C10 — SRI integrity**: `sri_review` ignores due-queue + can record to the
  wrong itemId (lemma keying); inconsistent SRI keys across `word_builder`/
  `word_find`/`verbtrenner`.
- [ ] **C11 — `gameCorrectOfTotal(_correct, _index+1)` mislabel** ("0 of 1"
  before first answer). `false_friends`, `wortfalle`, `homophone_drill`, both
  phrasal games, `conjugation`.
- [ ] **C12 — Duplication**: flash games ~95% identical; falling games share UI;
  quiz games share a scaffold. Extract shared base widgets/mixins (do LAST).

---

## Per-game findings

### Semantic flash
**antonym_flash_game.dart**
- [ ] [H] :194 distractors any random word → filter to same `wordType` (+grade) (C2)
- [ ] [H] :580 options no `Semantics`/state announcement (C8)
- [ ] [M] :189 only `antonyms.first` correct → randomize & accept any listed antonym
- [ ] [M] :195 distractor filler list reused across rounds → reshuffle per challenge
- [ ] [L] :298 `_showGameOver` missing `mounted` guard before `showDialog`

**synonym_flash_game.dart**
- [ ] [H] :218 distractors ignore POS (C2); [H] :575 a11y (C8)
- [ ] [M] :201 correct = first clean synonym deterministically → randomize/accept any
- [ ] [M] :185 `_isCleanSynonym` ASCII-only regex drops ä/ö/ü/ß → allow `\p{L}`
- [ ] [L] :218 no self-dedup of distractors; [L] :310 `mounted` guard

**hypernym_flash_game.dart**
- [ ] [H] :215 exclude ALL of word's hypernyms from distractors, not just chosen (C3)
- [ ] [H] :585 a11y (C8)
- [ ] [M] :58 `_abstractENVerbs` filter matches hypernym surface (nouns) — verify field
- [ ] [L] :149 `_pickHypernym` called 3×/word; [L] :308 `mounted` guard

### Translation flash
**translation_flash_game.dart**
- [ ] [H] :192 distractors not grade/difficulty-matched, recur (C2)
- [ ] [H] :238 thin-pool 2-option (C5)
- [ ] [M] :357 `correctInSeconds` likely wrong value (passes elapsed not count) — verify
- [ ] [M] :406/453/552 hardcoded German strings (C1)
- [ ] [M] :618 options a11y + tap target (C8)
- [ ] [L] :312 uncancelable `Future.delayed` advance

**reverse_translation_flash_game.dart**
- [ ] [H] :207 German distractors not clean/length-capped; long compounds give away answer
- [ ] [H] :219 thin-pool (C5)
- [ ] [H] :538 no reverse-synonym guard (two German words → same English) (C3)
- [ ] [M] :387 hardcoded German (C1); [L] :562 long-compound clipping

**expression_flash_game.dart**
- [ ] [H] :247 blanks lemma but expressions store inflected forms → confusing answer (C4)
- [ ] [H] :269 thin-pool (C5)
- [ ] [M] :262 distractor may already appear in visible expression → exclude substrings
- [ ] [M] :442 hardcoded German (C1); [M] :626 blank WidgetSpan no semantics (C8)
- [ ] [L] :247 magic length bounds; not grade-scaled

### Quiz / definition
**definition_quiz_game.dart**
- [ ] [H] :147 `?:` + `..shuffle` precedence → double-shuffle / misleading; split statements
- [ ] [H] :167 definition can contain headword → skip/redact (C3)
- [ ] [M] :413 distractor uniqueness by string not meaning (synonyms ambiguous)
- [ ] [M] :293 2200ms fixed delay blocks reading long banners → tap-to-advance
- [ ] [M] :396 no `SingleChildScrollView` → overflow on small phones
- [ ] [L] :562 `Semantics` omits state after answer (C8)

**word_class_flash_game.dart**
- [ ] [M] :104 `setTtsLanguage` but no audio played → remove or add tap-to-hear
- [ ] [M] :131 ambiguous word_type items (adverb/adj) unfair w/o context
- [ ] [M] :149 binary grade scaling (C9)
- [ ] [L] :518 magic `childAspectRatio` clips long labels

**sentence_completion_game.dart**
- [ ] [H] :227 prefix-blank matches wrong token (Hund→Hunderte) → exact whole-word first
- [ ] [H] :160 comment claims SRI weighting but only shuffles → implement or fix comment
- [ ] [M] :246 DE article case mismatch (der/den) in blank → blank noun only
- [ ] [M] :204 same-type distractor may also fit slot
- [ ] [M] :447 no scroll → overflow

### Cloze / conjugation
**cloze_flash_game.dart**
- [ ] [H] :234 lemma-vs-inflected blank/options mismatch (C4)
- [ ] [H] :242 distractors not POS/length-filtered (C2)
- [ ] [M] :249 no distractor dedup (proverb_cloze has it); [M] :325 timer runs during feedback
- [ ] [M] :676 options a11y (C8); [L] :238 magic length bounds

**proverb_cloze_game.dart**
- [ ] [H] :175/439/486/587 hardcoded German UI strings (C1)
- [ ] [H] :252 lemma-vs-inflected mismatch (acute for proverbs) (C4)
- [ ] [M] :311 timer during feedback; [M] :706 options a11y (C8)
- [ ] [M] :128 `_visibleWordCount` splits on space only → `\s+`+trim
- [ ] [L] :553 inline magic hex colors → theme

**conjugation_drill_game.dart**
- [ ] [H] :151 plural `wir`/`sie` form == shown infinitive (giveaway) → drop or skip (C3)
- [ ] [H] :372 hardcoded German strings (C1)
- [ ] [M] :377 "X von N" off-by-one (uses `_index+1` not `_total`) (C11)
- [ ] [M] :512 options a11y (C8); [M] :178 small-pool may yield <15 rounds silently
- [ ] [L] :162 redundant per-verb extraction

### Spelling / orthography
**spelling_spotter_game.dart**
- [ ] [H] :655 hardcoded `'Common mistakes:'` → ARB (C1)
- [ ] [M] :324 uncancelable `Future.delayed` timers; [M] :443 strategy badge only on correct → also on wrong
- [ ] [L] :162 always same hardest-10 (no shuffle within tier); [L] :251 options can be <4

**grossschreib_game.dart**
- [x] [H] no DE-language guard — **moot**: game is menu-gated to `['de']`, not reachable in EN mode
- [x] [H] :207 proper nouns classed `substantiv`, no `isProperNoun` filter → **fixed** (added `!w.isProperNoun`)
- [ ] [H] :411 `isAtStart = wordIndex < 3` fragile → detect via trimmed `beforeWord` terminator
- [ ] [M] :576 `_totalItems` stays 25 though queue often shorter → set to queue length
- [ ] [M] :98 `_log` arg strings built in all builds → guard call sites
- [ ] [L] :720 hardcoded German Semantics; [L] magic numbers

**syllable_count_game.dart**
- [ ] [M] :623 hint shows `hyphenation.first` but grading used a later entry → store chosen
- [ ] [M] :87 counts hyphenation points not true syllables (EN) — document/accept
- [ ] [M] :96 uppercase-split heuristic can mis-truncate (TV-Gerät)
- [ ] [L] :188 weak grade fallback (grade±1 before all)

### Word construction
**word_builder_game.dart**
- [ ] [H] :599 double `context.watch<GameProvider>()` + 1Hz setState → whole-board rebuild
- [ ] [H] :708 hardcoded German on EN-capable game (C1)
- [ ] [M] :388 SRI key mismatch (records bare word vs `SPELL_` id); `hints_used` always 0 (C10)
- [ ] [M] :416 auto-advance race w/ skip/back → capture token
- [ ] [M] :226 candidate pool rebuilt per word → build once per level
- [ ] [L] :58 `_totalWords` should be final; long words overflow Wrap

**wortbaumeister_game.dart**
- [ ] [H] :224 naive compound splitter → wrong morpheme decomposition shown as truth
- [ ] [H] :266 falling-timer race (C6)
- [ ] [M] :322 shallow difficulty; [M] :199 example may not contain the compound
- [ ] [M] :79 dead `GameMode.trennbareVerben` branch → remove
- [ ] [L] :600 `height-400` magic can go negative → clamp

**verbtrenner_game.dart**
- [x] [H] :996 button→answer mapping — **VERIFIED CORRECT (not a bug)**: `_handleChoice(chooseSeparated)` compares to `shouldBeSeparated`; sibling uses `chooseTogether`/`shouldBeTogether`. Different param semantics, each internally consistent. Optional: named enum (Tier 7).
- [ ] [L] :273 RULE2 infixed `zu` split is only a cosmetic display split; the `zusammen` label is correct → defer to Tier 6
- [ ] [H] :379 falling-timer race (C6)
- [ ] [M] :759 large dead code (`_buildVerbParts`/`_buildSinglePart`) → single forms render as 2 blocks
- [ ] [M] :167 grade filter always +3 above player
- [ ] [L] :69 `_totalItems` final; SRI key inconsistency (C10)

### Sorting / typing
**word_sort_game.dart**
- [ ] [H] :213 `getAllWords`/`getWordsByGrade` in loop → hoist + map
- [ ] [H] :255 silent `Navigator.pop()` on empty pool → empty state
- [ ] [M] :313 single `_feedbackTimer` reused uncancelled; double-drop possible → guard
- [ ] [M] :1043/:558 hardcoded German strings/semantics (C1)
- [ ] [L] :356 untracked hint `Future.delayed`; [L] :935 redundant Opacity

**word_type_whirl_game.dart**
- [ ] [H] :178 `'Adverb'`/`'Pronomen'` hardcoded German (C1)
- [ ] [H] :1102 per-frame `.map().toList()`+trig in AnimatedBuilder → drive from controller
- [ ] [M] :345 empty `validTypes` → round never starts (HANG) → fallback/game-over
- [ ] [M] :1091 first-round spawn before layout → maxRadius guard skips target words
- [ ] [M] :583 untracked delayed closures mutate next round → guard with round id
- [ ] [L] :107 non-final magic fields

**word_find_game.dart**
- [ ] [H] :329 `firstWhere` StateError CRASH on space-stripped mismatch → `orElse`
- [ ] [H] :118 review ids never re-extracted (skill/prefix mismatch) → SRI broken (C10)
- [ ] [M] :248 diagonal selection supported but generator never places diagonals → enable or constrain
- [ ] [M] :9 grid salted with German Ä/Ö/Ü in EN build → pass language to generator
- [ ] [M] :293 grade-6 grid can silently drop words → retry/min-placed
- [ ] [L] hardcoded German type labels in `_getEducationalInfo`

### Arcade
**word_memory_game.dart**
- [ ] [H] :236 tap race allows 3rd card → set `_isChecking` synchronously
- [ ] [H] :437 hardcoded German Semantics/labels (C1)
- [ ] [M] :213 definition-mode language/length mismatch
- [ ] [M] :610 `_CardBackPainter.shouldRepaint` always true → repaint all backs
- [ ] [L] dead code (blanket ignore); no reduced-motion (C8)

**word_snake_game.dart**
- [ ] [H] :369 correct answer advances immediately but stale 4s feedback timer wipes new state
- [ ] [H] :231 puzzle-gen failure pops screen → empty state
- [ ] [M] :455 `_getEducationalInfo` fully hardcoded German (C1)
- [ ] [M] :762 hardcoded Semantics; [M] :309 pan can't deselect (UX)
- [ ] no pause-on-background (C7)

**space_word_rescue_game.dart**
- [ ] [H] :253 `words.first` CRASH when pool empty → guard
- [ ] [H] :295 word-lost vs answer double-count race → set `_isAnswerChecked` synchronously
- [ ] [H] no pause-on-background (C7) — bites hardest here
- [ ] [M] :571 extensive hardcoded German (C1); [M] :462 article-strip inconsistent between paths
- [ ] [L] :275 fading-letters timer not stored

**grossstadt_game.dart**
- [ ] [H] :543 conveyor `.then` stale `_handleMiss` (C6)
- [ ] [H] :354 `_nominalizeAdjective` malformed forms (dunkel→dunkeles; sauer→sau) shown as truth
- [ ] [M] :632 `_handleMiss` no `_feedbackState` guard → double count
- [ ] [M] :100 conveyor duration `toInt()` truncation; [M] :271 fragile proper-noun heuristic
- [ ] [L] :90 verbose `_log` spam

### Confusables
**false_friends_game.dart**
- [ ] [M] service:74 trap `german` word mixed among meaning glosses (format mismatch)
- [ ] [M] :290 `gameCorrectOfTotal` mislabel (C11)
- [ ] [L] :63 `_pulseCtrl` created but never consumed (dead); [L] :182 `mounted` in dialog

**wortfalle_game.dart**
- [ ] [H] :210 no empty/defensive state (spinner forever if catalogue empty)
- [ ] [M] :267 `gameCorrectOfTotal` mislabel (C11)
- [ ] [L] service:30 two-blank example renders raw `___`; [L] predictable correct position

**homophone_drill_game.dart**
- [ ] [H] pervasive hardcoded English — zero l10n (title, onboarding, prompts) (C1)
- [ ] [H] :231 "correct homophones" label wrong in confusables mode
- [ ] [M] service:329 blanks first occurrence, casing cue; stale "preserve capitalisation" comment
- [ ] [M] :333 mislabel (C11); [L] :294 no scroll; [L] requires ALL group words in DB

### Phrasal verbs (EN-only)
**phrasal_verb_match_game.dart**
- [ ] [H] service:216 `min(1,optionCount-1)` only guards zero → allows 2-option (C5)
- [ ] [M] :300 mislabel (C11); [M] service:165 distractors not grade-filtered (C2)
- [ ] [L] `correctMeaning` dead field; no post-answer reinforcement; [L] options a11y (C8)

**phrasal_verb_power_game.dart**
- [ ] [H] service:112 `_blankParticle` blanks first occurrence not target's → unanswerable
- [ ] [H] service:81 empty distractors → single-option MCQ (C5)
- [ ] [M] :398 sentence w/ 0 or ≥2 blanks renders raw; [M] :484 fixed width clips long particles
- [ ] [M] grade-fit: gate to grade 3+ ; [L] options a11y (C8)

### SRI review
**sri_review_game.dart**
- [ ] [H] :167 ignores due-queue (uses `getMostDifficultItems`) → defeats spacing (C10)
- [ ] [H] :326 records to wrong itemId via lemma mismatch (C10)
- [ ] [M] :342 uncancelable 2000ms advance; no dispose cancel; [M] :677 options a11y (C8)
- [ ] [M] :108 `_init` no `mounted` guard after postFrame/await
- [ ] [L] :360 magic `difficulty:3`/`0.7`; [L] :160 `getAllWords` ×3 per build

---

## Fix order (tiers)

1. **Crashes/hangs/mis-teaching** — word_find crash, word_type_whirl hang,
   space_word_rescue/grossstadt crashes & malformed forms, verbtrenner inverted
   mapping, grossschreib DE guard + proper-noun, conjugation giveaway,
   sentence_completion blank, definition_quiz leak, hypernym/reverse distractor,
   empty-pool silent pops.
2. **Thin-pool (C5) + falling-timer race (C6).**
3. **SRI integrity (C10) + label mislabel (C11).**
4. **i18n (C1) + a11y (C8).**
5. **Distractor POS/grade (C2/C9) + cloze inflected-form (C4).**
6. **Quality nits** (final fields, magic numbers, dead code, reduced-motion, perf).
7. **Dedup refactors (C12)** — last, carefully.
