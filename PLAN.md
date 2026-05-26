# Improvement Plan — space_math_academy & voc (WortUniversum)

A consolidated punch list across both apps, written after a two-pass audit
(`flutter analyze` clean-up + gameplay/architecture review). Items are
roughly ordered by impact-per-effort. Sibling repo: `../voc` for
WortUniversum (German grammar/vocab); this repo for space_math_academy
(math). Both ship.

## Status legend

- [ ] not started
- [/] in progress
- [x] done
- [-] decided not to do

---

## Tier 1 — Highest leverage (do these first)

### [x] 1. Crash reporting in both apps
Local-first `CrashLogger` that persists `FlutterError.onError` and
`PlatformDispatcher.instance.onError` to a rotating file in app
documents. User-facing `DiagnosticsScreen` (Settings → Diagnostics)
exposes the log read-only with a "Copy to clipboard" action. Nothing
leaves the device unless the user explicitly copies. DSGVO-clean by
design — no third-party processor.

### [x] 2. Contract test suite (zero tests currently)
Most game logic is deterministic (puzzle generators, SRI decisions,
arithmetic generation, separable-verb detection). A `test/contracts/`
directory of consistency tests would have caught most bugs we just
fixed:
- `gameSkillMap` key drift → assert every menu key resolves
- missing `recordLevelWin` → assert every menu-registered game calls it
- `package.flutter/` typo → covered by `flutter analyze` already, but
  could be CI-enforced
- provider tree completeness — assert every `context.read<X>()` in a
  game has an X registered in `main.dart`

### [x] 3. Real audio in voc
Synthesized 5 short royalty-free sounds via ffmpeg (success / failure
/ tap / levelup / whoosh, ~24 KB total). AudioService now uses
audioplayers with per-effect AudioPlayer instances (no
truncation-on-overlap). Normalized call-site names — was a mix of
`'success'` / `'correct.mp3'` / `'whoosh.mp3'`; all collapsed to bare
keys. Background music + TTS remain stubbed until needed.

---

## Tier 2 — Architecture & maintainability

### [-] 4. Extract the voc falling-tile game template
The "~80% duplication" framing turned out to be optimistic. The 4 games
(`grossschreib`, `grossstadt`, `verbtrenner`, `wortbaumeister`) share
*structure* — combo tracking, miss handling, level-up triggers — but
the parameters that differ are intentional pedagogy: different scoring
curves (constant 100 vs `100 + difficulty*20`), different SRI metadata
schemas, different timing (1500ms vs 1200ms delays, 0.92× vs 0.85×
speed multipliers), and meaningfully different UI presentation (falling
sentence vs conveyor item vs verb pair vs compound word). A base class
would need 10+ override hooks and a parameterised UI builder. Each
file already sits comfortably ≤ 1100 LoC and reads standalone — four
readable copies beats `base + override × 4` indirection.

### [x] 5. Split game files > 1500 LoC
Pulled painters, puzzle generation, and game-world models out of six
oversized screen files into sibling `widgets/` and `services/` files.
Results (before → after):
- `magic_triangles_game.dart` 1486 → 973
- `hyperdrive_gates_game.dart` 1747 → 1111
- `arithmancer_crosswords_game.dart` 2126 → 1240
- `codebreaker_game.dart` 2331 → 1143
- `space_word_rescue_game.dart` (voc) 1625 → 1412
- `arithmancer_duel_game.dart` 3495 → 2839 (partial; see below)
arithmancer_duel was reduced by extracting visual effects, mode
selection, and dialogs. The remaining 2839 LoC is intrinsic
3-mode card-combat State — further reduction would require converting
the State's UI builders into stateless widgets with passed-in deps,
which is architectural work, not a file split, and adds significant
constructor boilerplate. Left as-is unless maintenance pain is felt.

### [x] 6. Unify the progression contract
Added `GameOutcome` value type in both projects with `.win` / `.loss`
/ `.fromRatio` named factories. New `GameProvider.reportOutcome(...)`
is the canonical entry point; legacy `recordLevelWin(...)` is now a
deprecated shim. Migrated all 53 call sites (42 space_math, 11 voc)
via a one-shot Python script. Contract tests updated to accept either
pattern.

