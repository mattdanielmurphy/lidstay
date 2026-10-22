#!/bin/bash
# <swiftbar.title>lidstay</swiftbar.title>
# <swiftbar.desc>Allow lid sleep for a while, or keep the Mac awake with the lid closed.</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# SwiftBar menu for lidstay. Run with an argument to act:
#   pause <hours> | pause manual | resume
# It only writes the pause file the lidstay daemon reads every 5s.

PAUSE_FILE=${PAUSE_FILE:-/Users/Shared/lidstay/pause_until}

case "$1" in
  pause)
    if [ "$2" = manual ]; then echo manual > "$PAUSE_FILE"
    else echo $(( $(date +%s) + $2 * 3600 )) > "$PAUSE_FILE"; fi
    exit 0 ;;
  resume)
    [ -f "$PAUSE_FILE" ] && mv "$PAUSE_FILE" "$PAUSE_FILE.done"
    exit 0 ;;
esac

until=$(head -c 40 "$PAUSE_FILE" 2>/dev/null | tr -d '[:space:]')
now=$(date +%s)
if [ "$until" = manual ]; then
  icon=moon.zzz; status="Lid sleep allowed (until you turn it back)"
elif [ -n "$until" ] && [ "$until" -eq "$until" ] 2>/dev/null && [ "$until" -gt "$now" ]; then
  icon=moon.zzz; status="Lid sleep allowed until $(date -r "$until" '+%-I:%M %p')"
else
  until=""; icon=laptopcomputer; status="Lid closed: stays awake"
fi

self="$0"
echo "| sfimage=$icon"
echo "---"
echo "$status"
if ! launchctl print system/local.lidstay >/dev/null 2>&1; then
  echo "lidstay isn't running (run install.sh) | color=red"
fi
echo "---"
for h in 1 2 4 8; do
  [ "$h" = 1 ] && unit=hour || unit=hours
  echo "Allow lid sleep for $h $unit | bash=\"$self\" param1=pause param2=$h terminal=false refresh=true"
done
[ "$until" = manual ] && mark=" checked=true" || mark=""
echo "Allow lid sleep until I turn it back | bash=\"$self\" param1=pause param2=manual terminal=false refresh=true$mark"
[ -z "$until" ] && mark=" checked=true" || mark=""
echo "Keep awake with lid closed | bash=\"$self\" param1=resume terminal=false refresh=true$mark"
