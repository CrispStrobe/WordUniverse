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

### [/] 1. Crash reporting in both apps
Both ship to App Store / Vercel with zero runtime visibility. Add
Sentry or Firebase Crashlytics. ~30 min of setup; the next real-user
`LateInitializationError` becomes a notification instead of silence.

### [/] 2. Contract test suite (zero tests currently)
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

### [ ] 3. Real (or genuinely absent) audio in voc
Games call `_audioService.playSound('success')` ~15 times. `assets/sounds/`
is empty. Either ship 5-10 short audio files + wire `audioplayers` (dep
already in pubspec), or remove the calls. Current half-state is worst
of both.

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

### [ ] 6. Unify the progression contract
`recordLevelWin` exists but games call it inconsistently — 5 of them
don't pass `mathProblems`; success thresholds (`score > 0` vs `>= 70%`
vs `stars >= 2`) are ad-hoc per game. Define a `GameOutcome` value
type and a single helper `reportOutcome(GameOutcome)` so every game
reports identically.

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

### [ ] 11. Surface the SRI state
Spaced-repetition is tracked but invisible. A "X facts due for review"
chip on the menu + a dedicated review screen would make the SRI
investment legible.

### [ ] 12. Surface the cognitive profile
5 skill categories tracked (arithmetic, spatial3d, spatial2d,
logic, pattern); no UI shows them. This is the actual differentiator
for adaptive learning — should be a visible feature, not internal
state.

### [ ] 13. Parental dashboard
No way for an adult to see what their kid played, struggled with,
mastered. Even a single "Last 7 days" summary screen would be
high-value. (Achievements screen already exists for math; voc needs
one wired.)

### [ ] 14. Document and centralize tuning constants
`_currentLevelWins >= 3 → advance`, SRI half-lives, decoy counts,
difficulty math — all magic numbers scattered through game files. A
`lib/features/games/tuning.dart` with documented constants would make
A/B testing tractable.

---

## Tier 5 — Internationalization

### [ ] 15. voc: consolidate l10n
Mixed German literals (`'Zu langsam!'`, `'Trennbare Verben'`, dialog
titles) with `S.of(context).foo`. Either commit to full l10n (then
voc can ship to English-speaking learners, math app to German) or
remove the half-finished S calls.

---

## Tier 6 — DevOps

### [ ] 16. Add basic CI
A `.github/workflows/ci.yml` running `flutter analyze && flutter test`
on every push would have prevented merging the `package.flutter/` typo
and the 228-error Python-saved-as-Dart file. ~15 minutes to set up.

### [ ] 17. Cap Gradle daemon heap
`org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=512m` in
`android/gradle.properties` of each project. Currently the daemon
balloons to ~5GB after a few builds.

### [ ] 18. Version bumping discipline
`pubspec.yaml` versions look static. Use `cider` or a release script
to enforce semver bumps on each release.

---

## Tier 7 — Game design polish

### [ ] 19. Onboarding per game
First-time players are dropped into the mechanic with no explanation.
A 3-tap "how to play" overlay (showOnce-per-game) would reduce bounce.

### [ ] 20. Difficulty picker beyond grade
Some grade-3 kids want grade-5 challenges. voc has
`useCustomProblemSettings` plumbing but no UI. Add an "easy / normal
/ challenge" toggle per game.

### [ ] 21. Daily-challenge / streak mechanic
Cheapest retention lever in education apps. One streak counter + one
"today's puzzle" rotation across all games.

### [ ] 22. Achievements UI for voc
`AchievementsScreen` exists for math; voc tracks achievements
internally but doesn't surface them. Mirror the math pattern.

---

## Tier 8 — Privacy / compliance (kids app)

### [ ] 23. Privacy policy + age gate + data disclosure
If analytics or crash reporting ever gets turned on, COPPA / GDPR-K
disclosure becomes mandatory. Better to lay groundwork now.

### [ ] 24. Audit data-at-rest sensitivity
SharedPreferences for everything is fine for now. If anything PII is
ever stored, switch to platform secure storage.

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
