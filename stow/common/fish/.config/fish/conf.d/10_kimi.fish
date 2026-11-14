fish_add_path -g --path "$HOME/.kimi-code/bin"

if type -q kimi
    function kimi --wraps kimi
        __agent_run kimi AGENT_SESSION=1 kimi $argv
    end
end
