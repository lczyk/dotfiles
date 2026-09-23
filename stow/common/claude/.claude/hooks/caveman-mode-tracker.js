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
// an abnormal stdin close (broken pipe, parent crash) emits 'error'; without a
// listener node rethrows it and the hook exits non-zero. hooks must exit 0.
process.stdin.on('error', () => process.exit(0));
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    // collapse whitespace so the multiline slash-command envelope below and the
    // whole-message deactivation match both see a single-line prompt.
    const raw = (data.prompt || '').trim().toLowerCase().replace(/\s+/g, ' ');

    // unattended scheduled-task runs must not be styled -- the reinforcement
    // would hijack the task prompt. bail before touching flag or output.
    if (/<scheduled-task\b/.test(raw)) return;

    // claude code delivers slash commands as an envelope rather than the
    // literal text:
    //   <command-message>caveman</command-message>
    //   <command-name>/caveman</command-name>
    //   <command-args>ultra</command-args>
    // reconstruct '<name> <args>' for our own commands so the switch below
    // sees what the user selected. a foreign command's envelope is left alone,
    // and deactivation matching is skipped for it so another command's args
    // can't trip our triggers.
    let prompt = raw;
    let foreignCommand = false;
    const envName = /<command-name>\s*([^<\s]+)\s*<\/command-name>/.exec(raw);
    if (envName) {
      if (envName[1].startsWith('/caveman')) {
        const envArgs = /<command-args>\s*([^<]*?)\s*<\/command-args>/.exec(raw);
        const args = envArgs ? envArgs[1].trim() : '';
        prompt = args ? envName[1] + ' ' + args : envName[1];
      } else {
        foreignCommand = true;
      }
    }

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
    if (!foreignCommand && (deact === 'stop caveman' || deact === 'normal mode')) {
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
            "code/commits/security: full sentences, lofi case still applies."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
