
begin
    set -l pnpm_home "$HOME/.local/share/pnpm"

    if test -d $pnpm_home
        set -gx PNPM_HOME $pnpm_home

        # Add once (Fish treats $PATH as a list).
        if not contains -- $PNPM_HOME $PATH
            set -gx PATH $PNPM_HOME $PATH
        end
    end
end
