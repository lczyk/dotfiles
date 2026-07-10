#!/usr/bin/env node
// ponytail -- shared configuration resolver
//
// Resolution order for default mode:
//   1. PONYTAIL_DEFAULT_MODE environment variable
//   2. Shared config file defaultMode field:
//      - $XDG_CONFIG_HOME/agent-modes/ponytail.json (any platform, if set)
//      - ~/.config/agent-modes/ponytail.json (macOS / Linux fallback)
//      - %APPDATA%\agent-modes\ponytail.json (Windows fallback)
//   3. Legacy ponytail config (for migration only)
//   4. 'full'

const fs = require('fs');
const path = require('path');
const os = require('os');

const DEFAULT_MODE = 'full';
const VALID_MODES = ['off', 'lite', 'full', 'ultra'];
const RUNTIME_MODES = ['off', 'lite', 'full', 'ultra'];

function normalizeMode(mode) {
  if (typeof mode !== 'string') return null;
  const normalized = mode.trim().toLowerCase();
  return RUNTIME_MODES.includes(normalized) ? normalized : null;
}

function normalizeConfigMode(mode) {
  if (typeof mode !== 'string') return null;
  const normalized = mode.trim().toLowerCase();
  return VALID_MODES.includes(normalized) ? normalized : null;
}

function normalizePersistedMode(mode) {
  return normalizeMode(mode) || normalizeConfigMode(mode);
}

// "stop ponytail" / "normal mode" turn ponytail off, but only as a standalone
// command. Matching the phrase anywhere in the message turned it off mid-task
// for ordinary requests like "add a normal mode toggle" -- so require the whole
// message to be the command, ignoring case and trailing punctuation.
function isDeactivationCommand(text) {
  const t = String(text || '').trim().toLowerCase().replace(/[.!?\s]+$/, '');
  return t === 'stop ponytail' || t === 'normal mode';
}

function getAgentConfigHome() {
  if (process.env.XDG_CONFIG_HOME) {
    return process.env.XDG_CONFIG_HOME;
  }
  if (process.platform === 'win32') {
    return process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  }
  return path.join(os.homedir(), '.config');
}

function getConfigDir() {
  return path.join(getAgentConfigHome(), 'agent-modes');
}

function getConfigPath() {
  return path.join(getConfigDir(), 'ponytail.json');
}

function getLegacyConfigPath() {
  return path.join(getAgentConfigHome(), 'ponytail', 'config.json');
}

function getStatePath() {
  const stateDir = process.env.AGENT_STATE_DIR || path.join(getAgentConfigHome(), 'agent-state');
  return path.join(stateDir, 'ponytail-active');
}

function getClaudeDir() {
  // ponytail: CLAUDE_CONFIG_DIR overrides ~/.claude, matching Claude Code.
  return process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
}

function getDefaultMode() {
  // 1. Environment variable (highest priority)
  const envMode = process.env.PONYTAIL_DEFAULT_MODE;
  if (envMode && VALID_MODES.includes(envMode.toLowerCase())) {
    return envMode.toLowerCase();
  }

  // 2. Shared config, then legacy config during migration.
  for (const configPath of [getConfigPath(), getLegacyConfigPath()]) {
    try {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      if (config.defaultMode && VALID_MODES.includes(config.defaultMode.toLowerCase())) {
        return config.defaultMode.toLowerCase();
      }
    } catch (e) {
      // Config file doesn't exist or is invalid -- try the next source.
    }
  }

  // 3. Default
  return DEFAULT_MODE;
}

function writeDefaultMode(mode) {
  const normalized = normalizeConfigMode(mode);
  if (!normalized) return null;

  const configPath = getConfigPath();
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify({ defaultMode: normalized }, null, 2), 'utf8');
  return normalized;
}

module.exports = {
  DEFAULT_MODE,
  VALID_MODES,
  RUNTIME_MODES,
  getDefaultMode,
  getAgentConfigHome,
  getConfigDir,
  getConfigPath,
  getLegacyConfigPath,
  getStatePath,
  getClaudeDir,
  normalizeMode,
  normalizeConfigMode,
  normalizePersistedMode,
  isDeactivationCommand,
  writeDefaultMode,
};
