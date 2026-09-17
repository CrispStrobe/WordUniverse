Headless live tests (Playwright, real Chromium) for language setup and downloads.
No preferences or language databases are seeded: each scenario has fresh storage.

Install without modifying the repository:
  npm install --prefix /tmp/wu-playwright playwright
  PLAYWRIGHT_BROWSERS_PATH=/tmp/wu-browsers /tmp/wu-playwright/node_modules/.bin/playwright install chromium

Build current source and serve it (separate terminal):
  flutter build web
  python3 -m http.server 18100 -d build/web

Run from any directory:
  NODE_PATH=/tmp/wu-playwright/node_modules PLAYWRIGHT_BROWSERS_PATH=/tmp/wu-browsers /path/to/words-universe/tools/e2e/run.sh

Optional environment variables:
  BASE_URL=http://127.0.0.1:18100
  EVIDENCE_DIR=/tmp/wu-live-evidence

The .mjs uses createRequire('playwright'), so NODE_PATH works. Evidence directory
is created automatically. Results JSON, run log, screenshots, semantic snapshots
and preference snapshots are saved, including on scenario exceptions. Failed
assertions, timeouts, or any pageerror make the process exit nonzero. Scenarios
continue after failures to collect evidence; do not interpret a completed run as
passing without checking its exit status and results.json.

Scenarios:
  A: Distinct picker legends and immediate German interface switch.
  B: Full onboarding, German preference retained after declining initial pack,
     launch gate, consent, download progress, pause/resume, playable quiz.
  C: Decline game download, launch again, re-consent, finish and play.
  D: Install, play, reload same browser storage, launch and play without consent.
  E: English learning + German interface through full learner onboarding,
     persisted independent preferences, playable English quiz with German UI,
     preferences and German home retained after reload.

Game assertions require the actual question prompt, four answer buttons, nonempty
content, 1/10 counter, and advancement to 2/10 after answering. A menu title never
counts as a running game. Scenarios assert absence of error UI and pageerrors.
Downloads use the actual configured endpoint; network or endpoint failures fail
this live suite (not silently skipped). Pause coverage requires the transfer to
still be in progress when the button is clicked.

Related fast tests:
  flutter test test/learner_onboarding_language_test.dart test/language_setup_flow_test.dart
  flutter test --platform chrome test/core/services/db_platform
  flutter test test/core/services/db_platform

Native file-cache tests are VM-only; Chrome runs the IndexedDB cache test plus
platform-independent transport/controller/gzip tests.
