# drop recursive-force `rm` invocations from shell history. the match logic
# lives in ../scrub-rm-rf.sh (a bash predicate) so it can be unit-tested via
# bats -- see tests/fish/scrub-history.bats. one cheap bash call per command.
#
# to scrub pre-existing history with the same rule, run once:
#   for c in (history); $__fish_config_dir/scrub-rm-rf.sh $c; and history delete --exact --case-sensitive -- $c; end
function _scrub_rm_rf --on-event fish_postexec
    $__fish_config_dir/scrub-rm-rf.sh $argv[1]
    or return
    history delete --exact --case-sensitive -- $argv[1]
end
