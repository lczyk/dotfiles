#!/bin/bash
#
# script by @FunctionalHacker
# https://git.korhonen.cc/FunctionalHacker/dotfiles
# from commit 245694fb0ed6f37f60bce4b4198a22e2cd24da07

# used to exit sway with a menu
# bindsym $mod+Shift+e exec $term --app-id fzf-launcher --login-shell /bin/sh -c "$scripts/exit.sh"

RESP=$(cat <<EOF | fzf +s --tac
Shutdown
Reboot
Suspend
Lock
Logout
Cancel
EOF
);

case "$RESP" in
	Cancel)
		exit 0
		;;
	Shutdown)
		systemctl poweroff
		;;
	Reboot)
		systemctl reboot
		;;
	Suspend)
		systemctl suspend
		;;
	Lock)
		loginctl lock-session $(loginctl show-user $USER -p Sessions | cut -d'=' -f2)
		;;
	Logout)
		swaymsg exit
		;;
	*)
		exit 1
esac
