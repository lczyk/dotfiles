if type -q eza
    function ls --description 'eza-backed ls, skips --git status on huge repos'
        set -l flags --group-directories-first --long --almost-all --show-symlinks --color=always --time-style=long-iso
        set -l gitdir (command git rev-parse --git-dir 2>/dev/null)
        if test -n "$gitdir"
            set -l idx_size (stat -f%z "$gitdir/index" 2>/dev/null)
            if test -z "$idx_size" -o "$idx_size" -lt 5000000
                set flags $flags --git
            end
        end
        eza $flags $argv
    end
end
