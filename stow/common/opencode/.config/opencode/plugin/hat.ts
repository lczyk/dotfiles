import type { Plugin } from "@opencode-ai/plugin";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// ---------------------------------------------------------------------------
// hat -- behavioral mode switch, ported from the claude-code hat hooks.
//   - unlike caveman's single global flag, state is per-session: one file per
//     sessionID under HATS_DIR. claude code correlates via session_id in its
//     hook/statusline payloads; opencode's plugin api exposes the same thing
//     as `sessionID` on chat.message / experimental.chat.system.transform.
//   - one plugin collapses claude's three hooks (SessionStart, UserPromptSubmit,
//     SessionEnd):
//       chat.message                        -> toggle hat from /hat <arg>
//       experimental.chat.system.transform  -> inject ruleset every turn
//       event (session.created/session.deleted) -> stale sweep / cleanup
//   - source of truth is the shared agent-skills package.
// ---------------------------------------------------------------------------

const VALID = ["default", "yolo"] as const;
type Hat = (typeof VALID)[number];
const DEFAULT_HAT: Hat = "default";

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
const STATE_DIR = process.env.AGENT_STATE_DIR || path.join(CONFIG_HOME, "agent-state");
const HATS_DIR = path.join(STATE_DIR, "hats");
const SKILL = path.join(CONFIG_HOME, "agent-skills", "hat", "SKILL.md");

// backstop for sessions that never emit session.deleted -- mirrors the
// claude-side hat-config.js sweep.
const STALE_MS = 7 * 24 * 60 * 60 * 1000;

function sanitize(sessionID: string): string {
  return sessionID.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 128);
}

function flagPath(sessionID: string): string | null {
  const safe = sanitize(sessionID);
  return safe ? path.join(HATS_DIR, safe) : null;
}

function writeHat(sessionID: string, hat: Hat): void {
  const p = flagPath(sessionID);
  if (!p) return;
  fs.mkdirSync(HATS_DIR, { recursive: true });
  fs.writeFileSync(p, hat, { mode: 0o600 });
}

function deleteHat(sessionID: string): void {
  const p = flagPath(sessionID);
  if (!p) return;
  try { fs.unlinkSync(p); } catch {}
}

function readHat(sessionID: string): Hat | null {
  const p = flagPath(sessionID);
  if (!p) return null;
  try {
    const h = fs.readFileSync(p, "utf8").trim().toLowerCase();
    return (VALID as readonly string[]).includes(h) ? (h as Hat) : null;
  } catch {
    return null;
  }
}

// bump mtime without touching content -- marks "seen alive" for the
// session.created sweep, decoupled from when the hat value itself last
// changed (a long-lived session that set yolo once shouldn't get swept).
function touchHat(sessionID: string): void {
  const p = flagPath(sessionID);
  if (!p) return;
  try {
    const now = new Date();
    fs.utimesSync(p, now, now);
  } catch {}
}

function pruneStale(): void {
  let entries: string[];
  try {
    entries = fs.readdirSync(HATS_DIR);
  } catch {
    return;
  }
  const cutoff = Date.now() - STALE_MS;
  for (const name of entries) {
    const p = path.join(HATS_DIR, name);
    try {
      const st = fs.lstatSync(p);
      if (!st.isFile()) continue;
      if (st.mtimeMs < cutoff) fs.unlinkSync(p);
    } catch {}
  }
}

// filter SKILL.md body to the active hat: strip frontmatter, keep only the
// matching table row.
function ruleset(hat: Hat): string {
  let body: string;
  try {
    body = fs.readFileSync(SKILL, "utf8").replace(/^---[\s\S]*?---\s*/, "");
  } catch {
    return `HAT ACTIVE (${hat}). devel-mode: skip worrying about api/back-compat breakage, hesitate less before refactoring, bundle commits instead of splitting. testing gate, commit conventions, git/gh permission tiers, security care unaffected.`;
  }
  const kept = body.split("\n").filter((line) => {
    const row = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (row) return row[1] === hat;
    return true;
  });
  return `HAT ACTIVE -- ${hat}\n\n${kept.join("\n")}`;
}

function text(parts: any[]): string {
  return parts
    .filter((p) => p?.type === "text" && typeof p.text === "string")
    .map((p) => p.text)
    .join(" ")
    .trim()
    .toLowerCase();
}

// set by chat.message on a bare `/hat`, consumed by the very next
// system.transform call for the same turn -- chat.message can't inject
// system text itself, so a status query has to hand off across hooks.
const pendingStatusQuery = new Set<string>();

export default (async () => {
  return {
    "chat.message": async (input, output) => {
      const sessionID = input.sessionID;
      const prompt = text(output.parts);

      if (prompt === "/hat" || prompt.startsWith("/hat ")) {
        const arg = prompt.slice(4).trim();
        if (!arg) {
          pendingStatusQuery.add(sessionID);
        } else if (arg === "yolo") {
          writeHat(sessionID, "yolo");
        } else if (arg === "default") {
          deleteHat(sessionID);
        }
        // any other arg: leave the current hat untouched
      }
    },

    "experimental.chat.system.transform": async (input, output) => {
      const sessionID = input.sessionID;
      if (!sessionID) return;

      if (pendingStatusQuery.delete(sessionID)) {
        const hat = readHat(sessionID) ?? DEFAULT_HAT;
        output.system.push(
          `user ran /hat with no args -- state the current hat (${hat}) and the valid options (${VALID.join(", ")}), nothing else.`
        );
        return;
      }

      const hat = readHat(sessionID);
      if (hat && hat !== DEFAULT_HAT) {
        touchHat(sessionID);
        output.system.push(ruleset(hat));
      }
    },

    event: async ({ event }) => {
      if (event.type === "session.created") {
        pruneStale();
      } else if (event.type === "session.deleted") {
        deleteHat(event.properties.info.id);
      }
    },
  };
}) satisfies Plugin;
