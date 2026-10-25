fish_add_path -g --path "$HOME/.kimi-code/bin"

if type -q kimi
    alias kimi='env AGENT_SESSION=1 kimi'
end
