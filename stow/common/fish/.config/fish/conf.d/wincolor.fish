# per-directory alacritty window background tinting.
#
# `wincolor` toggles tinting on/off for the *current directory*. the choice is
# persisted per-dir in a state file, so any window sitting in that dir -- now or
# later, including a cmd+N child in the same cwd -- gets the same tint. nothing
# is passed between windows; the dir is the key.
#
# hierarchical: enabling a dir tints the whole subtree below it, all sharing the
# *same* colour (hashed from the enabled dir, not the cwd). when several enabled
# dirs are ancestors of the cwd, the closest (longest path) wins. so you can
# colour a project root and override a sub-area with its own colour.
#
# the tint reuses the deterministic hash the prompt uses (fish_prompt.fish):
# `<dir> | cksum` -> first 3 bytes as rgb, scaled down to a dark bg so it shares
# a hue with that dir's prompt cwd colour. off-state restores the file background.
#
# guarded on alacritty (ALACRITTY_WINDOW_ID per-window + the `alacritty` binary);
# no-op in any other terminal.

set -g __wincolor_root $XDG_STATE_HOME
test -n "$__wincolor_root"; or set -g __wincolor_root ~/.local/state
set -g __wincolor_root $__wincolor_root/wincolor
set -g __wincolor_state $__wincolor_root/dirs

# window registry: one file per live alacritty window, named by window-id,
# contents = that window's pwd. lets any session push the right tint to *every*
# window via `alacritty msg config -w <id>` -- no cross-session events needed,
# so a window blocked in a fullscreen app still gets retinted by whoever toggled.
set -g __wincolor_win $__wincolor_root/win

# dark bg hex for a given dir, sharing that dir's prompt hue.
function __wincolor_hex --argument dir
    set -l shas (echo $dir | cksum | string split -f1 ' ' | math --base=hex \
        | string sub -s 3 | string pad -c 0 -w 6 | string match -ra ..)
    set -l col
    for c in $shas[1..3]
        set col $col (math "floor(0x$c * 0.30)")
    end
    # min-brightness floor: keep tints clearly above the default 0x1c1c1c bg
    # (luminance ~28) so even near-black hashes read as a distinct colour.
    while test (math "0.2126 x $col[1] + 0.7152 x $col[2] + 0.0722 x $col[3]") -lt 34
        for i in 1 2 3
            set col[$i] (math "min(255, $col[$i] + 6)")
        end
    end
    set -l hex
    for c in $col
        set hex $hex (math --base=hex $c | string replace 0x '' | string pad -c 0 -w 2)
    end
    string join '' $hex
end

# is the current dir itself an enabled entry? (exact match, for toggling)
function __wincolor_on
    test -f $__wincolor_state; and grep -Fxq -- (pwd -P) $__wincolor_state
end

# closest enabled ancestor of the given dir (the dir itself counts). prints the
# dir and succeeds, or fails if no enabled dir covers it. longest path wins.
function __wincolor_match --argument p
    test -f $__wincolor_state; or return 1
    test -n "$p"; or set p (pwd -P)
    set -l best ''
    for d in (cat $__wincolor_state)
        test -n "$d"; or continue
        test "$p" = "$d"; or string match -q -- "$d/*" "$p"; or continue
        test (string length -- "$d") -gt (string length -- "$best"); and set best $d
    end
    test -n "$best"; or return 1
    echo $best
end

# record this window's pwd in the registry.
function __wincolor_register
    set -q ALACRITTY_WINDOW_ID; or return
    mkdir -p $__wincolor_win
    pwd -P >$__wincolor_win/$ALACRITTY_WINDOW_ID
end

# push the right tint to *every* registered window: each gets the colour of its
# own closest enabled ancestor, or a reset. driven by whoever toggled/cd'd, so
# blocked windows still update. dead-window ids just no-op (msg returns 0 either
# way -- no liveness signal -- so stale entries are harmless; fish_exit prunes).
function __wincolor_apply
    test -d $__wincolor_win; or return
    for f in $__wincolor_win/*
        test -f $f; or continue
        set -l id (basename $f)
        set -l d (__wincolor_match (cat $f))
        if test -n "$d"
            alacritty msg config -w $id "colors.primary.background='#"(__wincolor_hex $d)"'"
        else
            alacritty msg config -w $id --reset
        end
    end
end

# toggle tinting for the current dir, apply, and report in one line.
#
# __wincolor_apply pushes to every registered window directly (`msg -w <id>`),
# so the toggling session retints all affected windows itself -- including ones
# blocked in a fullscreen app that can't react on their own.
function wincolor --description 'toggle/list/prune alacritty background tints'
    switch "$argv[1]"
        case -h --help help
            echo 'wincolor -- per-directory alacritty background tint'
            echo
            echo 'usage:'
            echo '  wincolor          toggle tinting for the current dir on/off'
            echo '  wincolor list     list enabled dirs with their colour'
            echo '  wincolor prune    drop entries whose dir no longer exists'
            echo '  wincolor --help   show this help'
            echo
            echo 'enabling a dir tints its whole subtree; the closest enabled'
            echo 'ancestor wins. all windows in the subtree update on toggle.'
            return
        case list
            test -f $__wincolor_state; or return
            for d in (cat $__wincolor_state)
                test -n "$d"; or continue
                set -l mark ''
                test -d "$d"; or set mark ' (missing)'
                echo "#"(__wincolor_hex $d)" $d$mark"
            end
            return
        case prune
            test -f $__wincolor_state; or return
            set -l keep
            for d in (cat $__wincolor_state)
                test -d "$d"; and set keep $keep $d
            end
            printf '%s\n' $keep >$__wincolor_state
            # reap registry files for windows no longer alive. alacritty has no
            # window-list cmd, so derive liveness from process env: a live window
            # has procs carrying ALACRITTY_WINDOW_ID=<id>.
            set -l gone 0
            if test -d $__wincolor_win
                set -l live (ps eww -o command= 2>/dev/null \
                    | string match -gr 'ALACRITTY_WINDOW_ID=(\d+)' | sort -u)
                for f in $__wincolor_win/*
                    test -f $f; or continue
                    if not contains -- (basename $f) $live
                        rm -f $f
                        set gone (math $gone + 1)
                    end
                end
            end
            __wincolor_apply
            echo "wincolor: kept "(count $keep)" dir(s), reaped $gone window(s)"
            return
    end

    set -l dir (pwd -P)
    if __wincolor_on
        # drop the dir from state
        set -l keep (grep -Fxv -- $dir $__wincolor_state)
        printf '%s\n' $keep >$__wincolor_state
        echo "wincolor off -> $dir"
    else
        mkdir -p (dirname $__wincolor_state)
        echo $dir >>$__wincolor_state
        echo "wincolor on  -> $dir #"(__wincolor_hex $dir)
    end
    __wincolor_apply
end

if status is-interactive
    and set -q ALACRITTY_WINDOW_ID
    and command -sq alacritty
    __wincolor_register
    __wincolor_apply

    # cd: update this window's registry entry, then push to all windows.
    # forks `alacritty msg` per registered window; cheap, debounce if cd lag bites.
    function __wincolor_on_pwd --on-variable PWD
        __wincolor_register
        __wincolor_apply
    end

    # drop this window's registry entry on exit so stale ids don't accumulate.
    function __wincolor_on_exit --on-event fish_exit
        rm -f $__wincolor_win/$ALACRITTY_WINDOW_ID
    end
end
