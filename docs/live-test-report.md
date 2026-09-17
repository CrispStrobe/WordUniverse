# Language setup and resumable downloads: verification

Local verification (2026-09-17):
- flutter analyze: no issues.
- flutter test: 565 passed.
- flutter test --platform chrome test/core/services/db_platform: 20 passed.
- flutter build web: succeeded.
- tools/e2e/language-setup-live.mjs: five scenarios passed in real headless Chromium against http://127.0.0.1:18100, three consecutive strict runs, zero pageerrors.
- Negative harness test against an unavailable port exits nonzero.

Live scenarios use fresh browser contexts and the real Hugging Face dataset:
A. Distinct picker legends and live interface-language change.
B. German consent, progress, pause/resume, installation and playable quiz.
C. Skip preserves German, launching a game reoffers consent, installation succeeds.
D. Reload preserves the installed database and permits gameplay without another download.
E. English learning with German interface survives complete learner onboarding and reload; English quiz is playable.

Gameplay assertions require a question, four answer buttons, and progression from question 1/10 to 2/10 after answering. They do not count a menu or an error dialog as successful gameplay. Saved preferences are checked independently. Page errors and failed scenarios produce a nonzero exit code.

Review found and fixed a real regression: learner onboarding previously overwrote the initial English choice with German. A regression test now covers both mixed-language combinations and learner onboarding no longer changes language choices.

Local evidence: /tmp/wu-strict-live-final (screenshots, accessibility snapshots and results). See tools/e2e/README.md for reproducible commands. Deployment verification must be run separately against the exact published revision before release.
