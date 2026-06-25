# mac-only: homebrew installs pass completions to vendor_completions.d, which
# fish doesn't autoload for some setups. source it directly if present.
set -l pass_comp /opt/homebrew/share/fish/vendor_completions.d/pass.fish
if test -f $pass_comp
    source $pass_comp
end
