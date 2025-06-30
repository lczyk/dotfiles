if type -q fzf
    # TODO: fzf shell integration does not work in onlder versions of fzf
    # see: https://github.com/junegunn/fzf?tab=readme-ov-file#installation
    fzf --fish 2>/dev/null | source
    export FZF_DEFAULT_OPTS='--multi --exact --cycle --height 40% --layout reverse --border top'
end