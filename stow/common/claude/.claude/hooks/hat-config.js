#!/usr/bin/env node
// hat -- shared configuration resolver
//
// unlike caveman's single global flag, hat state is one file per session
// under getHatsDir(), keyed by the session_id claude code puts in every
// hook payload. that's what lets concurrent sessions run different hats
// without stomping each other -- see hat-activate.js / hat-tracker.js.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { safeWriteFlag: sharedWriteFlag, readFlagRaw: sharedReadFlagRaw } = require('./flag-io');

const VALID_HATS = ['default', 'yolo'];
const DEFAULT_HAT = 'default';

// backstop for sessions that never fire SessionEnd (crash, kill -9, sleep
// through the session's whole life) -- see hat-tracker.js's per-turn touch,
// which is what keeps a long-lived session's file from looking stale.
const STALE_MS = 7 * 24 * 60 * 60 * 1000;

const SHORT_REMINDER = {
  yolo: 'hat active (yolo). devel-mode: skip worrying about api/back-compat breakage, ' +
    'hesitate less before refactoring/renaming, bundle related commits instead of splitting ' +
    'for a clean history. testing gate, commit conventions, git/gh permission tiers and ' +
    'security care are unaffected -- a hat is instructions, not a permission grant.',
};

function getAgentConfigHome() {
  if (process.env.XDG_CONFIG_HOME) return process.env.XDG_CONFIG_HOME;
  if (process.platform === 'win32') return process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  return path.join(os.homedir(), '.config');
}

function getHatsDir() {
  const stateDir = process.env.AGENT_STATE_DIR || path.join(getAgentConfigHome(), 'agent-state');
  return path.join(stateDir, 'hats');
}

function getSkillPath() {
  return path.join(getAgentConfigHome(), 'agent-skills', 'hat', 'SKILL.md');
}

// session_id is documented as a stable, session-lifetime-unique string;
// sanitize anyway so a malformed value can never escape the hats directory
// via a crafted path (matches the whitelist-then-cap pattern flag-io.js /
// the statusline badges already use elsewhere).
function sanitizeSessionId(sessionId) {
  return String(sessionId || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 128);
}

function getSessionFlagPath(sessionId) {
  const safe = sanitizeSessionId(sessionId);
  if (!safe) return null;
  return path.join(getHatsDir(), safe);
}

function safeWriteFlag(flagPath, content) {
  sharedWriteFlag(flagPath, content);
}

function readFlag(flagPath) {
  const raw = sharedReadFlagRaw(flagPath);
  if (raw === null) return null;
  const hat = raw.toLowerCase();
  return VALID_HATS.includes(hat) ? hat : null;
}

// bump mtime without touching content -- marks "seen alive" for the startup
// staleness sweep, decoupled from when the hat value itself last changed, so
// a long-lived session that set yolo once and never switched again doesn't
// get swept out from under it.
function touchFlag(flagPath) {
  try {
    const now = new Date();
    fs.utimesSync(flagPath, now, now);
  } catch (e) { /* best effort -- missing file, race with SessionEnd, etc */ }
}

function pruneStale() {
  const dir = getHatsDir();
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (e) {
    return;
  }
  const cutoff = Date.now() - STALE_MS;
  for (const name of entries) {
    const p = path.join(dir, name);
    try {
      const st = fs.lstatSync(p);
      if (!st.isFile()) continue; // skips symlinks too -- lstat reports the link itself
      if (st.mtimeMs < cutoff) fs.unlinkSync(p);
    } catch (e) { /* race with another session's write/delete -- ignore */ }
  }
}

// full ruleset for SessionStart -- filtered to the active hat's table row,
// same trick caveman-activate.js uses for intensity levels. only called for
// non-default hats; default has nothing to inject (see hat-activate.js).
function renderRuleset(hat) {
  let skillContent = '';
  try {
    skillContent = fs.readFileSync(getSkillPath(), 'utf8');
  } catch (e) { /* fall through to the inline fallback below */ }

  if (!skillContent) {
    return 'HAT ACTIVE -- ' + hat + '\n\n' + (SHORT_REMINDER[hat] || '');
  }

  const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');
  const filtered = body.split('\n').filter((line) => {
    const row = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (row) return row[1] === hat;
    return true;
  });
  return 'HAT ACTIVE -- ' + hat + '\n\n' + filtered.join('\n');
}

module.exports = {
  VALID_HATS,
  DEFAULT_HAT,
  SHORT_REMINDER,
  getHatsDir,
  getSkillPath,
  getSessionFlagPath,
  sanitizeSessionId,
  safeWriteFlag,
  readFlag,
  touchFlag,
  pruneStale,
  renderRuleset,
};
