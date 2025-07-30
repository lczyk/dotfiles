#!/usr/bin/env bash
# spellchecker: words rockx

INPUT="$1"
[ -z "$INPUT" ] && INPUT=$(find . -maxdepth 1 -type f -name "*.rock" | fzf)
[ -z "$INPUT" ] && exit 1

# make sure we end with .rock
if [[ "$INPUT" != *.rock ]]; then
    echo "Selected file is not a .rock package."
    exit 1
fi

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

# go into DIR/blobs/sha256 and unpack each blob
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

if command -v tree &>/dev/null; then
    tree -aCL 4 "$DIR"
fi

# Show the metadata if it exists
echo "--- metadata.yaml: ---"
find "$DIR" -name metadata.yaml -exec cat {} +
