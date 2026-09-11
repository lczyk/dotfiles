# cd wrapper for worktree-switch; plain completions live in completions/gg.fish
if type -q gg
    gg completion --cd fish | source
end
