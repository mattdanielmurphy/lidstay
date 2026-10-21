#!/bin/bash
# Install lidstay as a LaunchDaemon (asks for your password once).
#   ./install.sh                  stay awake on charger and on battery down to 20%
#   ON_BATTERY=0 ./install.sh     stay awake only when plugged in
#   MIN_BATTERY=40 ./install.sh   change the battery floor
set -e
[ "$(id -u)" = 0 ] || exec sudo ON_BATTERY="${ON_BATTERY:-1}" MIN_BATTERY="${MIN_BATTERY:-20}" "$0" "$@"

DIR=$(cd "$(dirname "$0")" && pwd)
LABEL=local.lidstay
PLIST=/Library/LaunchDaemons/$LABEL.plist

mkdir -p /usr/local/bin
install -m 755 "$DIR/lidstay.sh" /usr/local/bin/lidstay

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/usr/local/bin/lidstay</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ON_BATTERY</key><string>${ON_BATTERY:-1}</string>
    <key>MIN_BATTERY</key><string>${MIN_BATTERY:-20}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/lidstay.log</string>
  <key>StandardErrorPath</key><string>/var/log/lidstay.log</string>
</dict>
</plist>
PLIST
chmod 644 "$PLIST"

launchctl bootout system/$LABEL 2>/dev/null || true
launchctl bootstrap system "$PLIST"
sleep 2
echo "lidstay installed. Status:"
pmset -g | grep -E 'SleepDisabled|lowpowermode'
tail -3 /var/log/lidstay.log
