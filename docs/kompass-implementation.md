# Kompass 4 Deutsch learning pathway

Implementation branch: `codex/kompass4-learning-path-20261108` in WordUniverse and kompass4.

## Scope

- Bundle the four original German practice forms (96 tasks), 27 project competency IDs, passages, rubrics, and printable links from kompass4.
- Add reading evidence, productive spelling strategies, sentence work, instruction practice, transfer items, an optional start check, independent checks, and a time-budgeted daily plan.
- Keep school curriculum (BW Deutsch V2, 2024; applicable to grade 4 in 2026/27), vocabulary difficulty, taught status, and assistance separate.
- Preserve partial credit and keep semantic free responses pending until explicit rubric review. App observations are not official Kompass levels or school recommendations.
- Correct SRI review identity, skill attribution, maintenance review, mastery consistency, and spelling-context selection. Restore reliable native SQLite builds without bypassing integrity checks.
- Integrate BW1/BW3 vocabulary selections, course entry points, local progress, resume, reset, parent observations, and paper practice.

## Content contract

`assets/kompass/bw_de_v1.json` is generated from a pinned kompass4 revision. Top-level fields: schemaVersion, id, version, locale, competencies, stimuli, tasks, tests. Tasks preserve print blocks and add structured response parts. Each part has a stable id, type, prompt, maximum points, answer policy, rubric and explicit accepted answers or review requirement. Types: singleChoice, multiChoice, text, evidence, order, review. Evidence anchors refer to logical source lines, independent of mobile wrapping. Matrix time estimates are seconds; print-task minutes are converted explicitly.

The course runs from bundled original content without requiring the general German dictionary download. Optional word games use the existing language-pack gate. Course and vocabulary results remain distinct.

## Learner experience

Select **Kompass 4 · BW Deutsch** during onboarding or in Settings. Existing
learner goals retain their stored enum indices; Kompass is appended. The course
is also directly available from Home and the game menu. Its German learning
content is independent of the interface language. Choosing this goal skips the
initial dictionary download prompt; optional word games still ask for their pack.

The dashboard offers a persisted 5/10/15/20-minute plan, an optional start check,
four focused practice modes, and four complete practice papers:

| Mode | Learning action |
| --- | --- |
| Lesedetektiv | Read a passage/table, choose evidence and explain meaning |
| Wörter prüfen | Produce spellings, use strategies and correct errors |
| Satzwerkstatt | Work with word forms, sentence parts and punctuation |
| Auftragspilot | Understand instructions, quantities and operation order |

All **96 original tasks** are included, plus **8 instruction activities** and
**9 transfer tasks**. The bundle contains **264 separately scored response
parts**, **27 competency IDs**, **6 stimuli**, and **8 original PDF booklets**.
PDF save/share and print actions work independently of preview rendering.
The paper-answer workflow keeps its own review provenance.

Reading passages remain available beside the task on wide screens and in an
expandable panel on phones. Logical line numbers survive wrapping. Authored
emphasis is rendered safely. Multiple criteria for one sentence share one
answer field. The course supports portrait, landscape and enlarged text.

## Evidence, scoring and persistence

- Exact authored policies score closed answers. Unicode NFC and whitespace
  normalization preserve German capitalization, umlauts and ß where assessed.
  Exact semantic exemplars can score automatically; other nonempty variants
  remain pending under `reviewOnMismatch` instead of being rejected by spelling.
- Each criterion keeps its own points, including half-points. Pending points
  remain visible outside the reviewed denominator. An incorrect choice cannot
  cancel an independently correct explanation. Rubric review explicitly records
  self, parent or teacher attribution.
- Hints, read-aloud, adult help, retries and previously seen passages retain
  assistance records. Independent checks use fresh tasks and fresh passages
  from topics not marked “not taught yet.” Reusing a text within one new
  session is recorded as the same reading context.
- Subject observations exclude instruction-game results. A correct subpart
  cannot establish complete mastery while another criterion for that skill is
  unresolved or only rubric-reviewed. Automatic evidence for a different skill
  in the same task remains available.
- The local “secure” state requires three complete, successful independent
  first attempts across at least two days and two contexts, with recent
  evidence. The recent-three window allows recovery after early difficulties.
  These are conservative app rules, not calibrated KOMPASS test levels.
- Planning includes passage-reading time once per session, excludes topics
  marked not taught, reserves transfer items, and limits instruction warm-ups
  in mixed plans. Timing values are estimates, not speed requirements.
- Attempts preserve raw answers, part-specific skill IDs, assessment source,
  original prompt/rubric/credit steps, task/course versions, and course content
  fingerprints. Drafts survive navigation and reload; changed content cannot
  silently resume against a different answer policy. Malformed records and
  drafts are retained for recovery, and failed local writes are visible.

## BW vocabulary and existing games

The optional BW1/BW3 preset uses the verified membership and separately authored
lexical correction assets. See [the source audit](bw-vocabulary-coverage.md) for
exact receipt hashes, source-case distinctions, repaired importer losses and
the boundary between official membership and project-authored definitions.
Curriculum membership is separate from app difficulty and individual mastery.

SRI review now preserves exact skill/context identities, readable legacy data,
maintenance reviews and recovery after mistakes. Seven review formats assess
the original tracked skill. Legacy reading/sentence/case/punctuation cards that
lack their original task remain due; arbitrary replacement questions cannot
earn comprehension credit. Rescue enforces German spelling and capitalization;
Memory and Word Find identify recognition/assistance and avoid treating memory
guesses as language failures. Spelling Spotter uses the actual grade context.

