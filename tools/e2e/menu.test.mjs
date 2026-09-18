#!/usr/bin/env node
// Regression tests for menu selection against real Playwright pages.
// Scenario E on Pages failed with the popup menu still open in E-mixed.aria.txt:
// the menuitem click was accepted by the browser but dropped by the app while it
// rebuilt the semantics tree, so the language never changed.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { chooseFromMenu } from './menu.mjs';

// Browsers live in node_modules (see the setup scripts in package.json), so
// resolve them there unless the caller has pointed somewhere else.
process.env.PLAYWRIGHT_BROWSERS_PATH ??= '0';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

// `dropClicks` menuitem clicks are accepted and then ignored, mirroring a click
// landing on a semantics node the framework is in the middle of replacing.
const fixture = ({ dropClicks = 0 } = {}) => `
<body>
  <button id="trigger">Interface language English</button>
  <div id="menu" hidden></div>
  <div id="chosen"></div>
  <script>
    let drops = ${dropClicks};
    const menu = document.getElementById('menu');
    const open = () => {
      menu.hidden = false;
      menu.innerHTML = '<div role="menu"><div role="menuitem" tabindex="0">Deutsch</div>' +
                       '<div role="menuitem" tabindex="0">English</div></div>';
      for (const item of menu.querySelectorAll('[role=menuitem]')) {
        item.onclick = () => {
          if (drops-- > 0) return; // Click accepted by the DOM, dropped by the app.
          menu.hidden = true;
          menu.innerHTML = '';
          document.getElementById('chosen').textContent = item.textContent;
        };
      }
    };
    document.getElementById('trigger').onclick = open;
  </script>
</body>`;

async function withPage(t, html) {
  const browser = await chromium.launch({ headless: true });
  t.after(() => browser.close());
  const p = await (await browser.newContext()).newPage();
  p.setDefaultTimeout(5000);
  await p.setContent(html);
  return p;
}

const trigger = p => p.getByRole('button', { name: 'Interface language English', exact: true });

test('a normal menu selection is applied', async t => {
  const p = await withPage(t, fixture());
  await chooseFromMenu(p, trigger(p), 'Deutsch', { timeout: 3000 });
  assert.equal(await p.locator('#chosen').textContent(), 'Deutsch');
  assert.equal(await p.locator('#menu').isVisible(), false, 'menu closed');
});

test('a dropped click is retried until the selection really takes effect', async t => {
  const p = await withPage(t, fixture({ dropClicks: 1 }));
  await chooseFromMenu(p, trigger(p), 'Deutsch', { timeout: 3000 });
  assert.equal(await p.locator('#chosen').textContent(), 'Deutsch', 'selection applied');
  assert.equal(await p.locator('#menu').isVisible(), false, 'menu closed');
});

test('several dropped clicks in a row are still recovered', async t => {
  const p = await withPage(t, fixture({ dropClicks: 2 }));
  await chooseFromMenu(p, trigger(p), 'Deutsch', { timeout: 3000 });
  assert.equal(await p.locator('#chosen').textContent(), 'Deutsch');
});

test('a menu that never accepts the click fails loudly', async t => {
  const p = await withPage(t, fixture({ dropClicks: 99 }));
  await assert.rejects(
    () => chooseFromMenu(p, trigger(p), 'Deutsch', { attempts: 2, timeout: 3000 }),
    /did not take effect/,
  );
});

test('the wrong item is never silently chosen', async t => {
  const p = await withPage(t, fixture({ dropClicks: 1 }));
  await chooseFromMenu(p, trigger(p), 'English', { timeout: 3000 });
  assert.equal(await p.locator('#chosen').textContent(), 'English');
});
