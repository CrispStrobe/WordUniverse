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

The native SQLite retry wrapper handles a transient artifact-checksum failure
before tests start. It retains integrity verification and does not retry actual
test failures; a persistent mismatch still fails.

## Validation and release evidence

Each checkpoint records what was implemented and validated. Required checks include deterministic export/schema validation, all source task and passage references, rubric/point preservation, automatic vs pending grading, hint/retry separation, progress persistence, planner budgets, responsive widgets, Flutter analysis/tests, and a web build. Primary-school teacher review and a learner timing pilot remain human evaluation tasks; automated checks must not label them completed.

Official references: https://bildungsplaene-bw.de/25863460 and https://ibbw-bw.de/Startseite/Kompetenzmessung/Kompass%2B4%2B-%2B2025 . Original official papers stay linked under their own terms; the interactive course uses project-authored materials.
