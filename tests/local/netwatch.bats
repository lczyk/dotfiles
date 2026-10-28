#!/usr/bin/env bats
# tests for stow/x1/local/.local/bin/netwatch. ping, ip, nmcli and notify-send
# are shims: ip prints ROUTES (or ROUTES.<n> for its n-th call), ping pops one
# "loss rtt" line per call from $PINGS/<dev> (the last line sticks), nmcli
# answers the device listing from NMDEV and otherwise logs its argv and
# rewrites the device's metric in ROUTES the way NetworkManager would, and
# notify-send logs to NOTIFY.

setup() {
    NETWATCH="$BATS_TEST_DIRNAME/../../stow/x1/local/.local/bin/netwatch"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    export LOG="$BATS_TEST_TMPDIR/nmcli.log"
    export NOTIFY="$BATS_TEST_TMPDIR/notify.log"
    export ROUTES="$BATS_TEST_TMPDIR/routes"
    export NMDEV="$BATS_TEST_TMPDIR/nmdev"
    export PINGS="$BATS_TEST_TMPDIR/pings"
    mkdir -p "$SHIMDIR" "$PINGS"
    cat > "$SHIMDIR/ip" <<'SHIM'
#!/usr/bin/env bash
n=$(( $(cat "$ROUTES.n" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$ROUTES.n"
if [ -f "$ROUTES.$n" ]; then cat "$ROUTES.$n"; else cat "$ROUTES"; fi
SHIM
    cat > "$SHIMDIR/ping" <<'SHIM'
#!/usr/bin/env bash
dev=$2
f="$PINGS/$dev"
read -r loss rtt < "$f"
[ "$(wc -l < "$f")" -gt 1 ] && sed -i 1d "$f"
case $loss in (0|100) pct=$loss ;; (*) pct="$loss.3333" ;; esac
printf '3 packets transmitted, %s received, %s%% packet loss, time 600ms\n' $((3 - 3 * loss / 100)) "$pct"
if [ "$loss" -lt 100 ]; then
    printf 'rtt min/avg/max/mdev = %s/%s/%s/0.1 ms\n' "$rtt" "$rtt" "$rtt"
    exit 0
fi
exit 1
SHIM
    cat > "$SHIMDIR/nmcli" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = -t ]; then cat "$NMDEV"; exit 0; fi
printf '%s\n' "$*" >> "$LOG"
dev=$3 metric=$5
sed -i "s/^\(default .* dev $dev .*metric \)[0-9]*/\1$metric/" "$ROUTES"
SHIM
    cat > "$SHIMDIR/notify-send" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY"
SHIM
    chmod +x "$SHIMDIR"/*
    export PATH="$SHIMDIR:$PATH"
    export NETWATCH_INTERVAL=0
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
    routes 600 750
    wifi office
    pings wlan "0 60"
    pings bt "0 400"
}

routes() {
    printf 'default via 10.0.0.1 dev wlan proto dhcp src 10.0.0.2 metric %s\n' "$1" > "$ROUTES"
    [ -n "${2:-}" ] && printf 'default via 10.1.0.1 dev bt proto dhcp src 10.1.0.2 metric %s\n' "$2" >> "$ROUTES"
    return 0
}

wifi() { printf 'wifi:%s\nbt:phone\nloopback:lo\n' "$1" > "$NMDEV"; }

# pings <dev> <"loss rtt">... -- one line per upcoming call, last one sticks
pings() {
    local dev=$1; shift
    printf '%s\n' "$@" > "$PINGS/$dev"
}

metric_of() { grep "dev $1 " "$ROUTES" | sed 's/.*metric //'; }

@test "healthy primary is left alone" {
    run "$NETWATCH" --rounds 5
    [ "$status" -eq 0 ]
    [ ! -e "$LOG" ]
    [ ! -e "$NOTIFY" ]
    [ "$(metric_of wlan)" = 600 ]
}

@test "every probe of the primary lands in the state file" {
    run "$NETWATCH" --rounds 1
    [ "$(cat "$BATS_TEST_TMPDIR/netwatch")" = "wlan 0 60 ok" ]
    pings wlan "100 0"
    run "$NETWATCH" --rounds 1
    [ "$(cat "$BATS_TEST_TMPDIR/netwatch")" = "wlan 100 0 bad" ]
    [ ! -e "$BATS_TEST_TMPDIR/netwatch.tmp" ]
}

@test "one bad round is not enough" {
    pings wlan "100 0" "0 60"
    run "$NETWATCH" --rounds 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"wlan bad (100% loss, 0ms) 1/2"* ]]
    [ ! -e "$LOG" ]
}

@test "two bad rounds with a healthy backup demote the primary" {
    pings wlan "100 0" "66 2000" "0 60"
    run "$NETWATCH" --rounds 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"demoted wlan to metric 800, bt (400ms) now primary"* ]]
    [ "$(cat "$LOG")" = 'device modify wlan ipv4.route-metric 800 ipv6.route-metric 800' ]
    [ "$(metric_of wlan)" = 800 ]
    [ "$(cat "$NOTIFY")" = '-a netwatch demoted wlan to metric 800, bt (400ms) now primary ' ]
}

@test "high latency alone counts as bad" {
    pings wlan "0 1600"
    run "$NETWATCH" --rounds 2
    [[ "$output" == *"wlan bad (0% loss, 1600ms) 2/2"* ]]
    [ "$(metric_of wlan)" = 800 ]
}

@test "a dead backup means staying put" {
    pings wlan "100 0"
    pings bt "100 0"
    run "$NETWATCH" --rounds 4
    [ "$status" -eq 0 ]
    [[ "$output" == *"bt also bad (100% loss, 0ms), staying put"* ]]
    [ ! -e "$LOG" ]
    [ "$(metric_of wlan)" = 600 ]
}

@test "a good round resets the bad streak" {
    pings wlan "100 0" "0 60" "100 0" "0 60"
    run "$NETWATCH" --rounds 4
    [ ! -e "$LOG" ]
    [[ "$output" != *"2/2"* ]]
}

@test "three good rounds restore the original metric" {
    pings wlan "100 0" "100 0" "0 60"
    run "$NETWATCH" --rounds 4
    [ "$(metric_of wlan)" = 800 ]
    [[ "$output" == *"wlan ok (0% loss, 60ms) 2/3"* ]]
    [[ "$output" != *"restored"* ]]
    routes 600 750
    pings wlan "100 0" "100 0" "0 60"
    run "$NETWATCH" --rounds 5
    [[ "$output" == *"restored wlan to metric 600"* ]]
    [ "$(metric_of wlan)" = 600 ]
    [ "$(sed -n '$p' "$LOG")" = 'device modify wlan ipv4.route-metric 600 ipv6.route-metric 600' ]
    [ "$(sed -n '$p' "$NOTIFY")" = '-a netwatch restored wlan to metric 600 0% loss, 60ms' ]
}

@test "the uplink change itself is reported once each way" {
    pings wlan "100 0" "100 0" "0 60"
    run "$NETWATCH" --rounds 6
    [ "$(grep -c 'uplink:' "$NOTIFY")" -eq 2 ]
    [[ "$output" == *"uplink: wlan -> bt"* ]]
    [[ "$output" == *"uplink: bt -> wlan"* ]]
}

@test "a bad round while demoted resets the good streak" {
    pings wlan "100 0" "100 0" "0 60" "0 60" "100 0" "0 60"
    run "$NETWATCH" --rounds 7
    [[ "$output" != *"restored"* ]]
    [ "$(metric_of wlan)" = 800 ]
}

@test "a backup appearing or vanishing is reported" {
    routes 600
    printf 'default via 10.0.0.1 dev wlan proto dhcp src 10.0.0.2 metric 600\ndefault via 10.1.0.1 dev bt proto dhcp src 10.1.0.2 metric 750\n' > "$ROUTES.2"
    run "$NETWATCH" --rounds 4
    [ "$(cat "$NOTIFY")" = "$(printf -- '-a netwatch backup: none -> bt \n-a netwatch backup: bt -> none ')" ]
}

@test "fractional packet loss parses as its integer part" {
    pings wlan "33 60" "66 60"
    run "$NETWATCH" --rounds 2
    [[ "$output" == *"wlan bad (66% loss, 60ms) 1/2"* ]]
    [[ "$output" != *"33% loss"* ]]
    [ ! -e "$LOG" ]
}

@test "a demoted device that reconnects is forgotten" {
    pings wlan "100 0" "100 0"
    printf 'default via 10.1.0.1 dev bt proto dhcp src 10.1.0.2 metric 750\n' > "$ROUTES.3"
    run "$NETWATCH" --rounds 4
    [[ "$output" == *"wlan gone, forgetting demotion"* ]]
    [ "$(wc -l < "$LOG")" -eq 1 ]
    [[ "$output" == *"uplink: wlan -> bt"* ]]
}

@test "a wifi switch by someone else is reported" {
    run "$NETWATCH" --rounds 1
    [ ! -e "$NOTIFY" ]
    wifi office
    printf 'wifi:hotel\n' > "$NMDEV.next"
    cat > "$SHIMDIR/nmcli" <<'SHIM'
#!/usr/bin/env bash
cat "$NMDEV"; [ -f "$NMDEV.next" ] && mv "$NMDEV.next" "$NMDEV"; exit 0
SHIM
    run "$NETWATCH" --rounds 3
    [ "$(cat "$NOTIFY")" = '-a netwatch wifi: office -> hotel ' ]
    printf 'bt:phone\n' > "$NMDEV"
    run "$NETWATCH" --rounds 2
    [ "$(grep -c 'wifi:' "$NOTIFY")" -eq 1 ]
}

@test "a single default route is a no-op" {
    routes 600
    pings wlan "100 0"
    run "$NETWATCH" --rounds 3
    [ "$status" -eq 0 ]
    [ ! -e "$LOG" ]
}

@test "help and bad arguments" {
    run "$NETWATCH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--rounds N"* ]]
    run "$NETWATCH" --bogus
    [ "$status" -eq 2 ]
    run "$NETWATCH" --rounds x
    [ "$status" -eq 2 ]
}
