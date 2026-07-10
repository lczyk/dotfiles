import type { Plugin } from "@opencode-ai/plugin";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// ---------------------------------------------------------------------------
// based on caveman by Julius Brussee (https://github.com/JuliusBrussee/caveman)
// port of the claude-code caveman plugin to opencode.
//   - claude used two hooks (SessionStart activation + UserPromptSubmit tracker)
//     plus a statusline badge. opencode collapses this to one plugin:
//       chat.message                     -> toggle mode from /caveman <mode>
//       experimental.chat.system.transform -> inject ruleset every turn
//   - source of truth is the shared agent-skills package.
//   - commit/compress modes and the statusline badge are claude-only; skipped.
//     NOTE: add an opencode command if /caveman-commit is ever wanted here.
// ---------------------------------------------------------------------------

const VALID = ["lite", "full", "ultra"] as const;
type Mode = (typeof VALID)[number];

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
const STATE_DIR = process.env.AGENT_STATE_DIR || path.join(CONFIG_HOME, "agent-state");
const FLAG = path.join(STATE_DIR, "caveman-active");
const SKILL = path.join(CONFIG_HOME, "agent-skills", "caveman", "SKILL.md");

function writeMode(mode: Mode): void {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(FLAG, mode, { mode: 0o600 });
}

function readMode(): Mode | null {
  try {
    const m = fs.readFileSync(FLAG, "utf8").trim().toLowerCase();
    return (VALID as readonly string[]).includes(m) ? (m as Mode) : null;
  } catch {
    return null;
  }
}

// filter SKILL.md body to the active level: strip frontmatter, keep only the
// intensity-table row and `- <level>:` example line matching `mode`.
function ruleset(mode: Mode): string {
  let body: string;
  try {
    body = fs.readFileSync(SKILL, "utf8").replace(/^---[\s\S]*?---\s*/, "");
  } catch {
    return `CAVEMAN MODE ACTIVE (${mode}). Drop articles/filler/pleasantries/hedging. Fragments OK. Code/commits/security: write normal.`;
  }
  const kept = body.split("\n").filter((line) => {
    const row = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (row) return row[1] === mode;
    const ex = line.match(/^- (\S+?):\s/);
    if (ex) return ex[1] === mode;
    return true;
  });
  return `CAVEMAN MODE ACTIVE -- level: ${mode}\n\n${kept.join("\n")}`;
}

function text(parts: any[]): string {
  return parts
    .filter((p) => p?.type === "text" && typeof p.text === "string")
    .map((p) => p.text)
    .join(" ")
    .trim()
    .toLowerCase();
}

export default (async () => {
  return {
    "chat.message": async (_input, output) => {
      const prompt = text(output.parts);

      if (prompt.startsWith("/caveman")) {
        const arg = prompt.split(/\s+/)[1] ?? "";
        if (!arg) {
          writeMode("full");
        } else if (arg === "off" || arg === "stop" || arg === "disable") {
          try { fs.unlinkSync(FLAG); } catch {}
        } else if ((VALID as readonly string[]).includes(arg)) {
          writeMode(arg as Mode);
        }
        return;
      }

      // whole-message deactivation only, so a task mentioning "stop caveman"
      // mid-sentence doesn't silently disable it.
      const deact = prompt.replace(/[.!?\s]+$/, "");
      if (deact === "stop caveman" || deact === "normal mode") {
        try { fs.unlinkSync(FLAG); } catch {}
      }
    },

    "experimental.chat.system.transform": async (_input, output) => {
      const mode = readMode();
      if (mode) output.system.push(ruleset(mode));
    },
  };
}) satisfies Plugin;
