import { createRequire } from 'node:module';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const BASE = process.env.BASE_URL || 'http://127.0.0.1:18100';
const EV = process.env.EVIDENCE_DIR || '/tmp/wu-live-evidence';
fs.mkdirSync(EV, { recursive: true });
const results = {};
const pageerrors = [];
const logs = [];
const log = s => { logs.push(s); console.log(s); };
const aria = p => p.locator('body').ariaSnapshot();
const button = (p, name) => p.getByRole('button', { name, exact: true });
const errors = /\b(error|exception|failed|failure|Fehler)\b|Something went wrong|No definitions available|Keine Definitionen/i;
async function healthy(p) {
  const text = await aria(p);
  assert(!errors.test(text), 'Error UI: ' + text);
  return text;
}
async function snap(p, name) {
  fs.writeFileSync(`${EV}/${name}.aria.txt`, await aria(p));
  await p.screenshot({ path: `${EV}/${name}.png` });
}
async function semantics(p) {
  await p.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
  await p.locator('flt-semantics-placeholder').evaluate(el => el.click());
}
async function prefs(p, learning, ui) {
  const values = await p.evaluate(() => Object.fromEntries(Object.entries(localStorage)));
  fs.writeFileSync(`${EV}/prefs-${learning}-${ui}.json`, JSON.stringify(values, null, 2));
  for (const [key, expected] of Object.entries({ learning_language: learning, language: ui,
    language_setup_complete: true, learner_onboarding_complete: true })) {
    assert.equal(JSON.parse(values['flutter.' + key] ?? 'null'), expected, `saved ${key}`);
  }
}
async function completeOnboarding(p, de = false) {
  await button(p, de ? 'Weiter' : 'Continue').click();
  await button(p, de ? 'Meinen Lernplan vorbereiten' : 'Prepare my learning plan').click({ timeout: 30000 });
  // German requires a pack; declining must not silently select English.
  if (!de) await button(p, 'Not now').click({ timeout: 30000 });
  await button(p, de ? 'Alle Spiele entdecken' : 'Browse all games').waitFor({ timeout: 60000 });
  await healthy(p);
}
async function openGame(p, de = false) {
  await button(p, de ? 'Alle Spiele entdecken' : 'Browse all games').click();
  await p.getByRole('group', { name: de ? /^Definitions-Quiz/ : /^Definition Quiz Match/ })
    .click({ position: { x: 80, y: 45 }, timeout: 30000 });
}
async function consent(p) {
  await button(p, 'Download').waitFor({ timeout: 30000 });
  const text = await healthy(p);
  assert(text.includes('Deutsch pack required') && text.includes('GPL-3.0-or-later'), text);
}
async function game(p, name, de = false) {
  // A menu title (even behind an error dialog) is never proof of a running game.
  const prompt = de ? 'Welches Wort wird beschrieben?' : 'Which word is being described?';
  const deadline = Date.now() + 240000;
  while (Date.now() < deadline) {
    const text = await healthy(p);
    const skip = button(p, de ? 'Überspringen' : 'Skip');
    if (await skip.isVisible()) { await skip.click(); await p.waitForTimeout(500); continue; }
    if (text.includes(prompt)) {
      const question = p.getByRole('group').filter({ hasText: prompt });
      assert.equal(await question.count(), 1, 'one actual question');
      assert.equal(await question.getByRole('button').count(), 4, 'four answer choices');
      assert(/1 \/ 10/.test(text), 'first question counter');
      assert(!/pack required|Paket erforderlich|button "Download"|Definition Quiz Match/.test(text), text);
      const content = await question.innerText();
      assert(content.replace(prompt, '').trim().length > 10, 'nonempty definition and answers');
      await snap(p, name);
      // Exercise a real answer and require the counter to advance.
      await question.getByRole('button').first().click();
      await p.waitForFunction(() => /2 \/ 10/.test(document.body.innerText), null, { timeout: 15000 });
      await healthy(p);
      return;
    }
    await p.waitForTimeout(500);
  }
  throw new Error('No playable question before deadline: ' + await aria(p));
}
async function scenario(name, body) {
  let browser, p;
  const before = pageerrors.length;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
    p = await context.newPage();
    p.setDefaultTimeout(30000);
    p.on('pageerror', e => { pageerrors.push({ scenario: name, message: e.message }); log(`PAGEERROR ${name}: ${e.message}`); });
    await p.goto(BASE);
    await semantics(p);
    await body(p);
    await healthy(p);
    assert.equal(pageerrors.length, before, 'no pageerrors');
    results[name] = { ok: true };
    log('PASS ' + name);
  } catch (e) {
    results[name] = { ok: false, note: e.stack || String(e) };
    log('FAIL ' + name + ': ' + e.message);
    if (p) await snap(p, name + '-FAILED').catch(e => log('Evidence error: ' + e.message));
  } finally {
    if (browser) await browser.close();
    fs.writeFileSync(`${EV}/results.json`, JSON.stringify({ results, pageerrors }, null, 2));
    fs.writeFileSync(`${EV}/run.log`, logs.join('\n'));
  }
}
await scenario('A', async p => {
  await button(p, 'Interface language English').waitFor();
  const text = await healthy(p);
  for (const legend of ['What language do you want to learn?', 'Language for words, exercises and games.',
    'What language should the app use?', 'Language for menus, buttons and instructions.']) assert(text.includes(legend), legend);
  await snap(p, 'A-fresh-picker');
  await button(p, 'Interface language English').click();
  await p.getByRole('menuitem', { name: 'Deutsch', exact: true }).click();
  await button(p, 'Weiter').waitFor();
  const translated = await healthy(p);
  for (const label of ['Willkommen im WortUniversum', 'Welche Sprache möchtest du lernen?',
    'Welche Sprache soll die App verwenden?', 'Sprache der Oberfläche Deutsch']) assert(translated.includes(label), label);
  await snap(p, 'A-live-deutsch');
});
await scenario('B', async p => {
  await completeOnboarding(p);
  await prefs(p, 'de', 'en');
  await openGame(p);
  await consent(p);
  await snap(p, 'B-gate');
  await button(p, 'Download').click();
  await button(p, 'Pause').waitFor();
  await snap(p, 'B-progress');
  await button(p, 'Pause').click();
  await button(p, 'Resume').waitFor();
  await healthy(p);
  await snap(p, 'B-paused');
  await button(p, 'Resume').click();
  await game(p, 'B-in-game');
  await prefs(p, 'de', 'en');
});
await scenario('C', async p => {
  await completeOnboarding(p);
  await openGame(p);
  await consent(p);
  await button(p, 'Not now').click();
  await p.getByRole('group', { name: /^Definition Quiz Match/ }).waitFor();
  await healthy(p);
  await p.getByRole('group', { name: /^Definition Quiz Match/ }).click({ position: { x: 80, y: 45 } });
  await consent(p);
  await snap(p, 'C-gate-again');
  await button(p, 'Download').click();
  await game(p, 'C-game-after');
  await prefs(p, 'de', 'en');
});
await scenario('D', async p => {
  await completeOnboarding(p);
  await openGame(p);
  await consent(p);
  await button(p, 'Download').click();
  await game(p, 'D-before-reload');
  // Navigate to the app root in the same context: persistent cache, no seed data.
  await p.goto(BASE);
  await semantics(p);
  await button(p, 'Browse all games').waitFor({ timeout: 60000 });
  await healthy(p);
  await prefs(p, 'de', 'en');
  await openGame(p);
  await game(p, 'D-game'); // No fallback pass merely because consent is absent.
});
await scenario('E', async p => {
  await p.getByRole('button', { name: /^Learning language/ }).click();
  await p.getByRole('menuitem', { name: 'English', exact: true }).click();
  await button(p, 'Interface language English').click();
  await p.getByRole('menuitem', { name: 'Deutsch', exact: true }).click();
  await snap(p, 'E-mixed');
  await completeOnboarding(p, true);
  await prefs(p, 'en', 'de');
  await snap(p, 'E-full-onboarding');
  await openGame(p, true);
  await game(p, 'E-english-game-german-ui', true);
  await prefs(p, 'en', 'de');
  await p.goto(BASE);
  await semantics(p);
  await button(p, 'Alle Spiele entdecken').waitFor({ timeout: 60000 });
  await prefs(p, 'en', 'de');
});
const failed = Object.values(results).some(r => !r.ok) || pageerrors.length > 0;
log('SUITE COMPLETE ' + JSON.stringify({ results, pageerrors }));
fs.writeFileSync(`${EV}/run.log`, logs.join('\n'));
process.exitCode = failed ? 1 : 0;
