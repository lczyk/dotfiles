if type -q copilot
    function copilot --wraps copilot
        __agent_run copilot copilot $argv
    end
end
