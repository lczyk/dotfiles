#!/usr/bin/env node
// frugal -- SessionStart hook. Reads flag, emits ruleset for active level.
// Default 'off' means: no flag written, no rules injected, silent.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag } = require('./frugal-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.frugal-active');

// Resolve active mode: existing flag wins (sticks across sessions), else default.
let mode = readFlag(flagPath);
if (!mode) mode = getDefaultMode();

if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

safeWriteFlag(flagPath, mode);

// Read SKILL.md as single source of truth, filter intensity table to active level.
let skillContent = '';
try {
  skillContent = fs.readFileSync(
    path.join(__dirname, '..', 'skills', 'frugal', 'SKILL.md'), 'utf8'
  );
} catch (e) { /* fallback below */ }

let output;
if (skillContent) {
  const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');
  const filtered = body.split('\n').reduce((acc, line) => {
    const tableRowMatch = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (tableRowMatch) {
      if (tableRowMatch[1] === mode) acc.push(line);
      return acc;
    }
    acc.push(line);
    return acc;
  }, []);
  output = 'FRUGAL MODE ACTIVE -- level: ' + mode + '\n\n' + filtered.join('\n');
} else {
  output =
    'FRUGAL MODE ACTIVE -- level: ' + mode + '\n\n' +
    'Network slow, tokens expensive. Batch tool calls. Prefer single big edits. ' +
    "Don't re-read files in context. Don't pre-read speculatively. " +
    'Use rg/grep to extract instead of dumping whole files. ' +
    (mode === 'full' ? 'Avoid speculative agent forks; inline work when feasible. ' : '') +
    'Off: /frugal off';
}

process.stdout.write(output);
