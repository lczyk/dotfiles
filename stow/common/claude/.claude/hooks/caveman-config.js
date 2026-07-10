#!/usr/bin/env node
// ---------------------------------------------------------------------------
// based on caveman by Julius Brussee (https://github.com/JuliusBrussee/caveman)
// vendored under MIT license -- see ~/.claude/LICENSE-caveman
// ---------------------------------------------------------------------------
// caveman -- shared configuration resolver
//
// Resolution order for default mode:
//   1. CAVEMAN_DEFAULT_MODE environment variable
//   2. Shared config file defaultMode field:
//      - $XDG_CONFIG_HOME/agent-modes/caveman.json (any platform, if set)
//      - ~/.config/agent-modes/caveman.json (macOS / Linux fallback)
//      - %APPDATA%\agent-modes\caveman.json (Windows fallback)
//   3. Legacy caveman config (for migration only)
//   4. 'full'

const fs = require('fs');
const path = require('path');
const os = require('os');
const { safeWriteFlag: sharedWriteFlag, readFlagRaw: sharedReadFlagRaw } = require('./flag-io');

const VALID_MODES = [
  'off', 'lite', 'full', 'ultra',
  'commit', 'compress'
];

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
  return path.join(getConfigDir(), 'caveman.json');
}

function getLegacyConfigPath() {
  return path.join(getAgentConfigHome(), 'caveman', 'config.json');
}

function getStatePath() {
  const stateDir = process.env.AGENT_STATE_DIR || path.join(getAgentConfigHome(), 'agent-state');
  return path.join(stateDir, 'caveman-active');
}

function getSkillPath() {
  return path.join(getAgentConfigHome(), 'agent-skills', 'caveman', 'SKILL.md');
}

function getDefaultMode() {
  // 1. Environment variable (highest priority)
  const envMode = process.env.CAVEMAN_DEFAULT_MODE;
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
  return 'full';
}

// flag io is symlink-safe and shared with ponytail -- see ./flag-io.js.
function safeWriteFlag(flagPath, content) {
  sharedWriteFlag(flagPath, content);
}

function readFlag(flagPath) {
  const raw = sharedReadFlagRaw(flagPath);
  if (raw === null) return null;
  const mode = raw.toLowerCase();
  return VALID_MODES.includes(mode) ? mode : null;
}

module.exports = {
  getDefaultMode,
  getConfigDir,
  getConfigPath,
  getLegacyConfigPath,
  getSkillPath,
  getStatePath,
  VALID_MODES,
  safeWriteFlag,
  readFlag,
};