### [-] 5b. Delete orphan files (`bubble_math_game.dart`)
Skipped by user — leave the orphan in place.

---

## Tier 3 — Accessibility (high stakes for a kids' app)

### [x] 7. Replace color-only feedback
Swept all 11 game screens. Each correct/wrong outcome now pairs the
existing color with at least one of: ✓/✗ icon overlay, thicker border,
`HapticFeedback.lightImpact/heavyImpact`, and (since voc has real
audio) `_audioService.playSound('success'/'failure')`. Colors
unchanged.

### [x] 8. Add `Semantics` annotations
Went from 0 → 77 Semantics calls across the 11 games + shared
`widgets/game_ui.dart`. Wrapped tappable words, draggables, drop
targets, cards, and game-area gesture detectors. Score/level/combo
chips and feedback regions marked `liveRegion: true`. Labels are
inline German per the project's German-first convention (matches
PLAN.md #15 — English ARB is for "surface chrome" only).

### [x] 9. Respect OS text scaling
Added `FittedBox(fit: BoxFit.scaleDown, ...)` to fixed-size top-bar
badges, score numerals, titles, and choice-button labels across all
11 games plus shared `game_ui.dart`. Existing `fontSize:` values
inside FittedBox kept as upper-cap (intentional).

### [x] 10. Touch targets ≥ 48dp
Falling-tile choice buttons in the 4 template games (`grossschreib`,
`grossstadt`, `verbtrenner`, `wortbaumeister`) were already ≥120dp
tall. Letter tiles in `word_builder` are 50×60. Only one undersized
clickable got lifted: the tappable target word in `grossschreib`
now uses `ConstrainedBox(minWidth: 48, minHeight: 48)` +
`HitTestBehavior.translucent`. Top-bar IconButtons stayed at 32dp
in 5 games (widening would push elements off narrow phones).

---

## Tier 4 — Educational integrity

### [x] 11. Surface the SRI state
Added `SriReviewScreen` (read-only) plus a `Badge.count`-style chip on
the home header that shows the number of items due. Tile lists the
toughest tracked items (lowest easiness factor). Mirrored across both
projects.

