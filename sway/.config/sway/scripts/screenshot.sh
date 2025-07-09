#!/usr/bin/env bash

# grim -g (slurp -d) ~/screenshots/recent.png
# $SCREENSHOT_DIR

# check if the screenshot directory is set
if [ -z "$SCREENSHOT_DIR" ]; then
    echo "Error: SCREENSHOT_DIR environment variable is not set. Please set it to the path of your screenshots directory."
    exit 1
fi

# check the first argument fir mode (full, area, window)
if [ -z "$1" ]; then
    echo "Usage: $0 <mode> [filename]"
    echo "Modes:"
    echo "  full    - Take a full screenshot"
    echo "  area    - Take a screenshot of a selected area"
    echo "  window  - Take a screenshot of the selected window"
    exit 1
fi

mode="$1"
filename="${2:-$(date +%Y-%m-%d_%H-%M-%S).png}"

case "$mode" in
    full)
        grim "$SCREENSHOT_DIR/$filename"
        ;;
    area)
        grim -g "$(slurp -d)" "$SCREENSHOT_DIR/$filename" 2>/dev/null
        ;;
    window)
        grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .rect | "\(.x),\(.y) \(.width)x\(.height)"')" "$SCREENSHOT_DIR/$filename"
        ;;
    *)
        echo "Invalid mode: $mode"
        echo "Valid modes are: full, area, window"
        exit 1
        ;;
esac

# the recent screenshot is always saved as recent.png
if [ -f "$SCREENSHOT_DIR/$filename" ]; then
    cp "$SCREENSHOT_DIR/$filename" "$SCREENSHOT_DIR/recent.png"
fi

# send a notification
# swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .name' | xargs -I {} notify-send "Screenshot taken" "Saved to $SCREENSHOT_DIR/$filename\nFocused window: {}"