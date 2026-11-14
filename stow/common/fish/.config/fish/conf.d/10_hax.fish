if type -q hax
    function hax --wraps hax
        __agent_run hax AGENT_SESSION=1 hax $argv
    end
end
