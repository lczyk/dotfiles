#!/usr/bin/env python3
# Set opacity of focused sway window to `active`, others to `inactive`.
# https://www.reddit.com/r/swaywm/comments/1fijuc0/criteria_to_select_the_currently_focused_window/

import argparse
import json
import subprocess
import sys


def set_opacity(con_id: int, value: float) -> None:
    subprocess.run(
        ["swaymsg", f"[con_id={con_id}]", "opacity", "set", str(value)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--active", type=float, default=0.95)
    p.add_argument("--inactive", type=float, default=0.85)
    args = p.parse_args()

    proc = subprocess.Popen(
        ["swaymsg", "-t", "subscribe", "-m", "-r", '["window"]'],
        stdout=subprocess.PIPE,
        text=True,
    )
    assert proc.stdout is not None

    old: int | None = None
    try:
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                continue
            if evt.get("change") != "focus":
                continue
            new = evt.get("container", {}).get("id")
            if new is None or new == old:
                continue
            if old is not None:
                set_opacity(old, args.inactive)
            set_opacity(new, args.active)
            old = new
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
