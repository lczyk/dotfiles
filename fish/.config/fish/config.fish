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
if test -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
    export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
end
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
    set -x _EZA 'eza --group-directories-first --long --git --almost-all --show-symlinks --color=always --time-style=long-iso' 
    alias ls=$_EZA
    alias ls1="$_EZA -T -L1"
    alias ls2="$_EZA -T -L2"
    alias ls3="$_EZA -T -L3"
end

alias gc3="grep -C3 --"

# set up fzf if installed
if type -q fzf
    # TODO: fzf shell integration does not work in onlder versions of fzf
    # see: https://github.com/junegunn/fzf?tab=readme-ov-file#installation
    fzf --fish 2>/dev/null | source
    export FZF_DEFAULT_OPTS='--multi --exact --cycle --height 40% --layout reverse --border top'
end

if type -q nvim
    # for editing a file with sudo, but with the current user's setup
    alias sunvim='sudo -E nvim -n'
    alias vim='nvim'
    alias vi='nvim'
end
# export JAVA_HOME=$(/usr/libexec/java_home)
# export GRAALVM_HOME=/Library/Java/JavaVirtualMachines/graalvm-23.jdk/Contents/Home/
