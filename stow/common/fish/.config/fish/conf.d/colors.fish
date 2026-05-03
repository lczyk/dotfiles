# custom palette: orange-tinted scheme. set only if unset so user tweaks
# via `fish_config` / `set -U` stick afterwards.

set -q fish_color_autosuggestion;        or set -U fish_color_autosuggestion FFC473
set -q fish_color_cancel;                or set -U fish_color_cancel --reverse
set -q fish_color_command;               or set -U fish_color_command FF9400
set -q fish_color_comment;               or set -U fish_color_comment A63100
set -q fish_color_cwd;                   or set -U fish_color_cwd green
set -q fish_color_cwd_root;              or set -U fish_color_cwd_root red
set -q fish_color_end;                   or set -U fish_color_end FF4C00
set -q fish_color_error;                 or set -U fish_color_error FFDD73
set -q fish_color_escape;                or set -U fish_color_escape 00a6b2
set -q fish_color_history_current;       or set -U fish_color_history_current --bold
set -q fish_color_host;                  or set -U fish_color_host normal
set -q fish_color_match;                 or set -U fish_color_match --background=brblue
set -q fish_color_normal;                or set -U fish_color_normal normal
set -q fish_color_operator;              or set -U fish_color_operator 00a6b2
set -q fish_color_param;                 or set -U fish_color_param FFC000
set -q fish_color_quote;                 or set -U fish_color_quote BF9C30
set -q fish_color_redirection;           or set -U fish_color_redirection BF5B30
set -q fish_color_search_match;          or set -U fish_color_search_match white --background=brblack
set -q fish_color_selection;             or set -U fish_color_selection white --bold --background=brblack
set -q fish_color_status;                or set -U fish_color_status red
set -q fish_color_user;                  or set -U fish_color_user brgreen
set -q fish_color_valid_path;            or set -U fish_color_valid_path --underline

set -q fish_pager_color_completion;      or set -U fish_pager_color_completion normal
set -q fish_pager_color_description;     or set -U fish_pager_color_description B3A06D
set -q fish_pager_color_prefix;          or set -U fish_pager_color_prefix normal --bold --underline
set -q fish_pager_color_progress;        or set -U fish_pager_color_progress brwhite --background=cyan
set -q fish_pager_color_selected_background; or set -U fish_pager_color_selected_background --background=brblack
