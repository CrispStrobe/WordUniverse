import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/macos-release.yml', import.meta.url), 'utf8');

test('macOS release pins a hosted runner and Xcode with StoreKit win-back APIs', () => {
  assert.match(workflow, /^    runs-on: macos-15$/m);
  const selection = workflow.indexOf('sudo xcode-select --switch /Applications/Xcode_16.4.app/Contents/Developer');
  assert.ok(selection > 0, 'explicit Xcode 16.4 selection must not be removed');
  assert.ok(selection < workflow.indexOf('- name: Setup Flutter'), 'select Xcode before Flutter setup/build');
  assert.match(workflow, /xcodebuild -version/);
  assert.match(workflow, /xcrun --sdk macosx --show-sdk-version/);
});
