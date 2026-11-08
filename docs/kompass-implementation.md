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

## Validation and release evidence

Each checkpoint records what was implemented and validated. Required checks include deterministic export/schema validation, all source task and passage references, rubric/point preservation, automatic vs pending grading, hint/retry separation, progress persistence, planner budgets, responsive widgets, Flutter analysis/tests, and a web build. Primary-school teacher review and a learner timing pilot remain human evaluation tasks; automated checks must not label them completed.

Official references: https://bildungsplaene-bw.de/25863460 and https://ibbw-bw.de/Startseite/Kompetenzmessung/Kompass%2B4%2B-%2B2025 . Original official papers stay linked under their own terms; the interactive course uses project-authored materials.
