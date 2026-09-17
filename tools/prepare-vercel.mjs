// Reuse the root response policy for CI/manual prebuilt deployments.
// No build, network, Git, or deployment operations occur here.
import fs from 'node:fs';

const output = process.argv[2];
if (!output) throw new Error('Usage: node tools/prepare-vercel.mjs <output vercel.json>');
const config = JSON.parse(fs.readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'));
delete config.installCommand;
Object.assign(config, { buildCommand: '', outputDirectory: '.', ignoreCommand: 'exit 0' });
fs.writeFileSync(output, JSON.stringify(config, null, 2) + '\n');
