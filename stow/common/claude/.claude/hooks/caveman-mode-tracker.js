#!/usr/bin/env node
// ---------------------------------------------------------------------------
// based on caveman by Julius Brussee (https://github.com/JuliusBrussee/caveman)
// vendored under MIT license -- see ~/.claude/LICENSE-caveman
// ---------------------------------------------------------------------------
// caveman -- UserPromptSubmit hook to track which caveman mode is active
// Inspects user input for /caveman commands and writes mode to flag file

const fs = require('fs');
const { getDefaultMode, getStatePath, safeWriteFlag, readFlag, VALID_MODES } = require('./caveman-config');

// Modes handled by their own slash commands (/caveman-commit, etc.) -- not
// selectable via /caveman <arg>.
const INDEPENDENT_MODES = new Set(['commit', 'compress']);

const flagPath = getStatePath();

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Match /caveman commands
    if (prompt.startsWith('/caveman')) {
      const parts = prompt.split(/\s+/);
      const cmd = parts[0];
      const arg = parts[1] || '';

      let mode = null;

      if (cmd === '/caveman-commit') {
        mode = 'commit';
      } else if (cmd === '/caveman-compress' || cmd === '/caveman:caveman-compress') {
        mode = 'compress';
      } else if (cmd === '/caveman' || cmd === '/caveman:caveman') {
        if (!arg) {
          mode = getDefaultMode();
        } else if (arg === 'off' || arg === 'stop' || arg === 'disable') {
          mode = 'off';
        } else if (VALID_MODES.includes(arg) && !INDEPENDENT_MODES.has(arg)) {
          mode = arg;
        }
      }

      if (mode && mode !== 'off') {
        safeWriteFlag(flagPath, mode);
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
    }

    // Detect deactivation -- strict whole-message match only, so an ordinary
    // request that happens to mention "stop caveman" / "normal mode" mid-task
    // doesn't silently turn the mode off. toggling is `/caveman <mode>`.
    const deact = prompt.replace(/[.!?\s]+$/, '');
    if (deact === 'stop caveman' || deact === 'normal mode') {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Per-turn reinforcement
    const activeMode = readFlag(flagPath);
    if (activeMode && !INDEPENDENT_MODES.has(activeMode)) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "caveman mode active (" + activeMode + "). " +
            "drop articles/filler/pleasantries/hedging. fragments ok. " +
            "composes with lofi: caveman = density, lofi = surface (lowercase/en-gb/ascii). apply both, drop neither. " +
            "code/commits/security: write normal."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
