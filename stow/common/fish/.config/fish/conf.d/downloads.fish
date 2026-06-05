
# Print recently downloaded item here
function wrd
    set P (/usr/bin/env ls -td ~/Downloads/* | head -n1)
    echo "$P"
end

# Copy recently downloaded item here
function crd
    set P (/usr/bin/env ls -td ~/Downloads/* | head -n1)
    cp -v "$P" .
end

# Move recently downloaded item here
function mrd
    set P (/usr/bin/env ls -td ~/Downloads/* | head -n1)
    mv -v "$P" .
end

# Unpack recently downloaded archive here
function urd
    set P (/usr/bin/env ls -td ~/Downloads/* | head -n1)
    set F (basename "$P")
    set TMP (mktemp -d)

    set FTYPE (file -b "$P")
    echo "unpacking $F"
    echo "  detected: $FTYPE"

    set extracted 0

    if string match -q '*gzip compressed*' "$FTYPE"
        gunzip -c "$P" > "$TMP/_inner"
    else if string match -q '*bzip2 compressed*' "$FTYPE"
        bunzip2 -c "$P" > "$TMP/_inner"
    else if string match -q '*XZ compressed*' "$FTYPE"
        unxz -c "$P" > "$TMP/_inner"
    else if string match -q '*Zstandard compressed*' "$FTYPE"
        zstd -dc "$P" > "$TMP/_inner"
    else if string match -q '*tar archive*' "$FTYPE"
        cp "$P" "$TMP/_inner"
    else if string match -q '*Zip archive*' "$FTYPE"
        unzip -q "$P" -d "$TMP"
        set extracted 1
    else if string match -q '*7-zip archive*' "$FTYPE"
        7z x "$P" -o"$TMP" -y > /dev/null
        set extracted 1
    else if string match -q '*RAR archive*' "$FTYPE"
        unrar x "$P" "$TMP/" > /dev/null
        set extracted 1
    else
        echo "not an archive: $F" >&2
        rm -rf "$TMP"
        return 1
    end

    if test $extracted -eq 0
        set INNER_TYPE (file -b "$TMP/_inner")
        if string match -q '*tar archive*' "$INNER_TYPE"
            tar -xf "$TMP/_inner" -C "$TMP"
        else
            mv "$TMP/_inner" "$TMP/"(string replace -r '\.[^.]+$' '' "$F")
        end
        rm -f "$TMP/_inner"
    end

    for item in $TMP/*
        mv $item .
    end
    rm -rf "$TMP"
end