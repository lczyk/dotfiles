import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";

const HOOKS_DIR = path.join(os.homedir(), ".config", "agent-hooks");

const HOOKS_BY_TOOL: Record<string, string[]> = {
  bash: [
    "block-dangerous.sh",
    "discourage-bare-tail.sh",
    "enforce-log-suffix.sh",
    "enforce-tmp-ai.sh",
  ],
  write: ["enforce-tmp-ai.sh"],
  edit: ["enforce-tmp-ai.sh"],
  notebook_edit: ["enforce-tmp-ai.sh"],
};

function runHook(hook: string, payload: string): void {
  const result = spawnSync("bash", [path.join(HOOKS_DIR, hook)], {
    input: payload,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });

  if (result.error || result.status !== 0) {
    const reason = result.stderr.trim() || `${hook} failed`;
    throw new Error(`BLOCKED: ${reason}`);
  }
}

export default (async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const hooks = HOOKS_BY_TOOL[input.tool.toLowerCase()];
      if (!hooks || hooks.length === 0) return;

      const args = output.args ?? {};
      const payload = JSON.stringify({
        tool_input: {
          command: args.command ?? args.cmd,
          file_path: args.file_path ?? args.filePath,
        },
      });

      for (const hook of hooks) {
        runHook(hook, payload);
      }
    },
  };
}) satisfies Plugin;
