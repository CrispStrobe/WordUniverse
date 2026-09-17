Headless live tests (Playwright, real Chromium) for language setup and downloads.
No preferences or language databases are seeded: each scenario has fresh storage.

Setup (Node 22+ and npm; macOS/Linux, from repository root):
  npm ci --prefix tools/e2e
  npm run setup --prefix tools/e2e

Playwright 1.63.0 is pinned in the local package.json and integrity-locked in
package-lock.json, matching the scripts' ariaSnapshot API and Chromium revision.
Both the npm dependencies and Chromium live under tools/e2e/node_modules (ignored).
No global install, /tmp install or NODE_PATH is used. On Linux CI, use setup:ci
instead of setup to install OS dependencies too. After npm ci, rerun setup since
ci replaces node_modules, including the locally scoped browser installation.

Fast executable wrapper tests (no browser or network required):
  npm test --prefix tools/e2e
  # alternatively: ./tools/e2e/run.test.mjs

Build current source and serve it (separate terminal):
  flutter build web
  python3 -m http.server 18100 -d build/web

Run ALL A-F from repository root:
  npm run smoke --prefix tools/e2e

Or run from any directory:
  /path/to/words-universe/tools/e2e/run.sh

Production hosts (real downloads, fresh storage for each scenario):
  BASE_URL=https://crispstrobe.github.io/WordUniverse/ npm run smoke --prefix tools/e2e
  BASE_URL=https://wortuniversum.vercel.app/ npm run smoke --prefix tools/e2e

Optional environment variables:
  BASE_URL=http://127.0.0.1:18100
  EVIDENCE_DIR=/absolute/path/to/evidence-root

Default evidence root: tools/e2e/evidence. Each invocation, including a manual
retry, creates a unique timestamp + random-suffix run directory. A-E and F have
separate subdirectories with process.log capturing stdout AND stderr (including
browser startup errors), plus their existing JSON, screenshots, semantic and
preference snapshots. summary.json records target URL, timing, process exit codes,
signals and aggregate status; GitHub runs also record checkout SHA/run/attempt.
A-E/results.json and F/results-f.json contain individual scenario assertions.

There are NO automatic retries. A-E failure still runs F for evidence. The first
nonzero child exit is returned; signal termination and a 15-minute per-script
watchdog also fail. Interruptions retain a non-passing summary and stop the suite.
Do not interpret a completed run as passing without checking status. Manual retry
results are independent: a later pass does not erase or clear the earlier failure;
compare both attempts and report inconsistent results as flaky, not a clean pass.
Use the wrapper, not direct invocation of the legacy scenario scripts, to obtain
unique evidence and aggregate A-F status. Neither scenario's assertions are weakened.

GitHub Actions: Production live smoke A-F (live-smoke.yml) can be dispatched
manually and runs nightly at 03:37 UTC against both production hosts, sequentially
to limit download load. It needs only contents:read, no deploy tokens or Flutter
build. Host failures do not cancel the other matrix leg. Runs do not cancel active
runs; setup, test, live and job timeouts bound resource usage. Evidence is uploaded
with always(), retained 14 days, and named by host/run ID/attempt, so GitHub reruns
cannot replace prior artifacts. Production content may differ from checkout SHA;
this is a live deployment/endpoint check, not proof that the checkout was deployed.
No agent cron is installed. Forced runner loss can prevent artifact upload.

CI: .github/workflows/web-e2e.yml runs this suite on pull requests that touch
lib/, web/ or tools/e2e/, and on demand. Prefer that over a local run — the web
build plus a Chromium download is heavy, and a contended machine makes both the
timings and any pause/resume race unreliable. Evidence is uploaded as an
artifact.

Scenarios:
  A: Distinct picker legends and immediate German interface switch.
  B: Full onboarding, German preference retained after declining initial pack,
     launch gate, consent, download progress, pause/resume, playable quiz.
  C: Decline game download, launch again, re-consent, finish and play.
  D: Install, play, reload same browser storage, launch and play without consent.
  E: English learning + German interface through full learner onboarding,
     persisted independent preferences, playable English quiz with German UI,
     preferences and German home retained after reload.
  F: Fresh German-interface pack install, German consent/progress/pause/resume
     and browser-storage status; no English installer text leaks; playable German
     quiz and answer advancement. Decompression evidence is captured only if painted.

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
