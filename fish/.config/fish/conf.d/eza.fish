if type -q eza
    set -x _EZA 'eza --group-directories-first --long --git --almost-all --show-symlinks --color=always --time-style=long-iso'
    alias ls=$_EZA
end
