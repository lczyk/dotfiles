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
        # maybe we're in an environment without sudo (like a container where we're root)
        apt update && apt install -y "${deps[@]}"
    else
        sudo apt update && sudo apt install -y "${deps[@]}"
    fi
}

# make sure we end with .deb
main() {
    local input="$1"
    if [[ "$input" != *.deb ]]; then
        echo "Selected file is not a .deb package."
        exit 1
    fi

    local dir="$(echo "${input%.deb}")"
    if [ -d "$dir" ] && [ $FORCE -eq 0 ]; then
        # confirm if we want to remove the existing directory
        read -p "Directory '$dir' already exists. Do you want to continue? ([Y]/n): " -n 1 -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Exiting without changes."
            exit 0
        fi
    fi

    rm -rf "${dir:-}"

    mkdir "$dir"
    cp "$input" "$dir"
    (
        cd "$dir" || exit 1

        ar -x "$input"

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

        rm "$input"
    )
    if command -v tree &>/dev/null; then
        echo "Directory structure:"
        tree -aC "$dir"
    else
        echo "Tree command not found, showing directory structure with ls:"
        ls -laR "$dir"
    fi
}

################################################################

# parse flags
FORCE=0
INSTALL=0
while [[ "$1" == -* ]]; do
    case "$1" in
        -f|--force)
            FORCE=1; shift;;
        -I|--install)
            INSTALL=1; shift; ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ $INSTALL -eq 1 ]; then
    echo "Installing dependencies..."
    install
    exit 0
fi

INPUT="$1"
if [ -z "$INPUT" ]; then
    if command -v fzf &>/dev/null; then
        # NOTE: we don't use --no-multi-line because some of the older versions of fzf don't support it
        INPUT=$(find . -maxdepth 1 -type f -name "*.deb" | fzf)
    else
        echo "No input file provided. Please specify a .deb package or use fzf to select one."
        exit 1
    fi
fi

if [ -z "$INPUT" ]; then
    echo "No file selected."
    exit 1
else
    main "$INPUT"
fi
