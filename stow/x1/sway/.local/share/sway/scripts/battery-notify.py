#!/usr/bin/env python3
# Send a desktop notification as the battery drains past each threshold.
# Each threshold fires once per discharge; plugging in re-arms them.

import argparse
import subprocess
import sys
import time
from pathlib import Path

BATTERY = Path("/sys/class/power_supply/qcom-battmgr-bat")

# (percent, urgency). upower powers off at 2% (PercentageAction).
LEVELS = ((20, "normal"), (10, "critical"), (5, "critical"))

REARM_STATUSES = {"Charging", "Full", "Not charging"}


def read_battery(bat: Path) -> tuple[float, str]:
    now = int((bat / "energy_now").read_text())
    full = int((bat / "energy_full").read_text())
    status = (bat / "status").read_text().strip()
    return 100.0 * now / full, status


def check(percent: float, status: str, fired: set[int]) -> tuple[int, str] | None:
    """Return the level to notify about, if any. Updates `fired` in place."""
    if status in REARM_STATUSES:
        fired.clear()
        return None
    if status != "Discharging":
        return None
    crossed = [lv for lv in LEVELS if percent <= lv[0] and lv[0] not in fired]
    if not crossed:
        return None
    fired.update(threshold for threshold, _ in crossed)
    return min(crossed)


def notify(percent: float, urgency: str, replace_id: int | None) -> int | None:
    cmd = ["notify-send", "--print-id", "--app-name=battery", f"--urgency={urgency}"]
    if replace_id is not None:
        cmd.append(f"--replace-id={replace_id}")
    cmd += [f"battery {percent:.0f}%", "plug in -- powers off at 2%"]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return None


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--battery", type=Path, default=BATTERY)
    p.add_argument("--interval", type=float, default=60.0)
    args = p.parse_args()

    fired: set[int] = set()
    notification_id: int | None = None
    while True:
        try:
            percent, status = read_battery(args.battery)
        except (OSError, ValueError, ZeroDivisionError) as e:
            print(f"battery-notify: {e}", file=sys.stderr)
        else:
            level = check(percent, status, fired)
            if level is not None:
                notification_id = notify(percent, level[1], notification_id)
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
