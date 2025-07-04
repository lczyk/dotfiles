if type -q lxc
    alias lxc-ls='lxc -fcompact -censt ls --all-projects'

    source ~/.config/fish/lxc-throwaway.fish
end
