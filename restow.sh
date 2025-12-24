#!/usr/bin/env bash
#spellchecker: ignore restow Restowed

function main() {
    local all=$(
        find . -maxdepth 1 -type d \
            ! -name '.*' \
            ! -name 'bin' \
        | sed 's|^\./||' \
        | sort
    )

    for dir in $all; do
        stow --restow --target="$HOME" "$dir" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to restow $dir"
        else
            echo "Restowed $dir"
        fi
    done
}

main "$@"
