#!/usr/bin/env bash

# fsdiff.sh <dir1> <dir2> | grep -vE '^\+\+\+|^---|^@@' | grep '^ '
DIR_1="$1"
DIR_2="$2"
if [ -z "$DIR_1" ] || [ -z "$DIR_2" ]; then
    echo "Usage: $0 <directory1> <directory2>"
    exit 1
fi

if [ ! -d "$DIR_1" ] || [ ! -d "$DIR_2" ]; then
    echo "Both arguments must be directories."
    exit 1
fi

DIR_1=$(realpath "$DIR_1")
DIR_2=$(realpath "$DIR_2")

TMP_1=$(mktemp)
TMP_2=$(mktemp)

find "$DIR_1" -type f | sed "s|$DIR_1/||" | sort > "$TMP_1"
find "$DIR_2" -type f | sed "s|$DIR_2/||" | sort > "$TMP_2"

DIFF=$(diff -u "$TMP_1" "$TMP_2")
echo "$DIFF"

