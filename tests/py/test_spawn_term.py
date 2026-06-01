import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "stow" / "x1" / "sway" / ".local" / "share" / "sway" / "scripts" / "spawn-term.py"

spec = importlib.util.spec_from_file_location("spawn_term", SCRIPT)
assert spec and spec.loader
spawn_term = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spawn_term)


def make(*entries: tuple[int, int, str]) -> dict[int, tuple[int, str]]:
    return {pid: (ppid, comm) for pid, ppid, comm in entries}


def test_simple_shell_child():
    # ala(100) -> fish(101)
    procs = make((100, 1, "alacritty"), (101, 100, "fish"))
    assert spawn_term.find_deepest_shell(procs, 100) == 101


def test_skip_non_shell():
    # ala(100) -> fish(101) -> nvim(102) -- pick fish, not nvim
    procs = make(
        (100, 1, "alacritty"),
        (101, 100, "fish"),
        (102, 101, "nvim"),
    )
    assert spawn_term.find_deepest_shell(procs, 100) == 101


def test_deep_nested_shells():
    # ala -> bash -> tmux -> nvim -> bash -> bash
    procs = make(
        (100, 1, "alacritty"),
        (101, 100, "bash"),
        (102, 101, "tmux"),
        (103, 102, "nvim"),
        (104, 103, "bash"),
        (105, 104, "bash"),
    )
    assert spawn_term.find_deepest_shell(procs, 100) == 105


def test_no_shell_descendant():
    # ala -> nvim only
    procs = make((100, 1, "alacritty"), (101, 100, "nvim"))
    assert spawn_term.find_deepest_shell(procs, 100) is None


def test_no_descendants():
    procs = make((100, 1, "alacritty"))
    assert spawn_term.find_deepest_shell(procs, 100) is None


def test_tie_at_same_depth_picks_higher_pid():
    # ala -> bash(101) -> bash_a(102), ala -> bash(101) -> bash_b(103)
    # both bash_a and bash_b at depth 2 -- expect higher pid wins
    procs = make(
        (100, 1, "alacritty"),
        (101, 100, "bash"),
        (102, 101, "bash"),
        (103, 101, "bash"),
    )
    assert spawn_term.find_deepest_shell(procs, 100) == 103


def test_root_alacritty_not_returned_even_if_misnamed_as_shell():
    # defensive: if the root pid happens to match SHELLS, don't return it
    procs = make((100, 1, "bash"))
    assert spawn_term.find_deepest_shell(procs, 100) is None


def test_all_shell_kinds_recognised():
    for shell in ("fish", "bash", "zsh", "sh", "dash"):
        procs = make((100, 1, "alacritty"), (101, 100, shell))
        assert spawn_term.find_deepest_shell(procs, 100) == 101, shell
