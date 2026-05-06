# drop standalone `rm -rf` invocations from history.
# kept iff the command contains a pipe `|` or `;` chain -- in those cases the
# rm is part of a larger pipeline worth keeping a record of.
#
# to scrub pre-existing history with the same rule, run once:
#   for c in (history); string match -qr 'rm\s+-(rf|fr)\b' -- $c; and not string match -qr '[|;&]' -- $c; and history delete --exact -- $c; end
function _scrub_rm_rf --on-event fish_postexec
    set -l cmd $argv[1]
    string match -qr 'rm\s+-(rf|fr)\b' -- $cmd
    or return
    if string match -qr '[|;&]' -- $cmd
        return
    end
    history delete --exact -- $cmd
end
