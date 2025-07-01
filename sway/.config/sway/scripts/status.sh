# date
# <short month> <numeric month>-<numeric day> <short weekday> <hour>:<minute>
DATE=$(date +'%b %m-%d %a %H:%M')

# battery
_upower=$(upower -i $(upower -e | grep 'battery'))
battery=$(echo "$_upower" | grep -E "percentage" | awk '{gsub(/%/,""); printf("%.0f%%",$2)}')
BATTERY_STATE=$(echo "$_upower" | grep -E "state" | awk '{print($2)}')

BATTERY="${battery}"
if [ "$BATTERY_STATE" = "charging" ]; then
    BATTERY="${BATTERY} ^"
elif [ "$BATTERY_STATE" = "discharging" ]; then
    TIME_TO_EMPTY=$(echo "$_upower" | grep -E "time to empty" | awk '{printf("%.1fh",$4)}')
    BATTERY="${BATTERY} v (${TIME_TO_EMPTY})"
elif [ "$BATTERY_STATE" = "fully-charged" ]; then
    BATTERY="${BATTERY} ~"
elif [ "$BATTERY_STATE" = "unknown" ]; then
    BATTERY="${BATTERY} ?"
else
    BATTERY="${BATTERY} x"
fi

# volume
VOLUME=$(amixer get Master | grep 'Front Left:' | awk '{ gsub(/\[|\]/,""); print $5,$6 }')

# brightness
BRIGHTNESS=$(light | awk '{printf("b%.0f",$1)}')

# wifi and, maybe, vpn
_con=$(nmcli con show --active)
WIFI=$(echo "$_con" | grep wifi | awk '{print $1}')
VPN=$(echo "$_con" | grep vpn | awk '{print $1}')
WIFI_AND_VPN="${WIFI}"
if [ -n "$VPN" ]; then
    WIFI_AND_VPN="${WIFI_AND_VPN} (${VPN})"
fi

# get the top cpu usage but ignore 'top'
TOP=$(top -o%CPU -bn1 | head -n9 | grep -v top | tail -n1 | awk '{print($9,$12)}')

# temperature
TEMP=$(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n1 | awk '{printf("%.1fC",$1/1000)}')

# overall status
STATUS="${TOP} | ${TEMP} | ${WIFI_AND_VPN} | ${BRIGHTNESS} | ${VOLUME} | ${BATTERY} | ${DATE}"

echo "$STATUS "