Review identities carry stable lexical IDs and exercise contexts so case and
sense distinctions (for example, `Arm`/`arm` and the two senses of `sein`) cannot
silently merge. Legacy cards are adopted only when their word and context can
be resolved conservatively. Unsupported inflected-form reviews remain pending.
The daily warm-up falls back to an available vocabulary activity when no safe
review round exists, without consuming the unresolved cards.

Sentence completion displays an explicit lexical meaning clue before scoring,
accepts the verified form that reconstructs the source sentence, and excludes
known synonym/shared-gloss alternatives. Unsupported inflection guesses and
verified malformed adjective contexts are rejected. The clue explicitly says
the word *can* have that meaning: a dictionary's leading sense is not assumed
to match the example's sense. Results record vocabulary-in-context evidence,
not sentence-structure mastery. These gates reduce known ambiguity without
claiming that the whole source dictionary has been linguistically reviewed.

The confirmed progress reset clears game session totals, adaptive-promotion
wins, learner session and daily-plan totals, streaks, SRI, cognitive observations
and Kompass progress. The confirmation waits for persistence to complete.
It retains the learner's goal, onboarding completion and language preferences.
Unknown cognitive skill IDs and malformed neighboring records are preserved
without attributing them to a known skill; unreadable data are backed up before
new observations overwrite the primary record.

The native SQLite retry wrapper handles a transient artifact-checksum failure
before tests start. It retains integrity verification and does not retry actual
test failures; a persistent mismatch still fails.

## Validation and release evidence

Validation on **2026-11-08**, with Flutter **3.44.2**, passed against code
checkpoint `c84f763424d63d11063c03e661aaf934341bfaac`. The final documentation
checkpoint does not change application code. The companion kompass4 source head
is `6b48d7a3e0ed13bb966d7a390e049bbe9e177909`.

| Gate | Result |
| --- | --- |
| Complete Flutter VM/widget suite | **1,011 passed**, 27 declared skips, zero failures |
| Explicit shipped-pack pools, item provenance and German forms | **23 passed**, zero failures |
| Static analysis with `--fatal-infos` | No issues |
| Release web build (JavaScript target) | Passed |
| kompass4 Python suite | **74 passed**, including 19 interactive-export regressions |
| BW source/import pipeline regressions | **11 passed** |
| Vocabulary evidence metadata regressions | **13 passed** |
| Native download retry policy regressions | **5 passed** |
| Deployment configuration regressions | **5 passed** |
| Browser storage/install-path suite | **60 passed** in GitHub Actions |
| Playwright harness tests | **19 passed**, zero skips |
| Live browser scenarios A–F | **Passed** against the PR web build |

The full Flutter run includes the course engine, half-point and pending-review
policies, passage freshness, assisted evidence, content fingerprints, rubric
snapshots, persistence/reload/reset, planner budgets, responsive widgets,
portrait print actions after preview failure, exact BW membership, lexical
identity, and readable review labels in both UI languages. Phone and desktop
course renders were also inspected. The explicit pack gates open the actual
bundled English database and the pinned German artifact; the new BW overlay
live tests run in the full suite when `WU_PACK_DE` is set. No golden-update
mode was used for the final pass.

Reproduce the application gates after installing dependencies and obtaining
the German artifact declared in `lib/core/models/language_pack.dart`:

```sh
export WU_PACK_DE=/absolute/path/to/verified/grundwortschatz.db
flutter analyze --no-pub --fatal-infos
python3 tools/ci/flutter_native_retry.py -- flutter test --no-pub --reporter expanded
WU_PACK=1 python3 tools/ci/flutter_native_retry.py -- flutter test --no-pub --reporter expanded \
  test/live/shipped_pack_pools_live_test.dart \
  test/live/item_provenance_live_test.dart \
  test/live/german_forms_live_test.dart
flutter build web --release --no-pub
python3 -m unittest discover -s pipeline/voc-de -p 'test_bw_source_lists.py' -q
python3 -m unittest discover -s pipeline/voc-de -p 'test_*evidence.py' -q
python3 tools/ci/flutter_native_retry_test.py
node --test tools/deployment-config.test.mjs
```

In the companion repository, run `python3 -m unittest discover -s tests -q`.
The German artifact SHA-256 is
`b050d7d25f1a0ed373ae2b9f8d079a4c459c9536f3c2081fbc3cc9017e22f8f3`;
the runtime correction layer leaves its bytes unchanged. The source CSV's
original BOM/CRLF are preserved, and whitespace verification permits CRLF.

### Recovered CI evidence

On **2026-11-09**, the recovery review verified that both previously pending
workflows completed successfully against saved head
`bce58969b0c853d7102f26d43ed9ed3cfd11c070`:
[CI / CD](https://github.com/CrispStrobe/WordUniverse/actions/runs/42520060650)
and [Web e2e](https://github.com/CrispStrobe/WordUniverse/actions/runs/42520060641).
Their job logs confirm the browser results above; no pending or failed check
remained at that checkpoint. The browser scenarios cover language setup, real
pack installation, pause/resume, persistence after reload, and a playable
definition quiz. They do not cover the Kompass player; the course has separate
VM/widget tests. Deployment was skipped for the pull-request runs.

### Remaining external validation

- **Classroom validation:** primary-school teacher review of digital mappings,
  new activities and authored lexical corrections, plus a learner timing pilot,
  remain human evaluation tasks. Content stays explicitly draft until reviewed.
- **Build target:** the JavaScript web release succeeds. The existing
  `flutter_tts` dependency still reports WebAssembly dry-run compatibility
  warnings; this work does not certify a Wasm build.

Official references: https://bildungsplaene-bw.de/25863460 and https://ibbw-bw.de/Startseite/Kompetenzmessung/Kompass%2B4%2B-%2B2025 . Original official papers stay linked under their own terms; the interactive course uses project-authored materials.
