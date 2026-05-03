# Change greeting
source ~/.config/fish/logo.fish

function fish_greeting
    if not type -q fish
        echo "fish not in PATH"
        echo "SHELL: $SHELL"
        # check SHELL is fish
        if string match -q -r fish $SHELL
            $SHELL -v
        end
    else
        fish -v
    end
    logo
    echo "Hello $USER :))"
end

set -x SCREENSHOT_DIR "$HOME/screenshots"
set -x GCM_CREDENTIAL_STORE gpg
