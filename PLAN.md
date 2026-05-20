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

### [ ] 4. Extract the voc falling-tile game template
`grossschreib`, `grossstadt`, `wortbaumeister`, `verbtrenner` share
~80% of their ~800-line bodies (timer setup, drop animation, score
state, level-up logic). A `FallingTileGameBase` mixin or
`FallingTileGameScreen<T>` widget would remove ~2000 lines of
duplication and make game #5 a thin file.

### [ ] 5. Split game files > 1500 LoC
- `arithmancer_duel_game.dart` (~3000)
- `arithmancer_crosswords_game.dart`
- `codebreaker_game.dart` (2070)
- `hyperdrive_gates_game.dart`
- `space_word_rescue_game.dart` (1600)
- `magic_triangles_game.dart`
Mixing logic, painters, puzzle generation, and widget building. Pull
painters into their own files; move puzzle generation into
`lib/features/games/logic/`.

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

### [ ] 7. Replace color-only feedback
Many games flash red/green for wrong/right. ~8% of boys have color
blindness. Add shape / icon / haptic to every win/fail state.

### [ ] 8. Add `Semantics` annotations
Screen readers currently can't describe game state. Math apps in
particular are near-unusable for low-vision learners. Label every
interactive element.

### [ ] 9. Respect OS text scaling
Fixed `fontSize: 12` (and similar) doesn't scale. Use
`MediaQuery.textScaler` or `Theme.of(context).textTheme` consistently.

### [ ] 10. Touch targets ≥ 48dp
Some games (dial gestures in cryptex, falling-tile choice buttons)
have undersized hit areas.

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

### [ ] 17. Cap Gradle daemon heap
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

## Execution order

Picking off three at a time. Current focus:
1. **#2 contract tests** (now)
2. **#1 crash reporting** (next)
3. **#3 voc audio decision** (next)

Then re-evaluate.
