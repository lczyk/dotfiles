#!/usr/bin/env bash
# spellchecker: words

set -euo pipefail

INPUT="$1"
[ -z "$INPUT" ] && INPUT=$(find . -maxdepth 1 -type f | fzf)
[ -z "$INPUT" ] && exit 1

INPUT=$(realpath "$INPUT")

DIR="$(echo "${INPUT%.rock}")"
if [ -d "$DIR" ]; then
    # confirm if we want to remove the existing directory
    read -p "Directory '$DIR' already exists. Do you want to continue? ([Y]/n): " -n 1 -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

rm -rf "${DIR:-}"
mkdir "$DIR"
tar -xf "$INPUT" -C "$DIR"
(
    cd "$DIR/blobs/sha256" || exit 1

    for blob in *; do
        short_sha="${blob:0:8}"
        blob_path="$DIR/blobs/$short_sha"
        mkdir -p "$blob_path"
        file_info=$(file "$blob")
        if echo "$file_info" | grep -q "gzip compressed data"; then
            echo "Unpacking $short_sha (gzip)"
            # NOTE: assume we are .tar.gz
            gunzip -c "$blob" | tar -xf - -C "$blob_path"
        elif echo "$file_info" | grep -q "JSON text data"; then
            echo "Unpacking $short_sha (JSON)"
            cp "$blob" "$blob_path/blob.json"
        else
            echo "Unknown file type for $short_sha: ${file_info#*: }"
        fi
    done

    rm -rf "$DIR/blobs/sha256"
)

# Show the directory structure if tree is available
command -v tree &>/dev/null && tree -aCL 4 "$DIR"

# Show the metadata if it exists
# this is kina rock-specific. if not found does nothing
echo "--- metadata.yaml: ---"
find "$DIR" -name metadata.yaml -exec cat {} +
