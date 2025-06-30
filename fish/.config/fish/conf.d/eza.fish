if type -q eza
    set -x _EZA 'eza --group-directories-first --long --git --almost-all --show-symlinks --color=always --time-style=long-iso' 
    alias ls=$_EZA
    alias ls1="$_EZA -T -L1"
    alias ls2="$_EZA -T -L2"
    alias ls3="$_EZA -T -L3"
end