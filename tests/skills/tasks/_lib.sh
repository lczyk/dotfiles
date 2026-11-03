# shellcheck shell=sh
# shared helpers for the task scripts. not a task itself (no exec bit, no
# shebang) -- sourced by each prepare_<id>.sh and collect.sh via
# `. "$(dirname "$0")/_lib.sh"`. pats sets PATS_AGENT_HOME (the agent's
# sandbox HOME), PATS_WORKDIR (its cwd) and PATS_OUTPUT_DIR.

_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_STOW="${_ROOT}/stow/common"
_PACKAGES="claude agent-hooks agent-styles agent-guidance agent-skills git"
# expands in the sandbox, when the hook runs.
# shellcheck disable=SC2016
_CANARY_DIR='$HOME/.pats-canary'

_fail() {
    printf '%s: %s\n' "$(basename "$0")" "$1" >&2
    exit 1
}

# tracked files only, so machine-local and runtime state in the stow tree
# stays out. -L because stow links don't resolve inside the sandbox.
_seed_package() {
    pkg="$1"
    git -C "${_ROOT}" ls-files "stow/common/${pkg}" | while IFS= read -r path; do
        rel="${path#stow/common/"${pkg}"/}"
        mkdir -p "${PATS_AGENT_HOME}/$(dirname "${rel}")"
        cp -RL "${_STOW}/${pkg}/${rel}" "${PATS_AGENT_HOME}/${rel}"
    done
}

_canary_hook() {
    printf 'mkdir -p "%s" && touch "%s/%s"' "${_CANARY_DIR}" "${_CANARY_DIR}" "$1"
}

# drop host-only settings, turn off commit signing (no key in the sandbox) and
# append one marker hook per event, so the canary can tell the hooks fired.
_patch_settings() {
    settings="${PATS_AGENT_HOME}/.claude/settings.json"
    tmp=$(mktemp)
    jq \
        --arg start "$(_canary_hook session-start)" \
        --arg prompt "$(_canary_hook user-prompt-submit)" \
        --arg tool "$(_canary_hook pre-tool-use)" \
        'del(.model, .statusLine, .enabledPlugins, .extraKnownMarketplaces, .voice, .voiceEnabled, .agentPushNotifEnabled)
        | .env += {GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "commit.gpgsign", GIT_CONFIG_VALUE_0: "false"}
        | .hooks.SessionStart += [{hooks: [{type: "command", command: $start}]}]
        | .hooks.UserPromptSubmit += [{hooks: [{type: "command", command: $prompt}]}]
        | .hooks.PreToolUse += [{matcher: "Bash", hooks: [{type: "command", command: $tool}]}]' \
        "${settings}" >"${tmp}"
    mv "${tmp}" "${settings}"
}

# the styles the agent starts with. $1 lofi on|off (the skill's marker file),
# $2 the caveman default mode the caveman hooks read (off|lite|full|ultra).
_styles() {
    state="${PATS_AGENT_HOME}/.config/agent-state"
    modes="${PATS_AGENT_HOME}/.config/agent-modes"
    mkdir -p "${state}" "${modes}"
    printf '{"defaultMode": "%s"}\n' "$2" >"${modes}/caveman.json"
    if [ "$1" = off ]; then
        touch "${state}/lofi-off"
    else
        rm -f "${state}/lofi-off"
    fi
}

# the agent's HOME gets this repo's agent config, the way stow lays it out.
# styles follow the task id's suite prefix -- lofi alone, caveman alone, or
# both. a task that needs other starting state calls _styles again after.
# SKILLS_OVERLAY (host env) names a dir of text to append, see _overlay.
_seed_home() {
    [ -n "${PATS_AGENT_HOME}" ] || _fail "PATS_AGENT_HOME unset (needs pats >= 0.7.3)"
    command -v jq >/dev/null || _fail "jq not found"
    for pkg in ${_PACKAGES}; do
        _seed_package "${pkg}"
    done
    _patch_settings
    case "${PATS_TASK_ID}" in
        lofi-cave-*) _styles on full ;;
        cave-*) _styles off full ;;
        *) _styles on off ;;
    esac
    if [ -n "${SKILLS_OVERLAY:-}" ]; then
        _overlay "${SKILLS_OVERLAY}"
    fi
}

# append each file under dir $1 to the seeded file at the same path under the
# agent's HOME, to try out style / skill wording without touching the stow tree.
_overlay() {
    [ -d "$1" ] || _fail "SKILLS_OVERLAY: no such dir: $1"
    (cd "$1" && find . -type f) | while IFS= read -r rel; do
        dst="${PATS_AGENT_HOME}/${rel#./}"
        [ -f "${dst}" ] || _fail "SKILLS_OVERLAY: ${rel#./} isn't a seeded file"
        cat "$1/${rel}" >>"${dst}"
    done || exit 1
}

# lines the reply may quote in their source case (repo template headers), one
# per line. the lofi prose scorers skip them.
_verbatim() {
    printf '%s\n' "$@" >>"${PATS_OUTPUT_DIR}/verbatim.txt"
}

# git as the sandbox runs it: the seeded config and git hooks, no signing. the
# env override beats the config's gpgsign line, which an included config.local
# can't since the include comes first.
_git() {
    env HOME="${PATS_AGENT_HOME}" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
        git -C "${PATS_WORKDIR}" "$@"
}

# copy a cases/ dir's contents into the workdir, over whatever is there.
_lay() {
    cp -R "$(dirname "$0")/../cases/$1/." "${PATS_WORKDIR}/"
}

# HEAD as the point collect diffs the agent's work against. call again after
# any fixture commits made past _init_repo.
_mark_seed() {
    _git rev-parse HEAD >"${PATS_OUTPUT_DIR}/seed.sha"
}

# commit whatever the task laid down in the workdir as the fixture's base.
# pats stages prompt.txt into the workdir after prepare, so it's excluded up
# front to keep it out of the agent's git status and the collected diff.
_init_repo() {
    _git init -q
    printf 'prompt.txt\n' >>"${PATS_WORKDIR}/.git/info/exclude"
    _git add -A
    _git commit -q -m "chore: seed fixture"
    _mark_seed
}
