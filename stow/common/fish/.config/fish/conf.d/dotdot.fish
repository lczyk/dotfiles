function _dotdot_expand
    set -l dots (string length -- $argv[1])
    set -l parts (string repeat --count (math $dots - 1) -- "..;")
    echo -- (string trim --right --chars=\; -- $parts)
end

abbr --add dotdot --regex '\.{3,}' --function _dotdot_expand --position command
