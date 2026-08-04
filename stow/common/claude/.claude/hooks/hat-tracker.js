#!/usr/bin/env node
// hat -- UserPromptSubmit hook
//
// parses /hat commands (raw text and claude code's slash-command envelope),
// mutates this session's per-session flag file, and either answers a bare
// /hat status query or reinforces the active hat -- both via additionalContext,
// since a hook can't reply to the turn directly.

const fs = require('fs');
const { VALID_HATS, DEFAULT_HAT, SHORT_REMINDER, getSessionFlagPath, readFlag, safeWriteFlag, touchFlag } = require('./hat-config');

let input = '';
process.stdin.on('data', (chunk) => { input += chunk; });
// an abnormal stdin close (broken pipe, parent crash) emits 'error'; without a
// listener node rethrows it and the hook exits non-zero. hooks must exit 0.
process.stdin.on('error', () => process.exit(0));
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const sessionId = typeof data.session_id === 'string' ? data.session_id : null;
    // collapse whitespace so the multiline slash-command envelope below and
    // the arg-extraction that follows both see a single-line prompt.
    const raw = (data.prompt || '').trim().toLowerCase().replace(/\s+/g, ' ');

    // unattended scheduled-task runs must not switch hats -- the reinforcement
    // would hijack the task prompt. bail before touching flag or output.
    if (/<scheduled-task\b/.test(raw)) return;
    if (!sessionId) return;

    const flagPath = getSessionFlagPath(sessionId);
    if (!flagPath) return;

    // claude code delivers slash commands as an envelope rather than the
    // literal text:
    //   <command-message>hat</command-message>
    //   <command-name>/hat</command-name>
    //   <command-args>yolo</command-args>
    // reconstruct '<name> <args>' for our own command so the parsing below
    // sees what the user selected. a foreign command's envelope is left
    // alone so its args can't be misread as ours.
    let prompt = raw;
    const envName = /<command-name>\s*([^<\s]+)\s*<\/command-name>/.exec(raw);
    if (envName) {
      if (envName[1] === '/hat' || envName[1] === '/hat:hat') {
        const envArgs = /<command-args>\s*([^<]*?)\s*<\/command-args>/.exec(raw);
        const args = envArgs ? envArgs[1].trim() : '';
        prompt = args ? '/hat ' + args : '/hat';
      } else {
        prompt = null;
      }
    }

    let statusQuery = false;

    if (prompt !== null && (prompt === '/hat' || prompt.startsWith('/hat '))) {
      const arg = prompt.slice(4).trim();
      if (!arg) {
        statusQuery = true;
      } else if (arg === 'yolo') {
        safeWriteFlag(flagPath, 'yolo');
      } else if (arg === 'default') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
      // any other arg: leave the current hat untouched
    }

    const activeHat = readFlag(flagPath) || DEFAULT_HAT;
    if (activeHat !== DEFAULT_HAT) touchFlag(flagPath);

    if (statusQuery) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'UserPromptSubmit',
          additionalContext: 'user ran `/hat` with no args -- state the current hat (' +
            activeHat + ') and the valid options (' + VALID_HATS.join(', ') + '), nothing else.',
        },
      }));
      return;
    }

    if (activeHat !== DEFAULT_HAT) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'UserPromptSubmit',
          additionalContext: SHORT_REMINDER[activeHat] || ('hat active (' + activeHat + ').'),
        },
      }));
    }
  } catch (e) {
    // silent fail
  }
});
