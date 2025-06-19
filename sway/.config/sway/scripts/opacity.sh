#!/usr/bin/env bash

# https://www.reddit.com/r/swaywm/comments/1fijuc0/criteria_to_select_the_currently_focused_window/

# set old 0
# while true
#   set new (swaymsg -t subscribe '["window"]' | jq '.. | select(.type?) | .id')
#   if test "$new" -ne "$old"
#     swaymsg [con_id = $old] opacity set 0.85
#     swaymsg [con_id = $new] opacity set 1.00
#     set old $new
#   end
# end

# exit 0

active=0.9
inactive=0.8

old=0
while true; do
	new=$(swaymsg -t subscribe '["window"]' | jq '.. | select(.type?) | .id')
	if [[ $new -eq $old ]]; then
		continue
	fi
	if [[ $old -ne 0 ]]; then
		swaymsg [con_id = $old] opacity set $inactive 
	fi
	swaymsg [con_id = $new] opacity set $active
	old=$new
done
