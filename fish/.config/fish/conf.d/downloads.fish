
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
    cp -v "$P" . && rm -rf "$P"
end