// Exercise the bundled course through real browser UI and read-only persistence
// assertions. No learner preferences, answers or progress are seeded.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { chooseFromMenu } from './menu.mjs';

const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:18100';
const root = path.resolve(process.env.EVIDENCE_DIR || 'tools/e2e/evidence');
fs.mkdirSync(root, { recursive: true });
const evidence = fs.mkdtempSync(path.join(root, 'kompass-'));
const result = {
  status: 'running', baseUrl, commit: process.env.GITHUB_SHA || null,
  startedAt: new Date().toISOString(), assertions: [], pageerrors: [], packRequests: [],
};
const save = () => fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(result, null, 2) + '\n');
const button = (page, name) => page.getByRole('button', { name, exact: true });
const progressKey = 'flutter.kompass_progress_v1';
let browser, page;
save();

async function snapshot(name) {
  fs.writeFileSync(path.join(evidence, `${name}.aria.txt`), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(evidence, `${name}.png`) });
  fs.writeFileSync(path.join(evidence, `${name}.progress.json`), JSON.stringify(await progress(), null, 2) + '\n');
  const editors = await page.getByRole('textbox', { name: 'Deine Antwort', exact: true })
    .evaluateAll(fields => fields.map(element => ({
      tag: element.tagName, value: element.value, focused: element.matches(':focus'),
      root: element.getRootNode().nodeName, style: element.getAttribute('style'),
      activeTag: document.activeElement?.tagName,
    })));
  fs.writeFileSync(path.join(evidence, `${name}.editors.json`), JSON.stringify(editors, null, 2) + '\n');
}

// Flutter may merge adjacent Text widgets into one accessibility label. Wait
// for the visible semantics, without depending on a separate DOM text node.
async function waitForAccessibleText(text) {
  const deadline = Date.now() + 30000;
  let semantics = '';
  while (Date.now() < deadline) {
    semantics = await page.locator('body').ariaSnapshot();
    if (semantics.includes(text)) return;
    await page.waitForTimeout(100);
  }
  assert.fail(`Accessible text not found: ${text}\n${semantics}`);
}

async function navigate() {
  await page.goto(baseUrl, { timeout: 90000 });
  const semantics = page.locator('flt-semantics-placeholder');
  await semantics.waitFor({ state: 'attached', timeout: 90000 });
  await semantics.evaluate(element => element.click());
}

async function progress() {
  return page.evaluate(key => {
    const raw = localStorage.getItem(key);
    if (raw === null) return null;
    const value = JSON.parse(raw);
    return typeof value === 'string' ? JSON.parse(value) : value;
  }, progressKey);
}

async function focusAnswer(field) {
  await field.click();
  // Flutter 3.44's semantic input exists before its editing bridge is active.
  // Let the focus action and its semantics update render before typing or
  // reading a restored value. Inline CSS is not an editing-readiness signal.
  const focused = await field.evaluate(element => new Promise(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve(element.matches(':focus'))));
  }));
  assert(focused, 'the answer editor keeps focus through its rendered update');
}

async function enterAnswer(field, partId, value) {
  await focusAnswer(field);
  await field.pressSequentially(value, { delay: 30 });
  await waitForProgress({ partId, value });
}

// Wait for actual persisted data, rather than a fixed debounce delay. Reading
// localStorage here cannot manufacture a successful draft or score.
async function waitForProgress(expected) {
  await page.waitForFunction(({ key, expected }) => {
    const raw = localStorage.getItem(key);
    if (raw === null) return false;
    const value = JSON.parse(raw);
    const state = typeof value === 'string' ? JSON.parse(value) : value;
    if (typeof expected === 'object') {
      return state.activeSession?.answers?.d1_01?.[expected.partId] === expected.value;
    }
    if (expected === 'draft') {
      const draft = state.activeSession;
      return draft?.answers?.d1_01?.a === 'Montag'
        && draft?.answers?.d1_01?.b === 'Abstellraum'
        && draft?.assistance?.d1_01?.includes('hint');
    }
    if (expected === 'first-score') return state.attempts?.length === 1;
    if (expected === 'second-score') return state.attempts?.length === 2;
    return state.activeSession === null && state.attempts?.length === 2;
  }, { key: progressKey, expected });
}

function passed(message) {
  result.assertions.push(message);
  console.log(`PASS ${message}`);
  save();
}

