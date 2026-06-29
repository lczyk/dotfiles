# per-directory alacritty window background tinting.
#
# `wincolor` toggles tinting on/off for the *current directory*. the choice is
# stored per-dir in a state file, so any *live* window sitting in that dir --
# including a cmd+N child in the same cwd -- gets the same tint. nothing is
# passed between windows; the dir is the key.
#
# tints are ephemeral, not durable opt-in: gc drops an enabled dir once no live
# window sits under it (see __wincolor_gc), so closing the last window in a
# tinted subtree forgets the tint. re-enable when you come back.
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

# abbreviate $HOME -> ~ for display only (state file keeps absolute paths).
function __wincolor_tilde --argument p
    string replace -- $HOME '~' $p
end

# raw dark-bg rgb triple ("r g b") for a dir at a given hash seed. seed feeds
# the hash so a colliding colour can be re-rolled (see __wincolor_seed).
function __wincolor_rgb --argument dir seed
    set -l shas (echo "$dir:$seed" | cksum | string split -f1 ' ' | math --base=hex \
        | string sub -s 3 | string pad -c 0 -w 6 | string match -ra ..)
    set -l col
    for c in $shas[1..3]
        set col $col (math "floor(0x$c * 0.45)")
    end
    # min-brightness floor: keep tints clearly above the default 0x1c1c1c bg
    # (luminance ~28) so even near-black hashes read as a distinct colour.
    # floor sits well above default so low hashes don't blend into the bg.
    while test (math "0.2126 x $col[1] + 0.7152 x $col[2] + 0.0722 x $col[3]") -lt 50
        for i in 1 2 3
            set col[$i] (math "min(255, $col[$i] + 6)")
        end
    end
    # hue floor: base bg is neutral grey, so a near-grey tint (channels ~equal)
    # reads as the same hue, just brighter. force a channel gap by pushing the
    # largest channel up until max-min spread is clear. scaled vals top out ~115
    # (0.45 x 255), so plenty of headroom -- no 255 clamp loop risk.
    set -l mn (math "min($col[1],$col[2],$col[3])")
    set -l mx (math "max($col[1],$col[2],$col[3])")
    while test (math "$mx - $mn") -lt 24
        for i in 1 2 3
            test $col[$i] -eq $mx; and set col[$i] (math "$col[$i] + 4"); and break
        end
        set mx (math "$mx + 4")
    end
    printf '%s\n' $col
end

# redmean rgb distance -- cheap perceptual approximation, no Lab/cksum gymnastics
# needed. args: r1 g1 b1 r2 g2 b2 -> floored int distance.
function __wincolor_dist
    set -l rb (math "($argv[1] + $argv[4]) / 2")
    set -l dr (math "$argv[1] - $argv[4]")
    set -l dg (math "$argv[2] - $argv[5]")
    set -l db (math "$argv[3] - $argv[6]")
    math "floor(sqrt((2 + $rb/256)*$dr^2 + 4*$dg^2 + (2 + (255-$rb)/256)*$db^2))"
end

# resolve the hash seed for a dir given the whole enabled set. greedy in state
# file order: each dir takes the lowest seed whose colour stays >= threshold from
# every earlier dir's resolved colour. deterministic from the file, so list and
# apply agree. NOTE: O(n^2) over enabled dirs; n is a handful, not worth caching.
function __wincolor_seed --argument dir
    set -l thresh 60   # min redmean distance between any two tints
    # NOTE: the dark gamut (0.45 scale) only fits ~12-15 distinct tints at this
    # threshold; past that a re-roll exhausts cap and two tints end up similar.
    # fine for typical use (a handful of live tinted dirs). to pack more: lower
    # thresh (less distinct) or raise the 0.45 scale (brighter bg). bumping cap
    # barely helps -- the space is full, not under-sampled.
    set -l cap 50      # seed attempts before giving up (keep last try)
    set -l prev
    for d in (cat $__wincolor_state)
        test -n "$d"; or continue
        set -l s 0
        while test $s -lt $cap
            set -l rgb (__wincolor_rgb $d $s)
            set -l ok 1
            for p in $prev
                set -l q (string split ' ' $p)
                test (__wincolor_dist $rgb[1] $rgb[2] $rgb[3] $q[1] $q[2] $q[3]) -lt $thresh
                and set ok 0
                and break
            end
            test $ok -eq 1; and break
            set s (math $s + 1)
        end
        test "$d" = "$dir"; and echo $s; and return
        set prev $prev (string join ' ' (__wincolor_rgb $d $s))
    end
    echo 0   # dir not in state file: fall back to seed 0
end

# dark bg hex for a dir, with collision-avoiding seed. pass an already-resolved
# seed as $argv[2] to skip the lookup (list does, having the seed in hand).
function __wincolor_hex --argument dir seed
    test -n "$seed"; or set seed (__wincolor_seed $dir)
    set -l hex
    for c in (__wincolor_rgb $dir $seed)
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

