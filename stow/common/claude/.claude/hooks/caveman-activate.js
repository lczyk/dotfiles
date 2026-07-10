#!/usr/bin/env node
// ---------------------------------------------------------------------------
// based on caveman by Julius Brussee (https://github.com/JuliusBrussee/caveman)
// vendored under MIT license -- see ~/.claude/LICENSE-caveman
// ---------------------------------------------------------------------------
// caveman -- Claude Code SessionStart activation hook
//
// Runs on every session start:
//   1. Writes flag file at $CLAUDE_CONFIG_DIR/.caveman-active (statusline reads this)
//   2. Emits caveman ruleset as hidden SessionStart context
//   3. Detects missing statusline config and emits setup nudge

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, getSkillPath, getStatePath, safeWriteFlag } = require('./caveman-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = getStatePath();
const settingsPath = path.join(claudeDir, 'settings.json');

const mode = getDefaultMode();

// "off" mode -- skip activation entirely, don't write flag or emit rules
if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

// 1. Write flag file (symlink-safe)
safeWriteFlag(flagPath, mode);

// 2. Emit full caveman ruleset, filtered to the active intensity level.
const INDEPENDENT_MODES = new Set(['commit', 'compress']);

if (INDEPENDENT_MODES.has(mode)) {
  process.stdout.write('CAVEMAN MODE ACTIVE -- level: ' + mode + '. Behavior defined by /caveman-' + mode + ' skill.');
  process.exit(0);
}

// Read SKILL.md -- the single source of truth for caveman behavior.
// SKILL.md lives at ~/.config/agent-skills/caveman/SKILL.md.
let skillContent = '';
try {
  skillContent = fs.readFileSync(getSkillPath(), 'utf8');
} catch (e) { /* will use fallback below */ }

let output;

if (skillContent) {
  // Strip YAML frontmatter
  const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');

  // Filter intensity table: keep header rows + only the active level's row
  const filtered = body.split('\n').reduce((acc, line) => {
    const tableRowMatch = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (tableRowMatch) {
      if (tableRowMatch[1] === mode) {
        acc.push(line);
      }
      return acc;
    }

    const exampleMatch = line.match(/^- (\S+?):\s/);
    if (exampleMatch) {
      if (exampleMatch[1] === mode) {
        acc.push(line);
      }
      return acc;
    }

    acc.push(line);
    return acc;
  }, []);

  output = 'CAVEMAN MODE ACTIVE -- level: ' + mode + '\n\n' + filtered.join('\n');
} else {
  // Fallback when SKILL.md is not found
  output =
    'CAVEMAN MODE ACTIVE -- level: ' + mode + '\n\n' +
    'respond terse like smart caveman. all technical substance stay. only fluff die.\n\n' +
    '## persistence\n\n' +
    'active every response. no revert after many turns. no filler drift. still active if unsure. off only: "stop caveman" / "normal mode".\n\n' +
    'current level: **' + mode + '**. switch: `/caveman lite|full|ultra`.\n\n' +
    '## rules\n\n' +
    'drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. ' +
    'fragments ok. short synonyms (big not extensive, fix not "implement a solution for"). technical terms exact. code blocks unchanged. errors quoted exact.\n\n' +
    'pattern: `[thing] [action] [reason]. [next step].`\n\n' +
    'not: "sure! i\'d be happy to help you with that. the issue you\'re experiencing is likely caused by..."\n' +
    'yes: "bug in auth middleware. token expiry check use `<` not `<=`. fix:"\n\n' +
    '## composes with lofi\n\n' +
    'lofi = surface (case, en-gb spelling, ascii, short forms), caveman = density (article-drop, fragments, length). orthogonal. apply lofi surface to caveman-compressed output; drop neither. ' +
    'lofi compression-friendly short forms (`b/c`, `w/out`, `->`) stay; expressive/hedge markers (`tbd`, `...`, `alas`, `(?)`) go quiet under full/ultra.\n\n' +
    '## auto-clarity\n\n' +
    'drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread, user asks to clarify or repeats question. resume caveman after clear part done.\n\n' +
    '## boundaries\n\n' +
    'code/commits/PRs: write normal. "stop caveman" or "normal mode": revert. level persist until changed or session end.';
}

// 3. Detect missing statusline config -- nudge Claude to help set it up
try {
  let hasStatusline = false;
  if (fs.existsSync(settingsPath)) {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    if (settings.statusLine) {
      hasStatusline = true;
    }
  }

  if (!hasStatusline) {
    const scriptPath = path.join(__dirname, 'caveman-statusline.sh');
    const command = `bash "${scriptPath}"`;
    const statusLineSnippet =
      '"statusLine": { "type": "command", "command": ' + JSON.stringify(command) + ' }';
    output += "\n\n" +
      "STATUSLINE SETUP NEEDED: The caveman plugin includes a statusline badge showing active mode " +
      "(e.g. [CAVEMAN], [CAVEMAN:ULTRA]). It is not configured yet. " +
      "To enable, add this to " + path.join(claudeDir, 'settings.json') + ": " +
      statusLineSnippet + " " +
      "Proactively offer to set this up for the user on first interaction.";
  }
} catch (e) {
  // Silent fail -- don't block session start over statusline detection
}

process.stdout.write(output);
