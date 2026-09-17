#!/usr/bin/env node
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const source = path.dirname(fileURLToPath(import.meta.url));
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wu-wrapper-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dir = path.join(root, 'tools/e2e');
  fs.mkdirSync(path.join(dir, 'node_modules/playwright'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'node_modules/playwright/index.js'), 'module.exports = {};');
  for (const file of ['run.sh', 'run-live.mjs']) {
    if (fs.existsSync(path.join(source, file))) fs.copyFileSync(path.join(source, file), path.join(dir, file));
  }
  for (const [file, stage] of [['language-setup-live.mjs', 'A-E'], ['german-install-live.mjs', 'F']]) {
    fs.writeFileSync(path.join(dir, file), `
      import fs from 'node:fs';
      fs.mkdirSync(process.env.EVIDENCE_DIR, { recursive: true });
      fs.appendFileSync(process.env.CALLS, '${stage}\\n');
      fs.writeFileSync(process.env.EVIDENCE_DIR + '/proof.txt', '${stage}');
      console.log('stdout ${stage}'); console.error('stderr ${stage}');
      if (process.env.SIGNAL_STAGE === '${stage}') process.kill(process.pid, 'SIGTERM');
      process.exit(Number(process.env['${stage === 'F' ? 'F_EXIT' : 'AE_EXIT'}'] || 0));
    `);
  }
  const evidence = path.join(root, 'evidence');
  const calls = path.join(root, 'calls');
  return {
    evidence,
    calls: () => fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : [],
    run: (env = {}) => spawnSync('bash', [path.join(dir, 'run.sh')], {
      cwd: os.tmpdir(), encoding: 'utf8', timeout: 15000,
      env: { ...process.env, NODE_PATH: '', EVIDENCE_DIR: evidence, CALLS: calls,
        BASE_URL: 'https://example.invalid/app/', ...env },
    }),
  };
}

test('runs A-E and F exactly once from any working directory', t => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.calls(), ['A-E', 'F']);
});

test('A-E failure propagates even when F passes; F still collects evidence', t => {
  const f = fixture(t);
  assert.equal(f.run({ AE_EXIT: '7' }).status, 7);
  assert.deepEqual(f.calls(), ['A-E', 'F']);
});

test('F failure cannot be hidden by passing A-E', t => {
  const f = fixture(t);
  assert.equal(f.run({ F_EXIT: '9' }).status, 9);
  assert.deepEqual(f.calls(), ['A-E', 'F']);
});

test('signal termination is a failure, not a null-status pass', t => {
  const f = fixture(t);
  assert.notEqual(f.run({ SIGNAL_STAGE: 'F' }).status, 0);
  assert.deepEqual(f.calls(), ['A-E', 'F']);
});

test('manual retry retains prior failure, separate logs and machine-readable status', t => {
  const f = fixture(t);
  assert.equal(f.run({ AE_EXIT: '7' }).status, 7);
  const [first] = fs.readdirSync(f.evidence);
  const firstSummary = fs.readFileSync(path.join(f.evidence, first, 'summary.json'), 'utf8');
  assert.equal(f.run().status, 0);
  const runs = fs.readdirSync(f.evidence);
  assert.equal(runs.length, 2);
  assert.equal(fs.readFileSync(path.join(f.evidence, first, 'summary.json'), 'utf8'), firstSummary);
  assert.equal(JSON.parse(firstSummary).status, 'failed');
  for (const run of runs) {
    const dir = path.join(f.evidence, run);
    const summary = JSON.parse(fs.readFileSync(path.join(dir, 'summary.json')));
    assert.equal(summary.baseUrl, 'https://example.invalid/app/');
    assert.deepEqual(summary.stages.map(s => s.name), ['A-E', 'F']);
    for (const name of ['A-E', 'F']) {
      assert.equal(fs.readFileSync(path.join(dir, name, 'proof.txt'), 'utf8'), name);
      const log = fs.readFileSync(path.join(dir, name, 'process.log'), 'utf8');
      assert.match(log, /stdout/); assert.match(log, /stderr/);
    }
  }
  assert.deepEqual(f.calls(), ['A-E', 'F', 'A-E', 'F']);
});
