#!/usr/bin/env node
'use strict';

const fs = require('fs');
const {
  getDefaultMode,
  getSkillPath,
  getStatePath,
  safeWriteFlag,
  readFlag,
} = require('./caveman-config');

const flagPath = getStatePath();
let source = 'startup';

try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw) {
      const payload = JSON.parse(raw);
      if (payload && typeof payload.source === 'string') source = payload.source;
    }
  }
} catch (error) {
  source = 'startup';
}

const mode = source === 'startup' ? getDefaultMode() : (readFlag(flagPath) || 'off');

if (mode === 'off') {
  try {
    fs.unlinkSync(flagPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  process.exit(0);
}

safeWriteFlag(flagPath, mode);

if (['commit', 'compress'].includes(mode)) {
  process.stdout.write(`caveman mode active -- level: ${mode}. behaviour defined by /skill:caveman-${mode} skill.`);
  process.exit(0);
}

let output;
try {
  const body = fs.readFileSync(getSkillPath(), 'utf8').replace(/^---[\s\S]*?---\s*/, '');
  const filtered = body.split(/\r?\n/).filter(line => {
    const table = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (table) return table[1] === mode;
    const example = line.match(/^- (\S+?):\s/);
    if (example) return example[1] === mode;
    return true;
  });
  output = `caveman mode active -- level: ${mode}\n\n${filtered.join('\n')}`;
} catch (error) {
  output = `caveman mode active -- level: ${mode}\n\n` +
    'respond terse like smart caveman. all technical substance stay. only fluff die. ' +
    'drop articles, filler, pleasantries and hedging. fragments ok. ' +
    'keep technical terms, numbers, negations, code and error strings exact. ' +
    'composes with lofi: caveman = density, lofi = surface. apply both, drop neither. ' +
    'code, commits, docs and security warnings use full sentences. ' +
    'off only: "stop caveman", "normal mode", or /skill:caveman off.';
}

process.stdout.write(output);
