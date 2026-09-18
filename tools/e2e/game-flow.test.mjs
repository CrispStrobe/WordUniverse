#!/usr/bin/env node
// Regression tests for the shared quiz probe. These run against real Playwright
// pages, not stubs: the tutorial race that failed scenarios B/C/D on Pages is
// reproduced through the same locator behaviour the live scripts rely on.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { playQuiz } from './game-flow.mjs';

// Browsers live in node_modules (see the setup scripts in package.json), so
// resolve them there unless the caller has pointed somewhere else.
process.env.PLAYWRIGHT_BROWSERS_PATH ??= '0';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const PROMPT = 'Which word is being described?';
const SKIP = 'Skip';

// Mirrors the app's semantics: behind a modal route the game's nodes leave the
// accessibility tree entirely, so the question stops matching by role.
const FIXTURE = `
<body>
  <div id="counter">1 / 10</div>
  <div id="question" role="group">
    <div>${PROMPT}</div>
    <div>a settled agreement between parties</div>
    <button>Vertrag</button><button>Haus</button><button>Baum</button><button>Wasser</button>
  </div>
  <div id="tutorial" hidden></div>
  <script>
    const question = document.getElementById('question');
    const tutorial = document.getElementById('tutorial');
    window.mountTutorial = () => {
      // Flutter destroys the game's semantics nodes behind a modal route, so
      // the question stops matching by role -- not merely aria-hidden.
      question.hidden = true;
      tutorial.hidden = false;
      tutorial.innerHTML = '<div role="dialog"><button id="skip">Skip</button><button>Next</button></div>';
      document.getElementById('skip').onclick = () => {
        tutorial.hidden = true;
        tutorial.innerHTML = '';
        question.hidden = false;
      };
    };
    for (const b of question.querySelectorAll('button')) {
      b.onclick = () => { if (!window.freezeCounter) document.getElementById('counter').textContent = '2 / 10'; };
    }
  </script>
</body>`;

async function withPage(t, html = FIXTURE) {
  const browser = await chromium.launch({ headless: true });
  t.after(() => browser.close());
  const p = await (await browser.newContext()).newPage();
  p.setDefaultTimeout(5000);
  await p.setContent(html);
  return p;
}

// The live failures happened in a narrow window: the snapshot saw the prompt and
// the Skip button was not yet present, then the tutorial mounted before the
// question locator resolved, so count() returned 0. Reproduce that exact
// interleaving by mounting the tutorial as the question count is queried.
function racingPage(p, { times = 1 } = {}) {
  let fired = 0;
  const raceCount = locator => new Proxy(locator, {
    get(target, prop, recv) {
      if (prop !== 'count') return Reflect.get(target, prop, recv);
      return async () => {
        if (fired++ < times) await p.evaluate(() => window.mountTutorial());
        return target.count();
      };
    },
  });
  return new Proxy(p, {
    get(target, prop, recv) {
      if (prop !== 'getByRole') return Reflect.get(target, prop, recv);
      return (role, opts) => {
        const locator = target.getByRole(role, opts);
        if (role !== 'group') return locator;
        return new Proxy(locator, {
          get(t, prop2, r2) {
            if (prop2 !== 'filter') return Reflect.get(t, prop2, r2);
            return (...args) => raceCount(t.filter(...args));
          },
        });
      };
    },
  });
}

const run = (p, opts = {}) => playQuiz(p, {
  prompt: PROMPT, skipLabel: SKIP, deadlineMs: 20000,
  aria: () => p.locator('body').ariaSnapshot(),
  assertHealthy: () => {},
  snap: async () => {},
  ...opts,
});

test('a tutorial mounting as the question resolves is skipped, not a failure', async t => {
  const p = await withPage(t);
  await run(racingPage(p), { aria: () => p.locator('body').ariaSnapshot() });
  assert.equal(await p.locator('#counter').textContent(), '2 / 10', 'answered and advanced');
});

test('a tutorial that keeps returning is still skipped until the quiz is played', async t => {
  const p = await withPage(t);
  await run(racingPage(p, { times: 3 }), { aria: () => p.locator('body').ariaSnapshot() });
  assert.equal(await p.locator('#counter').textContent(), '2 / 10');
});

test('an undismissable tutorial fails at the deadline instead of hanging', async t => {
  const p = await withPage(t);
  await p.evaluate(() => {
    window.mountTutorial();
    document.getElementById('skip').onclick = null; // Skip no longer dismisses.
  });
  await assert.rejects(
    () => run(p, { deadlineMs: 3000 }),
    /No playable question before deadline/,
  );
});

test('a question that never appears fails rather than passing vacuously', async t => {
  const p = await withPage(t, '<body><div id="counter">1 / 10</div><div>Definition Quiz Match</div></body>');
  await assert.rejects(() => run(p, { deadlineMs: 3000 }), /No playable question before deadline/);
});

test('two matching question groups still fail the single-question guard', async t => {
  const p = await withPage(t, FIXTURE.replace('<div id="tutorial"', `<div role="group"><div>${PROMPT}</div></div><div id="tutorial"`));
  await assert.rejects(() => run(p, { deadlineMs: 3000 }), /one actual question|No playable question/);
});

// Scenario B on Pages failed with "waiting for locator('body')": the pack write
// blocked the main thread past the per-call timeout while the download finished.
test('a page stalled by storage writes is waited out and reported, not failed', async t => {
  const p = await withPage(t);
  let stallsLeft = 2;
  const result = await run(p, {
    aria: async () => {
      if (stallsLeft-- > 0) throw new Error("Timeout 500ms exceeded.\nCall log:\n  - waiting for locator('body')");
      return p.locator('body').ariaSnapshot();
    },
  });
  assert.equal(result.stalls.length, 2, 'stalls recorded as evidence');
  assert.match(result.stalls[0].message, /waiting for locator\('body'\)/);
  assert.equal(await p.locator('#counter').textContent(), '2 / 10', 'quiz still played');
});

test('a permanently stalled page still fails, naming the stalls', async t => {
  const p = await withPage(t);
  await assert.rejects(
    () => run(p, { deadlineMs: 3000, aria: async () => { throw new Error('Timeout 500ms exceeded.'); } }),
    /No playable question before deadline \(\d+ page stall\(s\)/,
  );
});

test('a counter that never advances is a real failure, not retried away', async t => {
  const p = await withPage(t);
  await p.evaluate(() => { window.freezeCounter = true; });
  await assert.rejects(() => run(p, { deadlineMs: 3000 }), /Timeout|exceeded/);
});
