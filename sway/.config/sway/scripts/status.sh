# date
# <short month> <numeric month>-<numeric day> <short weekday> <hour>:<minute>
DATE=$(date +'%b %m-%d %a %H:%M')

# battery
_upower=$(upower -i $(upower -e | grep 'battery'))
BATTERY=$(echo "$_upower" | grep -E "percentage" | awk '{gsub(/%/,""); printf("%.0f%%",$2)}')
BATTERY_STATE=$(echo "$_upower" | grep -E "state" | awk '{print($2)}')

SHORT_STATE=""
if [ "$BATTERY_STATE" = "charging" ]; then
    SHORT_STATE="c"
elif [ "$BATTERY_STATE" = "discharging" ]; then
    SHORT_STATE="d"
elif [ "$BATTERY_STATE" = "fully-charged" ]; then
    SHORT_STATE="f"
elif [ "$BATTERY_STATE" = "unknown" ]; then
    SHORT_STATE="?"
else
    SHORT_STATE="X"
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

# overall status
STATUS="${WIFI_AND_VPN} | ${BRIGHTNESS} | ${VOLUME} | ${BATTERY} ${SHORT_STATE} | ${DATE}"

echo "$STATUS "