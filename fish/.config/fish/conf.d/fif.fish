# using ripgrep combined with preview
# find-in-file - usage: fif <searchTerm>
# fif() {
#   if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
#   rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
# }

function fif
    set -q searchTerm $argv[1]
    echo $argv
    if not set searchTerm
        echo "Need a string to search for!"
        return 1
    end

    rg --files-with-matches --no-messages $searchTerm | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$searchTerm' || rg --ignore-case --pretty --context 10 '$searchTerm' {}"
end