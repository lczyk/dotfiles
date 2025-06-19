# based on .cargo/env.fish
if not contains "$HOME/.docker/bin" $PATH
    set -x PATH "$HOME/.docker/bin" $PATH
end