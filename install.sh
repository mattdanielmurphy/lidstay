#!/bin/bash
# Install lidstay as a LaunchDaemon (asks for your password once).
#   ./install.sh                  stay awake on charger and on battery down to 20%
#   ON_BATTERY=0 ./install.sh     stay awake only when plugged in
#   MIN_BATTERY=40 ./install.sh   change the battery floor
#   MENUBAR=0 ./install.sh        skip the menu bar icon (default: on, unless the
#                                 Hammerspoon "Lid" menu is set up)
set -e
[ "$(id -u)" = 0 ] || exec sudo ON_BATTERY="${ON_BATTERY:-1}" MIN_BATTERY="${MIN_BATTERY:-20}" MENUBAR="${MENUBAR:-}" "$0" "$@"

DIR=$(cd "$(dirname "$0")" && pwd)
LABEL=local.lidstay
PLIST=/Library/LaunchDaemons/$LABEL.plist

mkdir -p /usr/local/bin
install -m 755 "$DIR/lidstay.sh" /usr/local/bin/lidstay

USR=${SUDO_USER:-$(stat -f %Su /dev/console)}
UHOME=$(dscl . -read "/Users/$USR" NFSHomeDirectory | awk '{print $2}')

# Pause folder the logged-in user can write (menu bar icon / pause file)
mkdir -p /Users/Shared/lidstay
chown "$USR" /Users/Shared/lidstay

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
# bootout returns before the old copy has exited; bootstrap fails (error 5) until it has
for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print system/$LABEL >/dev/null 2>&1 || break; sleep 1; done
launchctl bootstrap system "$PLIST"
sleep 2
# Menu bar icon (a per-user LaunchAgent). Skipped where Hammerspoon's Lid menu does the job.
[ -z "$MENUBAR" ] && { [ -f "$UHOME/.hammerspoon/modules/lid_sleep.lua" ] && MENUBAR=0 || MENUBAR=1; }
MLABEL=local.lidstay.menu
MPLIST=$UHOME/Library/LaunchAgents/$MLABEL.plist
UID_=$(id -u "$USR")
if [ "$MENUBAR" = 1 ]; then
  mkdir -p "$DIR/tmp"
  sudo -u "$USR" swiftc -O "$DIR/menubar.swift" -o "$DIR/tmp/lidstay-menu"
  install -m 755 "$DIR/tmp/lidstay-menu" /usr/local/bin/lidstay-menu
  sudo -u "$USR" mkdir -p "$UHOME/Library/LaunchAgents"
  cat > "$MPLIST" <<MPL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MLABEL</string>
  <key>ProgramArguments</key><array><string>/usr/local/bin/lidstay-menu</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
MPL
  chown "$USR" "$MPLIST"
  launchctl bootout gui/$UID_/$MLABEL 2>/dev/null || true
  for _ in 1 2 3 4 5; do launchctl print gui/$UID_/$MLABEL >/dev/null 2>&1 || break; sleep 1; done
  launchctl bootstrap gui/$UID_ "$MPLIST"
  echo "Menu bar icon: on (laptop = stays awake, moon = lid sleep allowed)."
elif [ -f "$MPLIST" ]; then
  launchctl bootout gui/$UID_/$MLABEL 2>/dev/null || true
  mv "$MPLIST" "$UHOME/.Trash/" 2>/dev/null || true
fi

echo "lidstay installed. Status:"
pmset -g | grep -E 'SleepDisabled|lowpowermode'
tail -3 /var/log/lidstay.log
