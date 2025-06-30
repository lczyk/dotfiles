if type -q brew
    set -x HOMEBREW_NO_ENV_HINTS 1
end

# if /opt/homebrew/opt/make/libexec/gnubin exists, add it to PATH
if test -d /opt/homebrew/opt/make/libexec/gnubin
    export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
end