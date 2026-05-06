import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SWAY_SCRIPTS = REPO / "stow" / "x1" / "sway" / ".config" / "sway" / "scripts"

sys.path.insert(0, str(SWAY_SCRIPTS))
