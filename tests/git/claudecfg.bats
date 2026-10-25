#!/usr/bin/env bats

setup() {
    CONFIG="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/config"
    FILTER=$(git config -f "$CONFIG" filter.claudecfg.clean)
}

filter_config() {
    bash -c "$FILTER"
}

@test "removes claude machine-local settings and preserves stable preferences" {
    run filter_config <<'EOF'
{
  "effortLevel": "high",
  "model": "claude-opus-5",
  "skipWorkflowUsageWarning": true,
  "theme": "dark-ansi",
  "tui": "fullscreen",
  "voice": {"enabled": true, "mode": "hold"},
  "voiceEnabled": true,
  "agentPushNotifEnabled": true,
  "switchModelsOnFlag": false,
  "modelSettings": {
    "claude-fable-5-1": {"effortLevel": "high"},
    "claude-haiku-5-5": {"effortLevel": "medium", "maxEffortLevel": "medium"},
    "claude-opus-5": {"effortLevel": "low", "maxEffortLevel": "low"}
  }
}
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *'"effortLevel": "high"'* ]]
    [[ "$output" != *'"model": "claude-opus-5"'* ]]
    [[ "$output" != *'"skipWorkflowUsageWarning"'* ]]
    [[ "$output" != *'"theme"'* ]]
    [[ "$output" != *'"tui"'* ]]
    [[ "$output" != *'"voice"'* ]]
    [[ "$output" != *'"voiceEnabled"'* ]]
    [[ "$output" == *'"agentPushNotifEnabled": true'* ]]
    [[ "$output" == *'"switchModelsOnFlag": false'* ]]
    [[ "$output" != *'"claude-fable-5-1"'* ]]
    [[ "$output" == *'"claude-haiku-5-5": {'* ]]
    [[ "$output" == *'"effortLevel": "medium"'* ]]
    [[ "$output" == *'"maxEffortLevel": "medium"'* ]]
    [[ "$output" == *'"claude-opus-5": {'* ]]
    [[ "$output" != *'"effortLevel": "low"'* ]]
    [[ "$output" == *'"maxEffortLevel": "low"'* ]]
}

@test "is idempotent" {
    input=$'{"voice":{"enabled":true},"agentPushNotifEnabled":true}'
    once=$(printf '%s\n' "$input" | filter_config)
    twice=$(printf '%s\n' "$once" | filter_config)

    [ "$once" = "$twice" ]
}
