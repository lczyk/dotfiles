# soft claim on the working tree for an agent harness: a json file in
# <root>/.agents/sessions/ (git toplevel, else $PWD) that other sessions check
# before touching the tree. nothing enforces it. the claim pid is the harness
# itself, b/c sh execs into it, so an interrupted session leaves a claim that
# reads as dead and gets pruned on the next launch.
#
# usage: __agent_run <harness> [VAR=value ...] <command> [args ...]
function __agent_run --argument-names harness
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    or set root $PWD
    set -l dir $root/.agents/sessions
    set -l live (__agent_claims $dir)
    if set -q live[1]
        printf 'agent: other sessions in %s\n' $root >&2
        printf '    %s\n' $live >&2
    end
    set -l branch (git branch --show-current 2>/dev/null)

    sh -c '
        dir=$1 root=$2 harness=$3 branch=$4
        shift 4
        claim="$dir/$harness-$$.json"
        if mkdir -p "$dir" 2>/dev/null && jq -n \
            --arg harness "$harness" --argjson pid $$ \
            --arg root "$root" --arg cwd "$PWD" --arg branch "$branch" \
            --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            "{harness: \$harness, pid: \$pid, root: \$root, cwd: \$cwd, branch: \$branch, started: \$started}" \
            >"$claim" 2>/dev/null; then
            export AGENT_CLAIM="$claim"
        else
            rm -f "$claim" 2>/dev/null
        fi
        exec env "$@"
    ' sh $dir $root $harness "$branch" $argv[2..]
    set -l st $status
    __agent_claims $dir >/dev/null
    return $st
end

# prune dead claims in a sessions dir and print the live ones, one per line.
function __agent_claims --argument-names dir
    for f in $dir/*.json
        set -l pid (jq -r '.pid // empty' $f 2>/dev/null)
        if test -n "$pid"; and ps -p $pid >/dev/null 2>&1
            jq -r '"\(.harness) pid \(.pid) on \(.branch // "-") since \(.started)"' $f
        else
            rm -f $f
        end
    end
end
