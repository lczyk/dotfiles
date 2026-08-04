#!/usr/bin/env node
// hat -- SessionStart hook
//
// a fresh `startup` has no per-session file yet -- default is represented by
// absence (see hat-config.js), so there's nothing to seed. a resumed session
// keeps whatever this session's file already says; if that's yolo, the full
// ruleset gets re-injected since SessionStart context doesn't carry over
// resume/clear/compaction. every firing also sweeps stale per-session files
// left behind by sessions that never reached hat-session-end.js.

const fs = require('fs');
const { getSessionFlagPath, readFlag, pruneStale, renderRuleset } = require('./hat-config');

let payload = {};
try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw) payload = JSON.parse(raw);
  }
} catch (e) { /* no/bad stdin -- treat as no session id */ }

pruneStale();

const sessionId = typeof payload.session_id === 'string' ? payload.session_id : null;
const flagPath = sessionId ? getSessionFlagPath(sessionId) : null;
const hat = flagPath ? readFlag(flagPath) : null;

if (!hat || hat === 'default') {
  process.stdout.write('OK');
  process.exit(0);
}

process.stdout.write(renderRuleset(hat));
