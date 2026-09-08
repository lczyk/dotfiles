# in a private fish session (`fish -P`) run claude with local persistence and
# nonessential upstream traffic off. see `claude --help` for what --bare would
# add; not used here because it also drops hooks.
if type -q claude
    function claude --wraps claude
        if set -q fish_private_mode
            env CLAUDE_CODE_SKIP_PROMPT_HISTORY=1 \
                CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
                DISABLE_TELEMETRY=1 \
                DISABLE_ERROR_REPORTING=1 \
                DO_NOT_TRACK=1 \
                command claude $argv
        else
            command claude $argv
        end
    end
end
