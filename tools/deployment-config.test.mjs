import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const vercel = JSON.parse(read('vercel.json'));

test('Pages and every Vercel build use CanvasKit with matching CI SDK pins', () => {
  const pages = read('.github/workflows/pages.yml');
  const ci = read('.github/workflows/ci.yml');
  const version = pages.match(/FLUTTER_VERSION: '([^']+)'/)[1];
  assert.ok(vercel.buildCommand.includes(`--branch ${version}`));
  assert.ok(ci.includes(`flutter-version: '${version}'`));
  for (const config of [pages, ci, vercel.buildCommand, read('deploy.sh')]) {
    for (const build of config.matchAll(/flutter(?:\/bin\/flutter)? build web[^\n]*/g)) {
      assert.doesNotMatch(build[0], /--wasm/);
      assert.match(build[0], /--release/);
    }
  }
  assert.ok(pages.includes('--base-href "/${GITHUB_REPOSITORY#*/}/"'));
  assert.doesNotMatch(vercel.buildCommand, /--base-href/);
});

test('Vercel JS and WASM caching matches Pages without isolation requirements', () => {
  for (const asset of ['/main.dart.js', '/flutter.js', '/flutter_bootstrap.js', '/sqlite3.wasm', '/canvaskit/canvaskit.wasm']) {
    const headers = vercel.headers.filter(rule => new RegExp(`^${rule.source}$`).test(asset)).flatMap(rule => rule.headers);
    assert.equal(headers.find(h => h.key.toLowerCase() === 'cache-control')?.value, 'public, max-age=600');
    assert.ok(!headers.some(h => /cross-origin-(opener|embedder)-policy/i.test(h.key)));
  }
});

test('prebuilt deployments retain the canonical headers and rewrites', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'wu-vercel-config-'));
  try {
    const output = path.join(temp, 'vercel.json');
    execFileSync(process.execPath, [path.join(root, 'tools/prepare-vercel.mjs'), output], { cwd: temp });
    const generated = JSON.parse(fs.readFileSync(output, 'utf8'));
    assert.deepEqual(generated.headers, vercel.headers);
    assert.deepEqual(generated.rewrites, vercel.rewrites);
    assert.equal(generated.buildCommand, '');
    assert.equal(generated.outputDirectory, '.');
    assert.equal(generated.framework, null);
    assert.equal(generated.installCommand, undefined);
    assert.ok(read('.github/workflows/ci.yml').includes('node ../../tools/prepare-vercel.mjs vercel.json'));
    assert.ok(read('deploy.sh').includes('node tools/prepare-vercel.mjs build/web/vercel.json'));
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});
