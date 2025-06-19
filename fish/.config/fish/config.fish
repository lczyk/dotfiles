# Change greeting
source ~/.config/fish/logo.fish

function fish_greeting
    if not type -q fish
        echo "fish not in PATH"
        echo "SHELL: $SHELL"
        # check SHELL is fish
        if string match -q -r 'fish' $SHELL
            $SHELL -v
        end
    else
        fish -v
    end
    logo
    echo 'Hello Marcin! :)'
end

# Add stuff to path
# export PATH="$HOME/.poetry/bin:$PATH"
export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
# export PATH="/usr/local/optx/ruby/bin:$PATH"
# export PATH="/usr/local/lib/ruby/gems/2.7.0/bin:$PATH"
# export PATH="/usr/local/Cellar/openjdk/15.0.2/bin:$PATH"
# export PATH="/usr/local/bin:$PATH"
# export PATH="$HOME/.local/bin:$PATH"

# if /opt/homebrew/opt/make/libexec/gnubin exists, add it to PATH
if test -d /opt/homebrew/opt/make/libexec/gnubin
    export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
end

set -x SCREENSHOT_DIR "$HOME/screenshots"

if type -q brew
    set -x HOMEBREW_NO_ENV_HINTS 1
end

# check if eza is installed
if type -q eza
    alias ls='eza --group-directories-first --long --git --almost-all --show-symlinks --color=always --time-style=long-iso'
end

# set up fzf if installed
if type -q fzf
    fzf --fish | source
    export FZF_DEFAULT_OPTS='--multi --exact --cycle --height 40% --layout reverse --border top'
end

# export JAVA_HOME=$(/usr/libexec/java_home)
# export GRAALVM_HOME=/Library/Java/JavaVirtualMachines/graalvm-23.jdk/Contents/Home/
