#!/usr/bin/env bash

INPUT="$1"
if [ -z "$INPUT" ]; then
    # INPUT=$(/usr/bin/ls . | fzf --no-multi-line)
    INPUT=$(find . -maxdepth 1 -type f -name "*.deb" | fzf --no-multi-line)
fi

if [ -z "$INPUT" ]; then
    echo "No file selected."
    exit 1
fi

# make sure we end with .deb
if [[ "$INPUT" != *.deb ]]; then
    echo "Selected file is not a .deb package."
    exit 1
fi

DIR="$(echo "${INPUT%.deb}")"
if [ -d "$DIR" ]; then
    # confirm if we want to remove the existing directory
    read -p "Directory '$DIR' already exists. Do you want to continue? ([Y]/n): " -n 1 -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

rm -rf "$DIR"

mkdir "$DIR"
cp "$INPUT" "$DIR"
cd "$DIR"

ar -x "$INPUT"

if [ -f "control.tar.gz" ]; then
    tar -xzf control.tar.gz -C control
    rm control.tar.gz
elif [ -f "control.tar.zst" ]; then
    mkdir -p control
    mv control.tar.zst control/
    cd control
    tar --zstd -xf control.tar.zst
    rm control.tar.zst
    cd ..
else
    echo "No control.tar.gz found in the package."
    exit 1
fi

if [ -f "data.tar.gz" ]; then
    tar -xzf data.tar.gz
    rm data.tar.gz
elif [ -f "data.tar.zst" ]; then
    mkdir -p data
    mv data.tar.zst data/
    cd data
    tar --zstd -xf data.tar.zst
    rm data.tar.zst
    cd ..
else
    echo "No data.tar.gz found in the package."
    exit 1
fi

rm "$INPUT"
cd ..
tree -C "$DIR"




