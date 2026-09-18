// Shared dropdown/menu interaction for the live E2E scenarios.
// Flutter rebuilds its semantics tree as a popup menu route opens and pops, so
// a click can land on a stale node and leave the menu open.

// Open `trigger` and choose `itemName`, requiring the menu to actually close.
export async function chooseFromMenu(p, trigger, itemName, { attempts = 3, timeout = 15000 } = {}) {
  const item = () => p.getByRole('menuitem', { name: itemName, exact: true });
  for (let attempt = 0; attempt < attempts; attempt++) {
    // On a retry the menu is usually still open, so only reopen when it is not.
    if (!await item().isVisible().catch(() => false)) {
      await trigger.click();
      await item().waitFor({ state: 'visible', timeout });
    }
    await item().click();
    // A menu left standing means the click was dropped mid-rebuild; the
    // selection has not been applied, so it must be made again.
    try {
      await item().waitFor({ state: 'hidden', timeout: 5000 });
      return;
    } catch {
      await p.waitForTimeout(250);
    }
  }
  throw new Error(`Menu selection did not take effect after ${attempts} attempts: ${itemName}`);
}
