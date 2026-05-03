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

# TODO: fix bash env
# **TEMPORARILY** HACK IN .local/bin into the path 
if ! command -v grim &> /dev/null; then
    if [ -f "$HOME/.local/bin/grim" ]; then
        PATH="$PATH:$HOME/.local/bin"
    else
        echo "Error: grim is not installed or not found in PATH. Please install grim."
        exit 1
    fi
fi

case "$mode" in
    full)
        grim "$SCREENSHOT_DIR/$filename"
        ;;
    area)
        grim -g "$(slurp -d)" "$SCREENSHOT_DIR/$filename"
        ;;
    color-clipboard)
        position=$(slurp -p)
        temp_file=$(mktemp --suffix=.ppm)
        grim -t ppm -g "$position" "$temp_file"
        # parse the ppm file to get the color of the only pixel
        # note that the 4th line will be the RBG in *bytes* so we need to convert it to hex
        color=$(tail -n +4 "$temp_file" | head -n 1 | od -An -t u1 | tr -s ' ' | cut -d ' ' -f 2-4 | awk '{printf("#%02x%02x%02x\n", $1, $2, $3)}')
        echo "Picked color: $color"
        echo -n "$color" | wl-copy
        rm "$temp_file"
        ;;
    window)
        # grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .rect | "\(.x),\(.y) \(.width)x\(.height)"')" "$SCREENSHOT_DIR/$filename"
        grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.pid? and .visible?) | "\(.rect.x+.window_rect.x),\(.rect.y+.window_rect.y) \(.window_rect.width)x\(.window_rect.height)"' | slurp)" "$SCREENSHOT_DIR/$filename"
        ;;
    *)
        echo "Invalid mode: $mode"
        echo "Valid modes are: full, area, window and color-clipboard"
        exit 1
        ;;
esac

# the recent screenshot is always saved as recent.png
if [ -f "$SCREENSHOT_DIR/$filename" ]; then
    cp "$SCREENSHOT_DIR/$filename" "$SCREENSHOT_DIR/recent.png"
    echo "Screenshot saved to $SCREENSHOT_DIR/$filename"
fi
