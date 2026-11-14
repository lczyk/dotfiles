if type -q opencode
    function opencode --wraps opencode
        __agent_run opencode opencode $argv
    end
end