try {
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
  page = await context.newPage();
  page.setDefaultTimeout(30000);
  page.on('pageerror', error => result.pageerrors.push(error.message));
  page.on('request', request => {
    const url = new URL(request.url());
    if (/grundwortschatz[^/]*\.db(?:\.gz)?$/i.test(url.pathname)) {
      result.packRequests.push(url.origin + url.pathname);
    }
  });

  await navigate();
  await chooseFromMenu(page, button(page, 'Interface language English'), 'Deutsch');
  await button(page, 'Weiter').click();
  await page.getByRole('checkbox', { name: 'Kompass 4 · BW Deutsch', exact: true }).click();
  await button(page, 'Meinen Lernplan vorbereiten').click();
  await button(page, 'Kompass 4 · BW Deutsch').click({ timeout: 60000 });
  await button(page, 'Jetzt üben').waitFor();
  assert.equal(await button(page, 'Herunterladen').count(), 0);
  assert.equal(result.packRequests.length, 0, 'course does not request a dictionary');
  passed('Kompass onboarding opens the bundled course without downloading a word pack');
  await snapshot('dashboard-desktop');

  // The first full practice form gives a stable two-part reading task, followed
  // by a judgment/evidence task with independently awarded points.
  await button(page, 'Mit Hilfe üben').first().click();
  await waitForAccessibleText('Aufgabe 1 von 24');
  await waitForAccessibleText('Antworte kurz. Einzelne Wörter genügen.');
  const answers = page.getByRole('textbox', { name: 'Deine Antwort', exact: true });
  await enterAnswer(answers.nth(0), 'a', 'Montag');
  await enterAnswer(answers.nth(1), 'b', 'Abstellraum');
  await button(page, 'Tipp 1').click();
  await waitForProgress('draft');
  const draft = await progress();
  assert.equal(draft.attempts.length, 0, 'typing a draft does not award points');
  const sessionId = draft.activeSession.sessionId;
  passed('Reading answers and hint use persist before submission, without awarding points');
  await snapshot('reading-draft-desktop');

  await page.setViewportSize({ width: 390, height: 844 });
  await navigate();
  await button(page, 'Kompass 4 · BW Deutsch').click({ timeout: 60000 });
  await button(page, 'Fortsetzen').click();
  await waitForAccessibleText('Aufgabe 1 von 24');
  await focusAnswer(answers.nth(0));
  assert.equal(await answers.nth(0).inputValue(), 'Montag');
  await focusAnswer(answers.nth(1));
  assert.equal(await answers.nth(1).inputValue(), 'Abstellraum');
  assert.equal((await progress()).activeSession.sessionId, sessionId);
  await button(page, 'Lesetext').click();
  await waitForAccessibleText('Zeile 25');
  const passage = await page.locator('body').ariaSnapshot();
  assert.match(passage, /Zeile 25/, 'logical source lines remain available after phone reflow');
  assert.match(passage, /Am Montag wurde der Spielewagen zum ersten Mal auf den Schulhof geschoben\./,
    'assistive tools can read the passage content, not only its line numbers');
  assert.match(passage, /Nach jeder Pause steht der Wagen im Abstellraum neben der Turnhalle\./);
  await snapshot('passage-phone');
  await page.keyboard.press('Escape');
  await button(page, 'Antwort prüfen').waitFor();
  passed('A phone reload restores the same draft and keeps its numbered reading passage accessible');

  await button(page, 'Antwort prüfen').click();
  await waitForProgress('first-score');
  const first = (await progress()).attempts[0];
  assert.equal(first.taskId, 'd1_01');
  assert.deepEqual(first.parts.map(part => part.points), [1, 1]);
  assert(first.assistance.includes('hint'), 'resumed help must remain in the scored attempt');
  assert.equal(first.mode, 'practice');
  assert.equal(first.sessionId, sessionId);
  passed('Resumed correct answers earn their authored points and retain assistance provenance');

  await button(page, 'Weiter').click();
  await waitForAccessibleText('Aufgabe 2 von 24');
  await button(page, 'ja').click();
  // Deliberately wrong judgment, but the right evidence: neither part may
  // overwrite the other's credit. This is source line 24 of Deutsch Test 1.
  await page.getByRole('button', { name: /^24\s+.*Erwachsen/ }).click();
  await button(page, 'Antwort prüfen').click();
  await waitForProgress('second-score');
  const second = (await progress()).attempts[1];
  assert.equal(second.taskId, 'd1_02');
  assert.deepEqual(second.parts.map(part => part.points), [0, 1]);
  assert.equal(second.parts[1].response, 'passage_deutsch1:L24');
  passed('An incorrect judgment preserves the independently correct evidence point');
  await snapshot('partial-credit-phone');

  await button(page, 'Runde beenden').click();
  await button(page, 'Runde abschließen').click();
  await waitForAccessibleText('Ein Schritt weiter.');
  await waitForProgress('finished');
  const completed = await progress();
  assert.equal(completed.attempts.length, 2, 'unanswered tasks are not manufactured failures');
  await snapshot('summary-phone');
  await navigate();
  await button(page, 'Kompass 4 · BW Deutsch').click({ timeout: 60000 });
  await button(page, 'Jetzt üben').waitFor();
  const reloaded = await progress();
  assert.deepEqual(reloaded.attempts, completed.attempts, 'reload neither duplicates nor changes completed attempts');
  assert.equal(reloaded.activeSession, null);
  assert.equal(await button(page, 'Fortsetzen').count(), 0, 'a completed session is not offered for resume');
  assert.equal(result.packRequests.length, 0, 'entire course round works without a dictionary download');
  assert.deepEqual(result.pageerrors, []);
  fs.writeFileSync(path.join(evidence, 'progress.json'), JSON.stringify(reloaded, null, 2) + '\n');
  passed('Completion survives reload exactly once and leaves unanswered tasks unobserved');
  result.status = 'passed';
} catch (error) {
  result.status = 'failed';
  result.error = error.stack || String(error);
  process.exitCode = 1;
  console.error(result.error);
  if (page) await snapshot('FAILED').catch(captureError => console.error(captureError.message));
} finally {
  result.finishedAt = new Date().toISOString();
  save();
  await browser?.close();
  console.log(`Kompass browser smoke ${result.status}: ${evidence}/results.json`);
}
