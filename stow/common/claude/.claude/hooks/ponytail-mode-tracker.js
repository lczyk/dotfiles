#!/usr/bin/env node
// ponytail -- UserPromptSubmit hook to track which ponytail mode is active
// Inspects user input for /ponytail commands and writes mode to flag file

const { getDefaultMode, isDeactivationCommand } = require('./ponytail-config');
const { clearMode, readMode, setMode, writeHookOutput } = require('./ponytail-runtime');

// Short reminder re-injected every turn while a mode is active, so the persona
// persists like caveman does -- not just from SessionStart. Keep it terse.
function reinforcement(mode) {
  return 'PONYTAIL MODE ACTIVE (' + mode + '). ' +
    'lazy senior dev: YAGNI first (does it need to exist?), stdlib/native before ' +
    'custom, one line before fifty, delete over add, no unrequested abstractions. ' +
    'mark deliberate simplifications with a NOTE: comment. don\'t name this skill in replies.';
}

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    // Strip UTF-8 BOM some shells prepend when piping (breaks JSON.parse)
    const data = JSON.parse(input.replace(/^\uFEFF/, ''));
    const prompt = (data.prompt || '').trim().toLowerCase();
    let handled = false;

    // Match /ponytail commands
    if (/^[/@$]ponytail/.test(prompt)) {
      const parts = prompt.split(/\s+/);
      const cmd = parts[0].replace(/^[@$]/, '/');
      const arg = parts[1] || '';

      let mode = null;

      if (cmd === '/ponytail' || cmd === '/ponytail:ponytail') {
        if (arg === 'lite') mode = 'lite';
        else if (arg === 'full') mode = 'full';
        else if (arg === 'ultra') mode = 'ultra';
        else if (arg === 'off') mode = 'off';
        else mode = getDefaultMode();
      }

      if (mode && mode !== 'off') {
        setMode(mode);
        writeHookOutput(
          'UserPromptSubmit',
          mode,
          'PONYTAIL MODE CHANGED -- level: ' + mode,
        );
        handled = true;
      } else if (mode === 'off') {
        clearMode();
        writeHookOutput('UserPromptSubmit', 'off', 'PONYTAIL MODE OFF');
        handled = true;
      }
    }

    // Detect deactivation
    if (!handled && isDeactivationCommand(prompt)) {
      clearMode();
      writeHookOutput('UserPromptSubmit', 'off', 'PONYTAIL MODE OFF');
      handled = true;
    }

    // Per-turn reinforcement -- keep the active mode alive on ordinary turns.
    if (!handled) {
      const active = readMode();
      if (active) writeHookOutput('UserPromptSubmit', active, reinforcement(active));
    }
  } catch (e) {
    // Silent fail
  }
});
