#!/usr/bin/env bash
# spellchecker: words debx binutils zstd Marcin Konowalczyk lczyk tzdata noninteractive debname

__VERSION__="0.3.2"
__AUTHOR__="Marcin Konowalczyk @lczyk"
__LICENSE__="MIT-0"
# aka no liability, do whatever you want with it,
# no need to credit me, but it would be nice :)

fatal() {
    echo "$1" >&2
    exit 1
}

help() {
    cat << EOF
Usage: $0 [Install|Download|Unpack] [options] [file.deb]

Extracts the contents of a .deb package into a directory named after the package (without .deb extension).
If no file is provided, it will attempt to use fzf to select a .deb file in the current directory.
If no mode is provided, it defaults to Unpack.

Modes:
  Install          Installs necessary dependencies (fzf, binutils, tree, tar, zstd).
  Download         Downloads a .deb package from the apt repository and unpacks it.
  Unpack           Unpacks a specified .deb file (default mode).

Options:
  -f, --force       Force overwrite if the target directory already exists.
  -h, --help        Display this help message and exit.
EOF
}

download() {
    local package="$1"
    [ -n "$package" ] || fatal "No package name provided for download."
    command -v apt &>/dev/null || fatal "apt command not found. Cannot download package."
    echo "Downloading package: $package"
    local tmpdir
    tmpdir=$(mktemp -d) || fatal "Failed to create temporary directory."
    trap 'rm -rf "$tmpdir"' EXIT
    
    (
        cd "$tmpdir" || exit 1
        apt download "$package"
    )
    local debname=$(find "$tmpdir" -maxdepth 1 -type f -name "*.deb" -printf "%P\n" -quit)
    [ -n "$debname" ] || fatal "Failed to download package '$package'."

    mv "$tmpdir/$debname" ./"$debname"
    echo "Moved package to current directory: ./$debname"

    # unpack the downloaded package
    unpack "$debname"
}

# Install all dependencies if requested
# ./debx.sh -I

# This enables a one-liner to extract a .deb package for a different base than host.
# E.g. Extracting golang-1.22-src from Ubuntu 24.04 using podman:
# `podman run -it --rm -v$(pwd):/mnt ubuntu:24.04 bash -c 'cd mnt; ./debx.sh -I; apt download golang-1.22-src; ./debx.sh *.deb'`

install() {
    echo "Installing dependencies..."
    local deps=(fzf binutils tree tar zstd)
    if ! command -v sudo &>/dev/null; then
        # maybe we're in an environment without sudo (like a container where we're root)
        apt update && apt install -y "${deps[@]}"
    else
        sudo apt update && sudo apt install -y "${deps[@]}"
    fi
    # also install tzdata, since this is always a pain in noninteractive environments
    if ! command -v sudo &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt install -y tzdata
    else
        DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC sudo apt install -y tzdata
    fi
}

# make sure we end with .deb
unpack() {
    local input="$1"
    [ -n "$input" ] || fatal "No .deb file provided for unpacking."
    [[ "$input" != *.deb ]] && fatal "No .deb file provided for unpacking."
    [ -f "$input" ] || fatal "File '$input' does not exist."
    local dir="$(echo "${input%.deb}")"
    if [ -d "$dir" ] && [ $FORCE -eq 0 ]; then
        # confirm if we want to remove the existing directory
        read -p "Directory '$dir' already exists. Do you want to continue? (yes/no/[T]ree): " -n 1 -r
        case $REPLY in
            [Nn]* ) echo "Exiting without changes."; exit 0; ;;
            [Yy]* ) ;;
            [Tt]* ) tree "$dir"; exit 0; ;;
            * ) fatal "Invalid response. Exiting." ;;
        esac
    fi

    rm -rf "${dir:-}"

    mkdir "$dir"
    cp "$input" "$dir"
    (
        cd "$dir" || exit 1

        # deb is a thin archive, so we need to use `ar`
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
        elif [ -f "control.tar.xz" ]; then
            mkdir -p control
            mv control.tar.xz control/
            (
                cd control || exit 1
                tar -xf control.tar.xz
                rm control.tar.xz
            )
        else
            echo "No control archive found in the package."
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
        elif [ -f "data.tar.xz" ]; then
            mkdir -p data
            mv data.tar.xz data/
            (
                cd data || exit 1
                tar -xf data.tar.xz
                rm data.tar.xz
            )
        else
            fatal "No data archive found in the package."
        fi

        rm "$input"
    )
    debx_tree "$dir"
}

debx_tree() {
    local dir="$1"
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
MODE=""
ARGS=()
parse_args() {
    # parse mode. this must be the first argument
    case "$1" in
        -I|--install|I|install)
            MODE="install"; shift ;;
        d|--D|--download|D|download)
            MODE="download"; shift ;;
        --U|--unpack|U|unpack)
            MODE="unpack"; shift ;;
    esac

    # default to unpack
    if [ -z "$MODE" ]; then
        MODE="unpack"
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--force)
                FORCE=1; shift;;
            -h|--help) help; exit 0; ;;
            -v|--version)
                echo "$0 version $__VERSION__ by $__AUTHOR__"
                exit 0 ;;
            *) break ;;
        esac
    done

    ARGS=("$@")
}

main() {
    local input="$1"
    case "$MODE" in
        install) ;;
        unpack)
            if [ -z "$input" ]; then
                command -v fzf &>/dev/null || fatal "fzf is not installed. Please install it or provide a .deb file as an argument."
                input=$(find . -maxdepth 1 -type f -name "*.deb" | fzf --prompt="Select a .deb file: ")
                [ -n "$input" ] || fatal "No .deb file selected."
            fi ;;
        download)
            if [ -z "$input" ]; then
                command -v fzf &>/dev/null || fatal "fzf is not installed. Please install it or provide a package name as an argument."
                input=$(apt-cache search . | cut -d' ' -f1 | fzf --prompt="Select a package to download: ")
                [ -n "$input" ] || fatal "No package selected."
            fi ;;
        *) fatal "Unknown mode: $MODE" ;;
    esac

    case "$MODE" in
        install)
            install ;;
        download)
            download "$input" ;;
        unpack)
            unpack "$input" ;;
        *) fatal "Unknown mode: $MODE" ;;
    esac
}

parse_args "$@"
main "${ARGS[0]}"

__LICENSE__='
MIT No Attribution

Copyright 2025 Marcin Konowalczyk @lczyk

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
'
