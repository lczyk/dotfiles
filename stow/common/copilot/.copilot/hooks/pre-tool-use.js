#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const configHome = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
const evaluator = process.env.AGENT_HOOK_EVALUATOR ||
  path.join(configHome, 'agent-hooks', 'evaluate.sh');

const shellTools = new Set(['bash', 'powershell']);
const writeTools = new Set([
  'apply_patch',
  'create',
  'edit',
  'notebook_edit',
  'str_replace_editor',
  'write',
]);

function parseArgs(value) {
  if (typeof value !== 'string') return value || {};
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function commandFrom(args) {
  if (typeof args === 'string') return args;
  if (!args || typeof args !== 'object') return null;
  return typeof args.command === 'string'
    ? args.command
    : typeof args.cmd === 'string'
      ? args.cmd
      : null;
}

function directPaths(args) {
  if (!args || typeof args !== 'object') return [];

  const paths = [
    args.file_path,
    args.filePath,
    args.path,
    args.notebook_path,
    args.notebookPath,
  ];
  if (Array.isArray(args.paths)) paths.push(...args.paths);

  return [...new Set(paths.filter(
    value => typeof value === 'string' && value.length > 0,
  ))];
}

function patchFrom(args) {
  if (typeof args === 'string') return args;
  if (!args || typeof args !== 'object') return null;

  for (const key of ['patch', 'command', 'input']) {
    if (typeof args[key] === 'string') return args[key];
  }
  return null;
}

function patchPaths(patch) {
  const paths = new Set();
  for (const line of patch.split(/\r?\n/)) {
    const custom = line.match(/^\*\*\* (?:Add|Update) File: (.*)$/) ||
      line.match(/^\*\*\* Move to: (.*)$/);
    if (custom) paths.add(custom[1]);

    const unified = line.match(/^\+\+\+ b\/(.*)$/);
    if (unified) paths.add(unified[1]);
  }
  return [...paths];
}

function isDeleteOnlyPatch(patch) {
  return /^\*\*\* Delete File: |^\+\+\+ \/dev\/null$/m.test(patch);
}

function emitDenial(reason) {
  process.stdout.write(JSON.stringify({
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  }));
}

function evaluate(request) {
  const result = spawnSync('bash', [evaluator], {
    input: JSON.stringify(request),
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  if (result.error || result.status !== 0) {
    const reason = result.stderr.trim() || result.error?.message ||
      `safety evaluator failed with status ${result.status}`;
    throw new Error(reason);
  }

  let verdict;
  try {
    verdict = JSON.parse(result.stdout);
  } catch {
    throw new Error('safety evaluator returned invalid JSON');
  }

  if (verdict.decision === 'deny') {
    emitDenial(verdict.reason || 'blocked by safety policy');
  } else if (verdict.decision !== 'allow') {
    throw new Error('safety evaluator returned an invalid verdict');
  }
}

function main() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  const tool = payload.toolName;
  const args = parseArgs(payload.toolArgs);

  if (typeof tool !== 'string') {
    throw new Error('preToolUse payload has no toolName');
  }

  if (shellTools.has(tool)) {
    const command = commandFrom(args);
    if (!command) {
      emitDenial(`cannot inspect Copilot ${tool} payload`);
      return;
    }
    evaluate({ version: 1, operation: 'shell', command });
    return;
  }

  if (!writeTools.has(tool)) return;

  const paths = directPaths(args);
  const patch = patchFrom(args);
  if (patch) paths.push(...patchPaths(patch));

  const uniquePaths = [...new Set(paths)];
  if (uniquePaths.length === 0) {
    if (patch && isDeleteOnlyPatch(patch)) return;
    emitDenial(`cannot inspect Copilot ${tool} write destinations`);
    return;
  }

  evaluate({ version: 1, operation: 'write', write_paths: uniquePaths });
}

try {
  main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Copilot safety adapter failed: ${message}\n`);
  process.exit(1);
}