# record this window's pwd in the registry. tty-less shells (scripts) noop --
# only a real window/shell can hold a tint.
function __wincolor_register
    set -q ALACRITTY_WINDOW_ID; or return
    isatty stdout; or return
    mkdir -p $__wincolor_win
    pwd -P >$__wincolor_win/$ALACRITTY_WINDOW_ID
end

# garbage-collect stale state. order matters: reap dead windows first so the
# window-less-dir purge sees an accurate live set, then drop enabled dirs no
# live window sits under, then drop dirs that no longer exist on disk.
function __wincolor_gc
    # reap registry files for dead windows. alacritty has no window-list cmd,
    # so derive liveness from process env: a live window has procs carrying
    # ALACRITTY_WINDOW_ID=<id>.
    set -g __wincolor_reaped 0
    if test -d $__wincolor_win
        set -l live (ps eww -o command= 2>/dev/null \
            | string match -gr 'ALACRITTY_WINDOW_ID=(\d+)' | sort -u)
        for f in $__wincolor_win/*
            test -f $f; or continue
            if not contains -- (basename $f) $live
                rm -f $f
                set __wincolor_reaped (math $__wincolor_reaped + 1)
            end
        end
    end

    test -f $__wincolor_state; or return
    set -l live_pwds (cat $__wincolor_win/* 2>/dev/null)
    set -l keep
    for d in (cat $__wincolor_state)
        test -n "$d"; or continue
        test -d "$d"; or continue          # dir gone -> drop
        for p in $live_pwds                 # keep iff some live window is under it
            test "$p" = "$d"; or string match -q -- "$d/*" "$p"; or continue
            set keep $keep $d
            break
        end
    end
    printf '%s\n' $keep >$__wincolor_state
    set -g __wincolor_kept (count $keep)
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
        # dead windows make `alacritty msg` write BrokenPipe to stderr; swallow it
        # (fish_exit prunes stale ids, but cd can race a just-closed window).
        if test -n "$d"
            alacritty msg config -w $id "colors.primary.background='#"(__wincolor_hex $d)"'" 2>/dev/null
        else
            alacritty msg config -w $id --reset 2>/dev/null
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
            echo '  wincolor on       turn on (noop if already on)'
            echo '  wincolor off      turn off the current dir'
            echo '  wincolor off -f   turn off the closest enabled ancestor too'
            echo '  wincolor list     list enabled dirs with their colour'
            echo '  wincolor prune    gc stale state (same gc every call runs)'
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
                set -l seed (__wincolor_seed $d)
                echo "#"(__wincolor_hex $d $seed)"($seed) "(__wincolor_tilde $d)"$mark"
            end
            return
        case prune
            __wincolor_gc
            __wincolor_apply
            echo "wincolor: kept $__wincolor_kept dir(s), reaped $__wincolor_reaped window(s)"
            return
    end

    # resolve action: bare toggles, `on`/`off` force a direction (idempotent).
    set -l action toggle
    set -l force
    switch "$argv[1]"
        case on
            set action on
        case off
            set action off
            contains -- "$argv[2]" -f --force; and set force 1
    end

    # every invocation gc's stale windows + window-less dirs first.
    __wincolor_gc
    set -l dir (pwd -P)

    test "$action" = toggle; and begin
        __wincolor_on; and set action off; or set action on
    end

    if test "$action" = off
        # -f/--force drops the closest enabled ancestor too (works from a subdir);
        # plain off only removes an exact entry for the current dir.
        set -l target $dir
        test -n "$force"; and set target (__wincolor_match $dir)
        if test -z "$target"; or not grep -Fxq -- $target $__wincolor_state 2>/dev/null
            echo "wincolor: nothing to turn off here"
            return
        end
        set -l keep (grep -Fxv -- $target $__wincolor_state)
        printf '%s\n' $keep >$__wincolor_state
        echo "wincolor off -> "(__wincolor_tilde $target)
    else
        if __wincolor_on
            echo "wincolor already on -> "(__wincolor_tilde $dir)
            return
        end
        # already tinted by an enabled ancestor -> noop, the subtree shares its colour
        set -l parent (__wincolor_match $dir)
        if test -n "$parent"
            echo "wincolor already on in parent: "(__wincolor_tilde $parent)
            return
        end
        mkdir -p (dirname $__wincolor_state)
        echo $dir >>$__wincolor_state
        echo "wincolor on  -> "(__wincolor_tilde $dir)" #"(__wincolor_hex $dir)
    end
    __wincolor_apply
end

if status is-interactive
    and set -q ALACRITTY_WINDOW_ID
    and isatty stdout
    and command -sq alacritty
    __wincolor_register
    __wincolor_apply

    # cd: update this window's registry entry, then push to all windows.
    # forks `alacritty msg` per registered window; cheap, debounce if cd lag bites.
    function __wincolor_on_pwd --on-variable PWD
        __wincolor_register
        __wincolor_apply
    end

    # drop this window's registry entry on exit, then gc + retint the rest: a
    # closed window may have been the last one under an enabled dir.
    function __wincolor_on_exit --on-event fish_exit
        rm -f $__wincolor_win/$ALACRITTY_WINDOW_ID
        __wincolor_gc
        __wincolor_apply
    end
end
