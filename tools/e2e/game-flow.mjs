// Shared "is a quiz really playable" probe for the live E2E scenarios.
// Both language-setup-live.mjs (A-E) and german-install-live.mjs (F) drive the
// same flow, so the polling lives here once instead of being copied per script.
import assert from 'node:assert/strict';

// Poll until a real question is on screen, answer it, and require the counter
// to advance. Callers inject aria/assertHealthy/snap so each script keeps its
// own evidence layout and error vocabulary.
export async function playQuiz(p, {
  prompt,
  skipLabel,
  deadlineMs = 240000,
  aria,
  assertHealthy,
  snap,
  snapBefore,
  snapAfter,
}) {
  const deadline = Date.now() + deadlineMs;
  const stalls = [];
  const started = Date.now();
  while (Date.now() < deadline) {
    let text;
    try {
      text = await aria();
    } catch (e) {
      // Writing a pack to browser storage can block the main thread long enough
      // that even a body snapshot times out. The deadline is the real bound, so
      // record the stall as evidence and keep polling instead of failing here.
      stalls.push({ atMs: Date.now() - started, message: e.message });
      await p.waitForTimeout(1000);
      continue;
    }
    assertHealthy(text);
    const skip = p.getByRole('button', { name: skipLabel, exact: true });
    if (await skip.isVisible()) { await skip.click(); await p.waitForTimeout(500); continue; }
    if (text.includes(prompt)) {
      const question = p.getByRole('group').filter({ hasText: prompt });
      try {
        assert.equal(await question.count(), 1, 'one actual question');
        assert.equal(await question.getByRole('button').count(), 4, 'four answer choices');
        assert(/1 \/ 10/.test(text), 'first question counter');
        assert(!/pack required|Paket erforderlich|button "Download"|Definition Quiz Match/.test(text), text);
        const content = await question.innerText();
        assert(content.replace(prompt, '').trim().length > 10, 'nonempty definition and answers');
        if (snapBefore) await snap(snapBefore);
        // Exercise a real answer and require the counter to advance.
        await question.getByRole('button').first().click();
        await p.waitForFunction(() => /2 \/ 10/.test(document.body.innerText), null, { timeout: 15000 });
        assertHealthy(await aria());
        if (snapAfter) await snap(snapAfter);
        return { stalls };
      } catch (e) {
        // The tutorial can mount between the snapshot above and these checks,
        // taking the question out of the semantics tree mid-verification. That
        // is transient and the loop dismisses it; anything else is a real
        // failure and must surface unchanged.
        if (!await skip.isVisible().catch(() => false)) throw e;
        continue;
      }
    }
    await p.waitForTimeout(500);
  }
  const last = await aria().catch(e => `<no snapshot: ${e.message}>`);
  const stalled = stalls.length ? ` (${stalls.length} page stall(s): ${stalls.map(s => s.message).join('; ')})` : '';
  throw new Error(`No playable question before deadline${stalled}: ${last}`);
}
