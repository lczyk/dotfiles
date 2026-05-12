#!/usr/bin/env node
// frugal -- UserPromptSubmit hook. Parses /frugal commands, updates flag,
// reinjects per-turn reminder while flag set.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag, VALID_MODES } = require('./frugal-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.frugal-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language activation
    if (/\b(activate|enable|turn on|start)\b.*\bfrugal\b/i.test(prompt) ||
        /\bfrugal\b.*\b(mode|activate|enable|turn on|start)\b/i.test(prompt)) {
      if (!/\b(stop|disable|turn off|deactivate)\b/i.test(prompt)) {
        const def = getDefaultMode();
        const mode = def === 'off' ? 'full' : def;
        safeWriteFlag(flagPath, mode);
      }
    }

    // Match /frugal commands
    if (prompt.startsWith('/frugal')) {
      const parts = prompt.split(/\s+/);
      const cmd = parts[0];
      const arg = parts[1] || '';

      if (cmd === '/frugal' || cmd === '/frugal:frugal') {
        let mode = null;
        if (!arg) {
          const def = getDefaultMode();
          mode = def === 'off' ? 'full' : def;
        } else if (arg === 'off' || arg === 'stop' || arg === 'disable') {
          mode = 'off';
        } else if (VALID_MODES.includes(arg)) {
          mode = arg;
        }

        if (mode === 'off') {
          try { fs.unlinkSync(flagPath); } catch (e) {}
        } else if (mode) {
          safeWriteFlag(flagPath, mode);
        }
      }
    }

    // Natural-language deactivation
    if (/\b(stop|disable|deactivate|turn off)\b.*\bfrugal\b/i.test(prompt) ||
        /\bfrugal\b.*\b(stop|disable|deactivate|turn off)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Per-turn reinforcement
    const activeMode = readFlag(flagPath);
    if (activeMode) {
      const extra = activeMode === 'full'
        ? ' Prefer single big Edit over many small. Avoid speculative agent forks.'
        : '';
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "FRUGAL MODE ACTIVE (" + activeMode + "). " +
            "Batch tool calls. Don't re-read files in context. Use rg/grep to extract." + extra
        }
      }));
    }
  } catch (e) { /* silent */ }
});
