// F: fresh German-interface install, real transport/IndexedDB and playable quiz.
// Observe actual semantics text (not just aria-label attributes: Flutter also
// publishes text nodes). Merge snapshots and observer data for every assertion.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const BASE = process.env.BASE_URL || 'http://127.0.0.1:18100';
const EV = process.env.EVIDENCE_DIR || '/tmp/wu-live-evidence';
fs.mkdirSync(EV, { recursive: true });
const pageerrors = [];
const button = (p, name) => p.getByRole('button', { name, exact: true });
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
const p = await context.newPage();
p.setDefaultTimeout(30000);
p.on('pageerror', e => { pageerrors.push(e.message); console.log('PAGEERROR ' + e.message); });
const results = {};
const seen = [];
let observing = false;
const aria = async () => {
  const text = await p.locator('body').ariaSnapshot();
  if (observing) seen.push(text);
  return text;
};
const snap = async name => {
  fs.writeFileSync(`${EV}/${name}.aria.txt`, await aria());
  await p.screenshot({ path: `${EV}/${name}.png` });
};
const collect = async () => ({ poll: seen, observer: await p.evaluate(() => window.__wuTexts || []) });
const healthy = text => assert(!/\b(error|exception|failed|failure|Fehler)\b|Keine Definitionen/i.test(text), 'error UI: ' + text);
try {
  await p.goto(BASE);
  await p.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
  await p.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await button(p, 'Interface language English').click();
  await p.getByRole('menuitem', { name: 'Deutsch', exact: true }).click();
  await button(p, 'Weiter').waitFor();

  // Start after the language switch: the initial English picker is intentional.
  await p.evaluate(() => {
    window.__wuTexts = [];
    const add = text => { if (text?.trim()) window.__wuTexts.push(text.trim()); };
    const capture = node => {
      add(node.textContent);
      add(node.getAttribute?.('aria-label'));
      node.querySelectorAll?.('[aria-label]').forEach(el => add(el.getAttribute('aria-label')));
    };
    document.querySelectorAll('flt-semantics').forEach(capture);
    window.__wuObserver = new MutationObserver(mutations => {
      for (const m of mutations) {
        // Restrict to visible Flutter semantics, excluding scripts/styles.
        const el = m.target.nodeType === Node.ELEMENT_NODE ? m.target : m.target.parentElement;
        if (!el?.closest('flt-semantics, flt-semantics-host')) continue;
        if (m.type === 'attributes') { add(m.oldValue); add(m.target.getAttribute('aria-label')); }
        if (m.type === 'characterData') { add(m.oldValue); add(m.target.textContent); }
        if (m.type === 'childList') {
          m.addedNodes.forEach(capture);
          m.removedNodes.forEach(capture);
        }
      }
    });
    window.__wuObserver.observe(document, { subtree: true, childList: true, characterData: true,
      characterDataOldValue: true, attributes: true, attributeOldValue: true,
      attributeFilter: ['aria-label'] });
  });
  observing = true;
  await snap('F-picker-de');
  await button(p, 'Weiter').click();
  await button(p, 'Meinen Lernplan vorbereiten').waitFor();
  await snap('F-onboarding-de'); // Before leaving onboarding, not after it.
  await button(p, 'Meinen Lernplan vorbereiten').click();
  await button(p, 'Herunterladen').waitFor({ timeout: 60000 });
  const consent = await aria();
  assert(consent.includes('Deutsch-Paket erforderlich') && consent.includes('GPL-3.0-or-later'), consent);
  await snap('F-consent-de'); // Consent, not the already-started transfer.
  await button(p, 'Herunterladen').click();
  await button(p, 'Pausieren').waitFor({ timeout: 60000 });
  await snap('F-downloading-de');
  await button(p, 'Pausieren').click();
  await button(p, 'Fortsetzen').waitFor();
  assert((await aria()).includes('Download pausiert'), 'German paused status');
  await snap('F-paused-de');
  await button(p, 'Fortsetzen').click();
  await button(p, 'Pausieren').waitFor();
  await snap('F-resumed-de');

  fs.writeFileSync(`${EV}/F-install-poll.txt`, '');
  const deadline = Date.now() + 240000;
  let homeReached = false;
  const phases = new Map([
    ['decompressing', 'Datenbank wird entpackt …'],
    ['browser-storage', 'Wird im Browserspeicher gespeichert …'],
  ]);
  const captured = new Set();
  while (Date.now() < deadline) {
    const text = await aria();
    fs.appendFileSync(`${EV}/F-install-poll.txt`, text + '\n---\n');
    healthy(text);
    for (const [phase, phrase] of phases) {
      if (!captured.has(phase) && text.includes(phrase)) {
        captured.add(phase);
        // Save the snapshot that actually contained this phase, not a later one.
        fs.writeFileSync(`${EV}/F-${phase}-de.aria.txt`, text);
      }
    }
    if (text.includes('Alle Spiele entdecken')) { homeReached = true; break; }
    await p.waitForTimeout(50);
  }
  assert(homeReached, 'install finished and home reached');
  await p.evaluate(() => window.__wuObserver.disconnect());
  const observations = await collect();
  fs.writeFileSync(`${EV}/F-observed-texts.json`, JSON.stringify(observations, null, 2));
  const texts = [...observations.poll, ...observations.observer];
  const observed = phrase => texts.some(text => text.includes(phrase));
  // Positive regression assertion: absence of English alone is not evidence.
  assert(observed('Wird im Browserspeicher gespeichert …'), 'observed exact German browser-storage phrase');
  // Web compute is synchronous: decompression may finish before Flutter paints
  // its status. Record it if rendered, but never manufacture phase evidence.
  assert(observed('Wird heruntergeladen'), 'observed German download progress');
  for (const label of ['Pausieren', 'Fortsetzen']) {
    assert(texts.some(text => text === label || text.includes(`button "${label}"`)), `German control: ${label}`);
  }
  // All English loader messages from the ARB, including interpolated messages.
  const en = JSON.parse(fs.readFileSync(new URL('../../lib/l10n/app_en.arb', import.meta.url)));
  for (const [key, value] of Object.entries(en)) {
    if (!key.startsWith('load') || typeof value !== 'string') continue;
    const prefix = value.split('{')[0].trim().replace(/\s*…$/, '');
    assert(!observed(prefix), `no English install leak: ${key} (${prefix})`);
  }
  assert(!texts.some(text => /(?:^|button ")(?:Pause|Resume|Paused)(?:"|$)/m.test(text)), 'no English controls');
  observing = false; // Quiz vocabulary is content, not installer UI.

  await button(p, 'Alle Spiele entdecken').click();
  await p.getByRole('group', { name: /^Definitions-Quiz/ }).click({ position: { x: 80, y: 45 } });
  const gameDeadline = Date.now() + 120000;
  let playable = false;
  while (Date.now() < gameDeadline) {
    const text = await aria();
    healthy(text);
    const skip = button(p, 'Überspringen');
    if (await skip.isVisible()) { await skip.click(); await p.waitForTimeout(400); continue; }
    const prompt = 'Welches Wort wird beschrieben?';
    if (text.includes(prompt)) {
      const question = p.getByRole('group').filter({ hasText: prompt });
      assert.equal(await question.count(), 1, 'one question');
      assert.equal(await question.getByRole('button').count(), 4, 'four answers');
      assert(/1 \/ 10/.test(text), 'first question counter');
      assert((await question.innerText()).replace(prompt, '').trim().length > 10, 'nonempty definition and answers');
      await snap('F-game-de');
      await question.getByRole('button').first().click();
      await p.waitForFunction(() => /2 \/ 10/.test(document.body.innerText), null, { timeout: 15000 });
      healthy(await aria());
      await snap('F-game-advanced-de');
      playable = true;
      break;
    }
    await p.waitForTimeout(500);
  }
  assert(playable, 'German quiz really played and advanced');
  assert.equal(pageerrors.length, 0, 'no pageerrors');
  results.F = { ok: true };
  console.log('PASS F: German-interface install/status pipeline and playable quiz');
} catch (e) {
  results.F = { ok: false, note: e.stack || String(e) };
  console.log('FAIL F: ' + e.message);
  await snap('F-FAILED').catch(() => {});
} finally {
  await collect().then(data => fs.writeFileSync(`${EV}/F-observed-texts.json`, JSON.stringify(data, null, 2))).catch(() => {});
  fs.writeFileSync(`${EV}/results-f.json`, JSON.stringify({ results, pageerrors }, null, 2));
  await browser.close();
}
process.exitCode = results.F?.ok ? 0 : 1;
