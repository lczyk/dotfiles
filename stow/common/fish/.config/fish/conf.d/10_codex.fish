if type -q codex
    function codex --wraps codex
        __agent_run codex codex $argv
    end
end
