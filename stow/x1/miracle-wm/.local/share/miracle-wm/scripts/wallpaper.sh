#!/bin/sh -e
# Picks a wallpaper with the sway handler and keeps swaybg on it until killed.

PICKER="${HOME}/.local/share/sway/scripts/wallpaper.sh"

BG=$("${PICKER}")
exec swaybg -i "${BG}" -m fill
