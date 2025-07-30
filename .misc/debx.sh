#!/usr/bin/env bash
# spellchecker: words debx binutils zstd

# Install all dependencies if requested
# ./debx.sh -I

# This enables a one-liner to extract a .deb package for a different base than host.
# E.g. Extracting golang-1.22-src from Ubuntu 24.04 using podman:
# `podman run -it --rm -v$(pwd):/mnt ubuntu:24.04 bash -c 'cd mnt; ./debx.sh -I; apt download golang-1.22-src; ./debx.sh *.deb'`

install() {
    local deps=(fzf binutils tree tar zstd)
    if ! command -v sudo &>/dev/null; then
        # maybe we're in an environment without sudo
        apt update && apt install -y "${deps[@]}"
    else
        sudo apt update && sudo apt install -y "${deps[@]}"
    fi
}

# make sure we end with .deb
main() {
    if [[ "$INPUT" != *.deb ]]; then
        echo "Selected file is not a .de)b package."
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

    rm -rf "${DIR:-}"

    mkdir "$DIR"
    cp "$INPUT" "$DIR"
    (
        cd "$DIR" || exit 1

        ar -x "$INPUT"

        if [ -f "control.tar.gz" ]; then
            tar -xzf control.tar.gz -C control
            rm control.tar.gz
        elif [ -f "control.tar.zst" ]; then
            mkdir -p control
            mv control.tar.zst control/
            (
                cd control || exit 1
                tar --zstd -xf control.tar.zst
                rm control.tar.zst
            )
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
            (
                cd data || exit 1
                tar --zstd -xf data.tar.zst
                rm data.tar.zst
            )
        else
            echo "No data.tar.gz found in the package."
            exit 1
        fi

        rm "$INPUT"
    )
    tree -C "$DIR"
}

################################################################

INPUT="$1"
if [ -z "$INPUT" ]; then
    # INPUT=$(/usr/bin/ls . | fzf --no-multi-line)
    # NOTE: we don't use --no-multi-line because some of the older versions of fzf don't support it
    INPUT=$(find . -maxdepth 1 -type f -name "*.deb" | fzf)
fi

if [ -z "$INPUT" ]; then
    echo "No file selected."
    exit 1
elif [ "$INPUT" == "--install" ] || [ "$INPUT" == "-I" ]; then
    install
else
    main "$INPUT"
fi
