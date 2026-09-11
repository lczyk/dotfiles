function fish_prompt
    set -l last_status $status

    set -l normal (set_color normal)
    set -l usercolor (set_color $fish_color_user)

    # set -l delim \U25BA
    set -l delim "»"
    # If we don't have unicode use a simpler delimiter
    string match -qi "*.utf-8" -- $LANG $LC_CTYPE $LC_ALL; or set delim ">"

    fish_is_root_user; and set delim "#"

    set -l cwd (set_color $fish_color_cwd)
    if command -sq cksum
        # per-directory colour: hash the physical pwd into one of the terminal's
        # palette slots. deterministic per directory, follows the active palette.
        set -l slots red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan
        set -l sum (pwd -P | cksum | string split -f1 ' ')
        set cwd (set_color $slots[(math "$sum % "(count $slots)" + 1")])
    end

    # Prompt status only if it's not 0
    set -l prompt_status
    test $last_status -ne 0; and set prompt_status (set_color $fish_color_status)"[$last_status]$normal"

    # Only show host if in SSH or container
    # Store this in a global variable because it's slow and unchanging
    if not set -q prompt_host
        set -g prompt_host ""
        if set -q SSH_TTY
            or begin
                command -sq systemd-detect-virt
                and systemd-detect-virt -q
            end
            set prompt_host $usercolor$USER$normal@(set_color $fish_color_host)$hostname$normal":"
        end
    end

    # Private session indicator (fish -P / --private). ascii-safe, no unicode guard needed.
    set -l prompt_private
    test -n "$fish_private_mode"; and set prompt_private (set_color brmagenta)"[priv]"$normal" "

    # Shorten pwd if prompt is too long
    set -l pwd (prompt_pwd)

    echo -n -s $prompt_private $prompt_host $cwd $pwd $normal $prompt_status $delim
end
