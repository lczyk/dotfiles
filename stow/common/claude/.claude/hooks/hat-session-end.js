#!/usr/bin/env node
// hat -- SessionEnd hook
//
// deletes this session's per-session flag file. best-effort cleanup for the
// graceful-exit case; the startup mtime sweep in hat-activate.js is the
// backstop for sessions that never reach here (crash, kill -9, machine sleep
// through the session's whole life) -- SessionEnd itself isn't guaranteed to
// fire.

const fs = require('fs');
const { getSessionFlagPath } = require('./hat-config');

let payload = {};
try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw) payload = JSON.parse(raw);
  }
} catch (e) { /* no/bad stdin -- nothing to clean up */ }

const sessionId = typeof payload.session_id === 'string' ? payload.session_id : null;
const flagPath = sessionId ? getSessionFlagPath(sessionId) : null;
if (flagPath) {
  try { fs.unlinkSync(flagPath); } catch (e) { /* already gone, or never existed */ }
}

process.stdout.write('OK');
