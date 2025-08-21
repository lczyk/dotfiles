#!/usr/bin/env bash
_write_to_influx=0
if [ "$1" = "--influx" ]; then
    _write_to_influx=1
    shift
fi

# date
# <short month> <numeric month>-<numeric day> <short weekday> <hour>:<minute>
DATE=$(date +'%b %m-%d %a %H:%M')

# battery
_upower=$(upower -i $(upower -e | grep 'battery'))
_battery=$(echo "$_upower" | sed -n 's/ *percentage: *//;tt;b;:t s/ *//;s/%//;p' )
# check if we have influxdb to write the status

BATTERY_STATE=$(echo "$_upower" | sed -n 's/ *state: *//;tt;b;:t s/ *//;p' )

BATTERY=$(echo "$_battery" | sed -n 's/\.[0-9]*//;s/$/%/;p' )
if [ "$BATTERY_STATE" = "charging" ]; then
    TIME_TO_FULL=$(echo "$_upower" | sed -n 's/ *time to full: *//;tt;b;:t s/ minutes/min/; s/ hours/h/; p' )
    BATTERY="${BATTERY} ^"
    if [ -n "$TIME_TO_FULL" ]; then
        BATTERY="${BATTERY} (${TIME_TO_FULL})"
    fi
elif [ "$BATTERY_STATE" = "discharging" ]; then
    TIME_TO_EMPTY=$(echo "$_upower" | sed -n 's/ *time to empty: *//;tt;b;:t s/ minutes/min/; s/ hours/h/; p' )
    BATTERY="${BATTERY} v"
    if [ -n "$TIME_TO_EMPTY" ]; then
        BATTERY="${BATTERY} (${TIME_TO_EMPTY})"
    fi
elif [ "$BATTERY_STATE" = "fully-charged" ]; then
    BATTERY="${BATTERY} ~"
elif [ "$BATTERY_STATE" = "unknown" ]; then
    BATTERY="${BATTERY} ?"
else
    BATTERY="${BATTERY} x"
fi

# volume
VOLUME=$(amixer get Master | sed -n 's/ *Front Left:.*\(\[.*\]\).*\(\[.*\]\)/\1 \2/;tt;b;:t s/[][]//g; p')

# brightness
BRIGHTNESS=$(light | sed 's/\.[0-9]*//;s/^/b/')

# wifi and, maybe, vpn
_con=$(nmcli con show --active)
WIFI=$(echo "$_con" | sed -n '/wifi/ { s/^ *\([^ ]*\).*/\1/p }' )
VPN=$(echo "$_con" | sed -n '/vpn/ { s/^ *\([^ ]*\).*/\1/p }' )
WIFI_AND_VPN="${WIFI}"
if [ -z "$WIFI" ]; then
    WIFI_AND_VPN="no wifi"
else
    if [ -n "$VPN" ]; then
        WIFI_AND_VPN="${WIFI_AND_VPN} (${VPN})"
    fi
fi

# get the top cpu usage but ignore 'top'
TOP=$(top -o%CPU -bn1 | head -n9 | grep -v top | tail -n1 | awk '{print($9,$12)}')

# temperature
thermal_zones=$(for zone in /sys/class/thermal/thermal_zone*; do cat "$zone/temp" | tr '\n' ' ' && cat "$zone/type"; done)
_max_temp=$(echo "$thermal_zones" | sort -n | tail -n1 | awk '{print($1/1000)}')
TEMP="$(echo "$_max_temp" | awk '{printf("%.1fC",$1)}')"

# overall status
STATUS="${TOP} | ${TEMP} | ${WIFI_AND_VPN} | ${BRIGHTNESS} | ${VOLUME} | ${BATTERY} | ${DATE}"

echo "$STATUS "

if [ "$_write_to_influx" -eq 1 ]; then
    # write status to influxdb
    # command -v influx 1> /dev/null && \
    #     influx write -b status -p s "status message=\"${STATUS}\""

    influx_payload=("power battery=${_battery}" "thermal temperature=${_max_temp}")

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
        # for payload in "${influx_payload[@]}"; do
        #     influx write -b status -p s "$payload"
        # done
    fi

    # # write temperature to influxdb
    # command -v influx 1> /dev/null && \
    #     influx writeC -b status -p s "thermal temperature=${temp}"
    # ls
fi
