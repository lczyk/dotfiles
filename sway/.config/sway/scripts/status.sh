#!/usr/bin/env bash

# spellchecker: ignore upower amixer nmcli

function main () {
    local write_to_influx=0
    if [ "$1" = "--influx" ]; then
        write_to_influx=1
        shift
    fi

    # date
    # <short month> <numeric month>-<numeric day> <short weekday> <hour>:<minute>
    # DATE=$(date +'%b %m-%d %a %H:%M')
    DATE=$(date +'%b %d/%m %a %H:%M')

    # battery
    local upower=$(upower -i "$(upower -e | grep 'battery')")
    local battery=$(echo "$upower" | sed -n 's/ *percentage: *//;tt;b;:t s/ *//;s/%//;p' )
    # check if we have influxdb to write the status

    local battery_state=$(echo "$upower" | sed -n 's/ *state: *//;tt;b;:t s/ *//;p' )

    BATTERY=$(echo "$battery" | sed -n 's/\.[0-9]*//;s/$/%/;p' )
    if [ "$battery_state" = "charging" ]; then
        local time_to_full=$(echo "$upower" | sed -n 's/ *time to full: *//;tt;b;:t s/ minutes/min/; s/ hours/h/; p' )
        BATTERY="${BATTERY} ^"
        if [ -n "$time_to_full" ]; then
            BATTERY="${BATTERY} (${time_to_full})"
        fi
    elif [ "$battery_state" = "discharging" ]; then
        local time_to_empty=$(echo "$upower" | sed -n 's/ *time to empty: *//;tt;b;:t s/ minutes/min/; s/ hours/h/; p' )
        BATTERY="${BATTERY} v"
        if [ -n "$time_to_empty" ]; then
            BATTERY="${BATTERY} (${time_to_empty})"
        fi
    elif [ "$battery_state" = "fully-charged" ]; then
        BATTERY="${BATTERY} ~"
    elif [ "$battery_state" = "unknown" ]; then
        BATTERY="${BATTERY} ?"
    else
        BATTERY="${BATTERY} x"
    fi

    # volume
    local _volume=$(amixer get Master)
    if [ -z "$_volume" ]; then
        VOLUME="no sound"
    else
        VOLUME=$(echo "$_volume" | sed -n 's/ *Front Left:.*\(\[.*\]\).*\(\[.*\]\)/\1 \2/;tt;b;:t s/[][]//g; p')
    fi

    # brightness
    BRIGHTNESS=$(light | sed 's/\.[0-9]*//;s/^/b/')

    # wifi and, maybe, vpn
    local _con=$(nmcli con show --active)
    local wifi=$(echo "$_con" | sed -n '/wifi/ { s/^ *\([^ ]*\).*/\1/p }' )
    local vpn=$(echo "$_con" | sed -n '/vpn/ { s/^ *\([^ ]*\).*/\1/p }' )
    WIFI_AND_VPN="${wifi}"
    if [ -z "$wifi" ]; then
        WIFI_AND_VPN="no wifi"
    else
        if [ -n "$vpn" ]; then
            WIFI_AND_VPN="${WIFI_AND_VPN} (${vpn})"
        fi
    fi

    # get the top cpu usage but ignore 'top'
    TOP=$(top -o%CPU -bn1 | head -n9 | grep -v top | tail -n1 | awk '{print($9,$12)}')

    # temperature
    local thermal_zones=$(for zone in /sys/class/thermal/thermal_zone*; do cat "$zone/temp" | tr '\n' ' ' && cat "$zone/type"; done)
    local max_temp=$(echo "$thermal_zones" | sort -n | tail -n1 | awk '{print($1/1000)}')
    TEMP="$(echo "$max_temp" | awk '{printf("%.1fC",$1)}')"

    if [ "$write_to_influx" -eq 1 ]; then
        influx_payload=("power battery=${battery}" "thermal temperature=${max_temp}")

        # for each line, add a payload to influx_payload
        while read -r line; do
            temp=$(echo "$line" | awk '{print($1/1000)}')
            zone=$(echo "$line" | awk '{print($2)}')
            influx_payload+=("thermal ${zone}=${temp}")
        done <<< "$thermal_zones"

        if command -v influx 1> /dev/null; then
            # individual lines separated by newlines
            _overall_payload=""
            for payload in "${influx_payload[@]}"; do
                _overall_payload="${_overall_payload}${payload}
    "
            done
            influx write -b status -p s "$_overall_payload"
        fi
    fi
}

main "$@"


# overall status
STATUS="${TOP} | ${TEMP} | ${WIFI_AND_VPN} | ${BRIGHTNESS} | ${VOLUME} | ${BATTERY} | ${DATE}"

echo "$STATUS "