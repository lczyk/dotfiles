# based on .cargo/env.fish
if not contains "$HOME/go/bin" $PATH
    set -x PATH "$HOME/go/bin" $PATH
end