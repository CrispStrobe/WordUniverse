// Orchestrate both live scripts once. Never retry or overwrite an earlier run.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:18100';
const root = path.resolve(process.env.EVIDENCE_DIR || path.join(dir, 'evidence'));
fs.mkdirSync(root, { recursive: true });
const evidence = fs.mkdtempSync(path.join(root, `run-${new Date().toISOString().replaceAll(':', '-')}-`));
const summary = {
  status: 'running', baseUrl, startedAt: new Date().toISOString(), node: process.version,
  commit: process.env.GITHUB_SHA || null,
  workflowRun: process.env.GITHUB_RUN_ID || null,
  workflowAttempt: process.env.GITHUB_RUN_ATTEMPT || null,
  stages: [],
};
const save = () => fs.writeFileSync(path.join(evidence, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
save();
console.log(`Evidence: ${evidence}`);
let activeChild;
let interrupted = false;
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    interrupted = true;
    summary.status = 'interrupted';
    summary.signal = signal;
    process.exitCode = 128 + os.constants.signals[signal];
    activeChild?.kill(signal);
    save();
  });
}

async function runStage(name, script) {
  const stageDir = path.join(evidence, name);
  fs.mkdirSync(stageDir);
  const stage = { name, script, status: 'running', startedAt: new Date().toISOString() };
  summary.stages.push(stage);
  save();
  const log = fs.openSync(path.join(stageDir, 'process.log'), 'a');
  try {
    await new Promise(resolve => {
      const child = spawn(process.execPath, [path.join(dir, script)], {
        cwd: dir,
        env: { ...process.env, NODE_PATH: '', PLAYWRIGHT_BROWSERS_PATH: '0', BASE_URL: baseUrl, EVIDENCE_DIR: stageDir },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      activeChild = child;
      for (const [stream, output] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
        stream.on('data', chunk => { fs.writeSync(log, chunk); output.write(chunk); });
      }
      // Bound hung browser/transport processes, while leaving CI time to upload.
      const timer = setTimeout(() => {
        stage.timedOut = true;
        child.kill('SIGKILL');
      }, 15 * 60 * 1000);
      child.on('error', error => { stage.error = error.message; });
      child.on('close', (code, signal) => {
        clearTimeout(timer);
        activeChild = undefined;
        stage.signal = signal;
        stage.exitCode = stage.timedOut ? 124 : (code ?? (128 + (os.constants.signals[signal] || 0)));
        stage.status = stage.exitCode === 0 && !stage.error ? 'passed' : 'failed';
        resolve();
      });
    });
  } finally {
    fs.closeSync(log);
    stage.finishedAt = new Date().toISOString();
    save();
  }
}

for (const [name, script] of [['A-E', 'language-setup-live.mjs'], ['F', 'german-install-live.mjs']]) {
  if (interrupted) break;
  await runStage(name, script);
}
if (!interrupted) {
  const failed = summary.stages.find(stage => stage.status !== 'passed');
  summary.status = failed ? 'failed' : 'passed';
  process.exitCode = failed ? (failed.exitCode || 1) : 0;
}
summary.finishedAt = new Date().toISOString();
save();
console.log(`A-F ${summary.status}: ${evidence}/summary.json`);
