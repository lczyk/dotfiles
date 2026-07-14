import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";

const CONFIG_HOME = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
const EVALUATOR = path.join(CONFIG_HOME, "agent-hooks", "evaluate.sh");

type Request =
  | { version: 1; operation: "shell"; command: string }
  | { version: 1; operation: "write"; write_paths: string[] };

type Verdict =
  | { decision: "allow" }
  | { decision: "deny"; policy: string; reason: string };

function runEvaluator(request: Request): void {
  const result = spawnSync("bash", [EVALUATOR], {
    input: JSON.stringify(request),
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });

  if (result.error || result.status !== 0) {
    const reason = result.stderr.trim() || result.error?.message || "safety evaluator failed";
    throw new Error(`BLOCKED: ${reason}`);
  }

  let verdict: Verdict;
  try {
    verdict = JSON.parse(result.stdout);
  } catch {
    throw new Error("BLOCKED: safety evaluator returned invalid JSON");
  }

  if (verdict.decision === "deny") {
    throw new Error(verdict.reason);
  }
}

function directPaths(args: Record<string, unknown>): string[] {
  return [
    args.file_path,
    args.filePath,
    args.path,
    args.notebook_path,
    args.notebookPath,
  ].filter((value): value is string => typeof value === "string" && value.length > 0);
}

function patchText(args: unknown): string | null {
  if (typeof args === "string") return args;
  if (!args || typeof args !== "object") return null;

  const values = args as Record<string, unknown>;
  for (const key of ["patch", "command", "input"]) {
    if (typeof values[key] === "string") return values[key];
  }
  return null;
}

function patchPaths(patch: string): string[] {
  const paths = new Set<string>();
  for (const line of patch.split(/\r?\n/)) {
    const custom = line.match(/^\*\*\* (?:Add|Update) File: (.*)$/) ||
      line.match(/^\*\*\* Move to: (.*)$/);
    if (custom) paths.add(custom[1]);

    const unified = line.match(/^\+\+\+ b\/(.*)$/);
    if (unified) paths.add(unified[1]);
  }
  return [...paths];
}

export default (async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool.toLowerCase();
      const args = output.args ?? {};

      if (tool === "bash") {
        const command = args.command ?? args.cmd;
        if (typeof command !== "string") {
          throw new Error("BLOCKED: cannot inspect OpenCode shell payload");
        }
        runEvaluator({ version: 1, operation: "shell", command });
        return;
      }

      if (["write", "edit", "notebook_edit"].includes(tool)) {
        const paths = directPaths(args);
        if (paths.length === 0) {
          throw new Error("BLOCKED: cannot inspect OpenCode write destinations");
        }
        runEvaluator({ version: 1, operation: "write", write_paths: paths });
        return;
      }

      if (tool === "apply_patch") {
        const patch = patchText(args);
        if (!patch) throw new Error("BLOCKED: cannot inspect OpenCode patch payload");

        const paths = patchPaths(patch);
        if (paths.length === 0) {
          if (/^\*\*\* Delete File: |^\+\+\+ \/dev\/null$/m.test(patch)) return;
          throw new Error("BLOCKED: cannot inspect OpenCode patch destinations");
        }
        runEvaluator({ version: 1, operation: "write", write_paths: paths });
      }
    },
  };
}) satisfies Plugin;
