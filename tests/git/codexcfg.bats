#!/usr/bin/env bats

setup() {
    FILTER="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/filters/codexcfg-clean.sh"
}

filter_config() {
    bash "$FILTER"
}

@test "removes Codex machine-local tables" {
    run filter_config <<'EOF'
sandbox_mode = "workspace-write"
[projects."/repo"]
trust_level = "trusted"

[tui]
status_line = ["model"]

[tui.model_availability_nux]
"gpt-5.5" = 4

[hooks.state]
[hooks.state."/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:abc"

[feedback]
enabled = false
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *'sandbox_mode = "workspace-write"'* ]]
    [[ "$output" == *'[tui]'* ]]
    [[ "$output" == *'status_line = ["model"]'* ]]
    [[ "$output" == *'[feedback]'* ]]
    [[ "$output" != *'[projects.'* ]]
    [[ "$output" != *'[tui.model_availability_nux]'* ]]
    [[ "$output" != *'[hooks.state'* ]]
    [[ "$output" != *'trusted_hash'* ]]
}

@test "strips the top-level model pin" {
    run filter_config <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"

[tui]
status_line = ["model"]
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *'model = '* ]]
    [[ "$output" != *'model_reasoning_effort'* ]]
    [[ "$output" == *'sandbox_mode = "workspace-write"'* ]]
    [[ "$output" == *'[tui]'* ]]
}

@test "keeps model keys inside named tables" {
    run filter_config <<'EOF'
model = "gpt-5.6-sol"

[profiles.review]
model = "gpt-5.5"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *'[profiles.review]'* ]]
    [[ "$output" == *'model = "gpt-5.5"'* ]]
    [[ "$output" != *'gpt-5.6-sol'* ]]
}

@test "no leading blank when first tables are stripped" {
    run filter_config <<'EOF'
model = "gpt-5.6-sol"
[projects."/repo"]
trust_level = "trusted"

[tui]
status_line = ["model"]
EOF

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[tui]" ]
}

@test "preserves similarly named keys outside transient tables" {
    run filter_config <<'EOF'
[custom]
projects = "keep"
hooks_state = "keep"
tui_model_availability_nux = "keep"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *'projects = "keep"'* ]]
    [[ "$output" == *'hooks_state = "keep"'* ]]
    [[ "$output" == *'tui_model_availability_nux = "keep"'* ]]
}

@test "is idempotent" {
    input=$'model = "gpt-5.6-sol"\n\n[tui]\nstatus_line = ["model"]'
    once=$(printf '%s\n' "$input" | filter_config)
    twice=$(printf '%s\n' "$once" | filter_config)

    [ "$once" = "$twice" ]
}
