import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "stow" / "x1" / "sway" / ".local" / "share" / "sway" / "scripts" / "battery-notify.py"

spec = importlib.util.spec_from_file_location("battery_notify", SCRIPT)
assert spec and spec.loader
battery_notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(battery_notify)

check = battery_notify.check


def test_above_all_levels():
    fired: set[int] = set()
    assert check(55.0, "Discharging", fired) is None
    assert fired == set()


def test_each_level_fires_once():
    fired: set[int] = set()
    assert check(19.9, "Discharging", fired) == (20, "normal")
    assert check(15.0, "Discharging", fired) is None
    assert check(9.5, "Discharging", fired) == (10, "critical")
    assert check(4.8, "Discharging", fired) == (5, "critical")
    assert check(3.0, "Discharging", fired) is None


def test_skipped_levels_collapse_to_lowest():
    # e.g. resumed from suspend at 8%: one notification, not two
    fired: set[int] = set()
    assert check(8.0, "Discharging", fired) == (10, "critical")
    assert fired == {20, 10}
    assert check(7.0, "Discharging", fired) is None


def test_charging_rearms():
    fired: set[int] = set()
    assert check(15.0, "Discharging", fired) == (20, "normal")
    assert check(16.0, "Charging", fired) is None
    assert fired == set()
    assert check(15.0, "Discharging", fired) == (20, "normal")


def test_not_charging_rearms():
    fired = {20, 10}
    assert check(9.0, "Not charging", fired) is None
    assert fired == set()


def test_unknown_status_neither_fires_nor_rearms():
    fired = {20}
    assert check(9.0, "Unknown", fired) is None
    assert fired == {20}


def test_read_battery(tmp_path: Path):
    (tmp_path / "energy_now").write_text("11342500\n")
    (tmp_path / "energy_full").write_text("45370000\n")
    (tmp_path / "status").write_text("Discharging\n")
    percent, status = battery_notify.read_battery(tmp_path)
    assert round(percent, 2) == 25.0
    assert status == "Discharging"
