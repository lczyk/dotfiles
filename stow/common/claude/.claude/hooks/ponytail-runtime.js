const fs = require('fs');
const path = require('path');
const { getClaudeDir, normalizeMode } = require('./ponytail-config');
const { safeWriteFlag, readFlagRaw } = require('./flag-io');

const STATE_FILE = '.ponytail-active';
const isCopilot = Boolean(process.env.COPILOT_PLUGIN_DATA);
const isCodex = !isCopilot && Boolean(process.env.PLUGIN_DATA);

let stateDir = getClaudeDir();
if (isCodex) stateDir = process.env.PLUGIN_DATA;
if (isCopilot) stateDir = process.env.COPILOT_PLUGIN_DATA;

const statePath = path.join(stateDir, STATE_FILE);

function setMode(mode) {
  safeWriteFlag(statePath, mode);
}

function clearMode() {
  try { fs.unlinkSync(statePath); } catch (e) {}
}

function readMode() {
  return normalizeMode(readFlagRaw(statePath));
}

function writeHookOutput(event, mode, context = '') {
  if (isCopilot) {
    // Copilot reads additionalContext on SessionStart; ignores output elsewhere.
    process.stdout.write(JSON.stringify(
      event === 'SessionStart' && context ? { additionalContext: context } : {}));
    return;
  }
  if (isCodex) {
    const output = { systemMessage: `PONYTAIL:${mode.toUpperCase()}` };
    if (context) {
      output.hookSpecificOutput = {
        hookEventName: event,
        additionalContext: context,
      };
    }
    process.stdout.write(JSON.stringify(output));
    return;
  }
  process.stdout.write(context);
}

module.exports = {
  clearMode,
  isCodex,
  isCopilot,
  readMode,
  setMode,
  writeHookOutput,
};
