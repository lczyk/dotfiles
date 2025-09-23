if test -e "$HOME/go/env.fish"
    source "$HOME/go/env.fish"
end

# Maybe we installed go manually
# Add Go to PATH if it exists
if test -d /usr/local/go/bin
    set -gx PATH /usr/local/go/bin $PATH
end