### [x] 12. Surface the cognitive profile
Added `CognitiveProfileScreen` showing per-skill bars + per-difficulty
chips. Reads from a new `CognitiveProfileService.snapshot` getter
(returns deep copies so consumers can't mutate). Surfaced via the
home header. Mirrored.

### [x] 13. Parental dashboard
Added `ParentDashboardScreen` with 4-digit PIN gate (default `1234`,
changeable from inside the screen, stored in SharedPreferences).
Aggregates GameProvider game progress, SriService mastery, and
CognitiveProfileService strongest/weakest skills. Surfaced from
Settings → About in both projects. Time-bucketing ("last 7 days")
deferred — current data model doesn't timestamp per-attempt; would
need new plumbing.

### [x] 14. Document and centralize tuning constants
Created `lib/features/games/tuning.dart` in both projects with named
constants for `kWinsRequiredForLevelUp`, `kDefaultPassThreshold`,
`kMinAttemptsForMastery`, `kMinTrackedProblemsForMastery`, plus
the SM-2 algorithm constants (`kSm2InitialEasiness`,
`kSm2MinimumEasiness`, etc.). Wired into GameProvider,
CognitiveProfileService, SriService, GameOutcome.

---

## Tier 5 — Internationalization

### [x] 15. voc: consolidate l10n
Picked direction: voc is German-first, English ARB kept for surface
chrome (existing 200+ keys, plus 70 new ones for the polish work
above). The agent-driven cleanup pass lifted ~68 user-visible German
literals across 8 game/UI files into ARB with real English
translations and ICU plurals where needed. Intentionally left inline:
pedagogical content (grammar rule explanations, German example
sentences the games generate), Wiktionary inflection tag strings,
debug-only output. Final state: `flutter analyze` clean, all 3
contract tests passing.

---

## Tier 6 — DevOps

### [x] 16. Add basic CI
`.github/workflows/ci.yml` in both repos runs `flutter analyze
--fatal-infos` + `flutter test` on push to main and PRs against main.
Uses subosito/flutter-action@v2 pinned to Flutter 3.38.5 to match the
local toolchain. Cache is enabled so warm runs are fast. The
`--fatal-infos` flag locks in the "zero issues at any level" bar we
just cleared.

### [x] 17. Cap Gradle daemon heap
`org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=512m` in
`android/gradle.properties` of each project. Currently the daemon
balloons to ~5GB after a few builds.

### [ ] 18. Version bumping discipline
`pubspec.yaml` versions look static. Use `cider` or a release script
to enforce semver bumps on each release.

---

## Tier 7 — Game design polish

### [x] 19. Onboarding per game
New `OnboardingOverlay` widget (shared between projects). One-call
API: `OnboardingOverlay.maybeShow(context, gameKey:..., title:...,
steps:...)` from `initState`. Tracks per-game seen-state in
SharedPreferences so it shows exactly once. Wired into
`magic_triangles_game` (space_math) and `word_sort_game` (voc) as
template demonstrations; other games can adopt by adding 5 lines.

### [x] 20. Difficulty picker
New `DifficultyMode` enum (easy / normal / challenge) on
GameProvider in both projects. Maps to a grade shift of -1 / 0 / +1
clamped to 1..6. `effectiveGrade` getter applied at game launch
time so per-game internals don't need to know about it. Toggle row
at the top of the game menu, persisted in SharedPreferences.

### [x] 21. Daily-challenge / streak mechanic
New `StreakService` (shared between projects). Tracks
current/longest streak + last-played day via local calendar
arithmetic. Auto-heals on load if the player skipped ≥2 days. Marked
played on app launch. Surfaced as 🔥 chip on the home screen when
streak > 0.

### [x] 22. Achievements UI for voc
New voc-only `AchievementsScreen` with a 14-entry catalog matching
the IDs already tracked in `GameProvider._achievements`. Surfaced
from the home header with a trophy icon. German strings inline (see
#15 — voc is German-first).

---

## Tier 8 — Privacy / compliance (kids app)

### [x] 23. Privacy policy + data disclosure
New `PrivacyPolicyDialog` in both projects (English for space_math,
German for voc). 7 sections covering: short summary, what's stored
locally, network behavior, crash report flow, COPPA/GDPR-K
applicability, user reset rights, change policy. Reachable from
Settings → Privacy & data (space_math) / Datenschutz (voc).
Composition: honest claim that nothing is transmitted, no PII
collected, so the consent rules of COPPA + GDPR Art. 8 don't
attach because there's nothing to consent to.

### [x] 24. Audit data-at-rest + reset control
Inventory: 11 SharedPreferences keys in space_math (game_data,
sri_database, cognitive_profile, achievements, gridlock_played_puzzles,
streak_current/longest, debug_force_unlock, language,
starloader_played_ids, settings), plus a 50-entry rolling crash_log
JSONL file. Voc adds: sri_language_database, custom_words,
vocabulary_sets, parent_pin, and the extracted DB. No PII anywhere.
Added "Reset all data" parental-gated action to Settings in both
projects — challenge gate first (math addition), then the existing
reset confirmation dialog. Documented findings in the policy text.

---

## Already done in the audit passes

- `flutter analyze` clean on both projects (was 1662 + 581 issues → 0)
- 35 + 228 compile errors fixed (including the `package.flutter/`
  typo, a Python file mistakenly saved as `.dart`, nullable `S.of`
  accesses, mis-migrated `DragTarget.onAcceptWithDetails` callbacks)
- 657 `withOpacity` + 268 web-equivalent migrated to `withValues`
- `gameSkillMap` reconciled — `solar_panel` / `solarpanel_game`,
  `grid_filler` / `grid_filler_game` keys aligned
- `magic_triangles` and `path_finder` now use `recordLevelWin`
- 6 voc games now wire `recordLevelWin` (`word_memory`,
  `word_builder`, `word_type_whirl`, `wortbaumeister`, `grossstadt`,
  `grossschreib`); `word_type_whirl` got a proper game-over dialog
- voc gzip decompression routed through `compute()` (mobile isolate,
  web microtask boundary)
- `late Timer` races in `asteroid_math` + `bubble_math` fixed
- `arithmancer_crosswords` controller leak fixed (`.stop()` →
  `.dispose()`)
- `signal_triangulation` was firing `recordLevelWin` per guess —
  now fires once per puzzle
- `cryptex_lock_breaker` had no fail path at all — now records on
  back-press during active game + has a proper Try Again dialog
- voc `VocabularyService.initialize()` rethrows on failure +
  treats empty vocab as hard error (was silently leaving games with
  no content)
- voc `AudioService` print → debugPrint stub (release-safe)
- space_math `main.dart` global init order fixed (was relying on
  Dart lazy top-level finals)
- `verbtrenner_game` wired into voc — class renamed, route added,
  menu card added, `gameSkillMap` entry added,
  `recordLevelWin` call added

---

---

## Tier 9 — Vocabulary depth (new games + data surfacing)

Items below leverage the enriched DE+EN DBs that shipped 2026-05-26.
Priority order: 25 → 26 → 27 → 28 → rest.

### [x] 25. Sentence Completion game
Show a `gradeExamples` sentence with one word blanked out. Player picks
the correct word from 4 options (distractors drawn from same grade/CEFR
band). 99% of both DBs have `grade_examples`; grade key is already
stored so difficulty self-differentiates. Works for both DE + EN.
Pedagogically strong: tests vocabulary in authentic context.

### [x] 26. TTS pronunciation
Wire `flutter_tts` (already a dependency stub in `AudioService`) into
SpaceWordRescue so the word is *spoken aloud* before it disappears —
turns it from a visual-memory game into a phonics-aware one. Optionally
expose a speaker icon on any word card for on-demand replay.
`AudioService.speak(text, lang)` → `FlutterTts.speak`.

### [x] 27. Definition Quiz game
Inverse of WordMemory definition mode: show a definition, pick the
matching word from 4 options. Distractors sampled from same CEFR level
so they're plausible. 99% definition coverage means no special filtering
needed. Works DE + EN.

### [x] 28. SRI Review Mode
Dedicated "practice weak words" session on the home screen: pulls the
10 lowest-rated SRI entries and runs them through a compact mixed
mini-game (spelling + definition + example). SRI data already exists;
this is purely a new game entry that reads it. Closes the loop between
SRI tracking and explicit remediation.

### [x] 29. Antonym Flash game
Show a word, tap the antonym from 3 options within a time limit. WordNet
antonyms power the EN side (9 186 entries); OdeNet covers DE. Quick
round-trip game (≤30 s per session), good warm-up complement to
Sentence Completion.

### [ ] 30. Conjugation Drill (DE-only)
Show a verb + pronoun (e.g. "laufen — er ___"), type or pick the
correct form. Powered by `inflectionsPattern.conjugation.Präsens`.
DE-only initially; `supportedLearningLanguages: ['de']`.

### [ ] 31. Word of the Day (home screen)
One word per calendar day on the home screen: definition, one
`gradeExample` sentence, synonym strip. Zero new game logic; drives
daily open rate. Seed from a deterministic hash of `DateTime.now().day`.

### [x] 32. Surface CEFR level badges
Show `cefrLevel` (A1–B2) as a small badge on any word card that
renders in game feedback or review screens. Lets older students
self-select challenge level via a filter in the game menu.

### [ ] 33. Etymology layer (grade 5-6)
Show a short "did you know?" etymology note after a correct answer for
grade 5-6 words. Etymology data present in Wiktionary enrichment JSON
for a large fraction of the DE DB. EN side has it too; gate on
`gradeLevel.index >= 4`.

### [ ] 34. Surface Gutenberg examples
6 274 EN entries have authentic public-domain sentences in
`gutenbergExamples`. Show one of these (labelled "from a real book")
as an alternative example in SpaceWordRescue and WordFind feedback
when `gradeExamples` is absent or already shown.

---

## Execution order

Picking off three at a time. Current focus:
1. **#30 Conjugation Drill** (DE-only, next)
2. **#31 Word of the Day** (home screen widget)
3. **#33 Etymology layer** (grade 5–6 "did you know" panel)
