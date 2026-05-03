# x1-only: add ruby gem bin dirs under ~/.local/share/gem/ruby/*/bin to PATH.
for dir in (find $HOME/.local/share/gem/ruby -maxdepth 2 -type d -name bin 2>/dev/null)
    if not contains -- $dir $PATH
        set -gx PATH $dir $PATH
    end
end
