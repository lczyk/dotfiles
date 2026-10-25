#!/usr/bin/env node
'use strict';

const fs = require('fs');
const {
  getDefaultMode,
  getStatePath,
  safeWriteFlag,
  readFlag,
  VALID_MODES,
} = require('./caveman-config');

const INDEPENDENT_MODES = new Set(['commit', 'compress']);
const flagPath = getStatePath();

function clearFlag() {
  try {
    fs.unlinkSync(flagPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

try {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  const promptInput = Array.isArray(data.prompt)
    ? data.prompt.map(part => part && typeof part.text === 'string' ? part.text : '').join('\n')
    : data.prompt;
  const raw = String(promptInput || '').trim().toLowerCase().replace(/\s+/g, ' ');
  if (/<scheduled-task\b/.test(raw)) process.exit(0);

  let prompt = raw;
  let foreignCommand = false;
  const envelopeName = /<command-name>\s*([^<\s]+)\s*<\/command-name>/.exec(raw);
  if (envelopeName) {
    if (envelopeName[1].startsWith('/caveman')) {
      const envelopeArgs = /<command-args>\s*([^<]*?)\s*<\/command-args>/.exec(raw);
      const args = envelopeArgs ? envelopeArgs[1].trim() : '';
      prompt = args ? `${envelopeName[1]} ${args}` : envelopeName[1];
    } else {
      foreignCommand = true;
    }
  }

  if (prompt.startsWith('/caveman') || prompt.startsWith('/skill:caveman')) {
    const parts = prompt.split(/\s+/);
    const command = parts[0];
    const argument = parts[1] || '';
    let mode = null;

    if (['/caveman-commit', '/skill:caveman-commit'].includes(command)) {
      mode = 'commit';
    } else if (['/caveman-compress', '/caveman:caveman-compress', '/skill:caveman-compress'].includes(command)) {
      mode = 'compress';
    } else if (['/caveman', '/caveman:caveman', '/skill:caveman'].includes(command)) {
      if (!argument) mode = getDefaultMode();
      else if (['off', 'stop', 'disable'].includes(argument)) mode = 'off';
      else if (VALID_MODES.includes(argument) && !INDEPENDENT_MODES.has(argument)) mode = argument;
    }

    if (mode === 'off') clearFlag();
    else if (mode) safeWriteFlag(flagPath, mode);
  }

  const deactivation = prompt.replace(/[.!?\s]+$/, '');
  if (!foreignCommand && ['stop caveman', 'normal mode'].includes(deactivation)) clearFlag();

  const activeMode = readFlag(flagPath);
  if (activeMode && !INDEPENDENT_MODES.has(activeMode)) {
    process.stdout.write(
      `caveman mode active (${activeMode}). ` +
      'drop articles/filler/pleasantries/hedging. fragments ok. ' +
      'composes with lofi: caveman = density, lofi = surface (lowercase/en-gb/ascii). apply both, drop neither. ' +
      'code/commits/security: full sentences, lofi case still applies.'
    );
  }
} catch (error) {
  process.exit(0);
}
