#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const configHome = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
const stateDir = process.env.AGENT_STATE_DIR || path.join(configHome, 'agent-state');
const modesDir = path.join(configHome, 'agent-modes');
const skillsDir = path.join(configHome, 'agent-skills');
const stylesDir = path.join(configHome, 'agent-styles');

const modes = {
  caveman: {
    defaultMode: 'full',
    env: 'CAVEMAN_DEFAULT_MODE',
    valid: ['off', 'lite', 'full', 'ultra', 'commit', 'compress'],
  },
  ponytail: {
    defaultMode: 'full',
    env: 'PONYTAIL_DEFAULT_MODE',
    valid: ['off', 'lite', 'full', 'ultra'],
  },
};

function exists(file) {
  try {
    fs.accessSync(file);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

function readJsonIfPresent(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function normalizeMode(name, value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  return modes[name].valid.includes(normalized) ? normalized : null;
}

function configuredMode(name) {
  const spec = modes[name];
  const fromEnv = normalizeMode(name, process.env[spec.env]);
  if (fromEnv) return fromEnv;

  const files = [
    path.join(modesDir, `${name}.json`),
    path.join(configHome, name, 'config.json'),
  ];
  for (const file of files) {
    const config = readJsonIfPresent(file);
    if (!config) continue;

    const configured = normalizeMode(name, config.defaultMode);
    if (!configured) throw new Error(`invalid defaultMode in ${file}`);
    return configured;
  }
  return spec.defaultMode;
}

function statePath(name) {
  return path.join(stateDir, `${name}-active`);
}

function clearState(name) {
  const file = statePath(name);
  try {
    const stat = fs.lstatSync(file);
    if (stat.isSymbolicLink()) throw new Error(`refusing symlinked state file: ${file}`);
    fs.unlinkSync(file);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

function writeState(name, mode) {
  fs.mkdirSync(stateDir, { recursive: true, mode: 0o700 });

  const file = statePath(name);
  try {
    if (fs.lstatSync(file).isSymbolicLink()) {
      throw new Error(`refusing symlinked state file: ${file}`);
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  const temporary = path.join(stateDir, `.${name}-active.${process.pid}.${Date.now()}`);
  let descriptor;
  try {
    descriptor = fs.openSync(temporary, 'wx', 0o600);
    fs.writeFileSync(descriptor, mode);
    fs.fchmodSync(descriptor, 0o600);
    fs.closeSync(descriptor);
    descriptor = undefined;
    fs.renameSync(temporary, file);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    try {
      fs.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

function filteredSkill(name, mode) {
  const file = path.join(skillsDir, name, 'SKILL.md');
  const body = fs.readFileSync(file, 'utf8').replace(/^---[\s\S]*?---\s*/, '');

  return body
    .split(/\r?\n/)
    .filter(line => {
      const table = line.match(/^\|\s*\*\*(lite|full|ultra)\*\*\s*\|/i);
      if (table) return table[1].toLowerCase() === mode;

      const example = line.match(/^-\s*(lite|full|ultra):\s*/i);
      if (example) return example[1].toLowerCase() === mode;
      return true;
    })
    .join('\n');
}

function modeContext(name, mode) {
  if (name === 'caveman' && ['commit', 'compress'].includes(mode)) {
    return `CAVEMAN MODE ACTIVE -- level: ${mode}. Behaviour is defined by the caveman-${mode} skill.`;
  }
  return `${name.toUpperCase()} MODE ACTIVE -- level: ${mode}\n\n${filteredSkill(name, mode)}`;
}

function activateMode(name, contexts) {
  const mode = configuredMode(name);
  if (mode === 'off') {
    clearState(name);
    return;
  }

  writeState(name, mode);
  contexts.push(modeContext(name, mode));
}

function sessionStart() {
  const contexts = [];
  const lofiOff = path.join(stateDir, 'lofi-off');
  if (!exists(lofiOff)) {
    contexts.push(fs.readFileSync(path.join(stylesDir, 'lofi.md'), 'utf8'));
  }

  activateMode('caveman', contexts);
  activateMode('ponytail', contexts);

  process.stdout.write(JSON.stringify({
    additionalContext: contexts.join('\n\n---\n\n'),
  }));
}

function requestedMode(name, prompt) {
  if (name === 'caveman') {
    if (/^\/caveman-commit(?:\s|$)/.test(prompt)) return 'commit';
    if (/^\/caveman(?::caveman)?-compress(?:\s|$)/.test(prompt)) return 'compress';
  }

  const prefix = new RegExp(`^[/@$]${name}(?::${name})?(?:\\s|$)`);
  if (!prefix.test(prompt)) return null;

  const argument = prompt.split(/\s+/)[1] || '';
  if (['off', 'stop', 'disable'].includes(argument)) return 'off';
  if (!argument) return configuredMode(name);
  return normalizeMode(name, argument);
}

function trackMode(name, prompt) {
  const requested = requestedMode(name, prompt);
  if (!requested) return;
  if (requested === 'off') clearState(name);
  else writeState(name, requested);
}

function promptSubmitted() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  const prompt = String(payload.prompt || '').trim().toLowerCase();
  const deactivation = prompt.replace(/[.!?\s]+$/, '');

  if (deactivation === 'normal mode') {
    clearState('caveman');
    clearState('ponytail');
    return;
  }
  if (deactivation === 'stop caveman') clearState('caveman');
  if (deactivation === 'stop ponytail') clearState('ponytail');

  trackMode('caveman', prompt);
  trackMode('ponytail', prompt);
}

function main() {
  switch (process.argv[2]) {
    case 'session-start':
      sessionStart();
      break;
    case 'prompt':
      promptSubmitted();
      break;
    default:
      throw new Error(`unknown context adapter command: ${process.argv[2] || '<missing>'}`);
  }
}

try {
  main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Copilot context adapter failed: ${message}\n`);
  process.exit(1);
}
