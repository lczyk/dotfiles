#!/bin/sh -e
# Opens the sway fuzzy launcher in a terminal; the app id matches the float rule in config.yaml.

LAUNCHER="${HOME}/.local/share/sway/scripts/launcher.sh"

exec alacritty --class launcher --command "${LAUNCHER}"
