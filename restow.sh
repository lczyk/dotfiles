#!/usr/bin/env bash

# ALL is an array of all the directories in the current directory
ALL=$(find . -maxdepth 1 -type d ! -name '.*' | sed 's|^\./||' | sort)

for dir in $ALL; do
    if [ -d "$dir" ]; then
        stow --restow --target="$HOME" "$dir" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to restow $dir"
        else
            echo "Restowed $dir"
        fi
    fi
done
