#!/usr/bin/env python3
# spawn alacritty inheriting cwd from the focused alacritty's deepest shell.
# any failure -> bare `alacritty` exec.

import json
import os
import subprocess
import sys
import traceback

SHELLS = {"fish", "bash", "zsh", "sh", "dash"}


def find_focused(node: dict) -> dict | None:
    if node.get("focused") is True:
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = find_focused(child)
        if found is not None:
            return found
    return None


def walk_subtree(root: int) -> dict[int, tuple[int, str]]:
    # walk only the descendants of `root` via /proc/<pid>/task/<pid>/children
    # (avoids scanning every pid on the system).
    out: dict[int, tuple[int, str]] = {}
    stack = [(root, 0)]
    while stack:
        pid, ppid = stack.pop()
        try:
            with open(f"/proc/{pid}/comm", "rb") as f:
                comm = f.read().decode("utf-8", "replace").rstrip("\n")
        except OSError:
            continue
        out[pid] = (ppid, comm)
        try:
            with open(f"/proc/{pid}/task/{pid}/children", "rb") as f:
                children = f.read().decode("ascii", "replace").split()
        except OSError:
            continue
        for c in children:
            try:
                stack.append((int(c), pid))
            except ValueError:
                continue
    return out


def find_deepest_shell(procs: dict[int, tuple[int, str]], root: int) -> int | None:
    children: dict[int, list[int]] = {}
    for pid, (ppid, _) in procs.items():
        children.setdefault(ppid, []).append(pid)

    best: tuple[int, int] | None = None  # (depth, pid)
    best_pid: int | None = None
    stack = [(root, 0)]
    while stack:
        pid, depth = stack.pop()
        info = procs.get(pid)
        if info is not None and info[1] in SHELLS and pid != root:
            key = (depth, pid)
            if best is None or key > best:
                best = key
                best_pid = pid
        for ch in children.get(pid, []):
            stack.append((ch, depth + 1))
    return best_pid


def resolve_cwd() -> str | None:
    tree = json.loads(subprocess.run(
        ["swaymsg", "-t", "get_tree"],
        check=True, capture_output=True, text=True,
    ).stdout)
    focused = find_focused(tree)
    if focused is None:
        return None
    if focused.get("app_id") != "Alacritty":
        return None
    pid = focused.get("pid")
    if not isinstance(pid, int):
        return None
    procs = walk_subtree(pid)
    shell_pid = find_deepest_shell(procs, pid)
    if shell_pid is None:
        return None
    cwd = os.readlink(f"/proc/{shell_pid}/cwd")
    if not os.path.isdir(cwd):
        return None
    return cwd


def main() -> None:
    cwd: str | None = None
    try:
        cwd = resolve_cwd()
    except Exception:
        traceback.print_exc()
    if cwd is not None:
        os.execvp("alacritty", ["alacritty", "--working-directory", cwd])
    else:
        os.execvp("alacritty", ["alacritty"])


if __name__ == "__main__":
    main()
    sys.exit(1)  # only reached if execvp fails
