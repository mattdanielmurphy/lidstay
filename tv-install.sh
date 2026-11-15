#!/bin/bash
# Start tv.py's local server at login (user LaunchAgent local.lidstay.tv; no password needed).
#   ./tv-install.sh                         TV at 192.168.40.57, Mac on HDMI 3
#   BRAVIA_IP=192.168.1.20 BRAVIA_MAC_PORT=2 ./tv-install.sh
#   ./tv-install.sh remove                  stop and remove it
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
LABEL=local.lidstay.tv
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
LOG=$HOME/Library/Logs/lidstay-tv.log
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
for _ in 1 2 3 4 5; do launchctl print gui/$(id -u)/$LABEL >/dev/null 2>&1 || break; sleep 1; done
if [ "$1" = remove ]; then mv "$PLIST" ~/.Trash/ 2>/dev/null || true; echo "TV server removed."; exit 0; fi
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <!-- Apple's python: macOS lets it reach the TV on the local network (Homebrew's and Hammerspoon are blocked) -->
  <key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$DIR/tv.py</string><string>serve</string>
    <string>--ip</string><string>${BRAVIA_IP:-192.168.40.57}</string><string>--port</string><string>${BRAVIA_MAC_PORT:-3}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PL
launchctl bootstrap gui/$(id -u) "$PLIST"
sleep 1.5
echo "TV server: $(curl -s -m 5 http://127.0.0.1:47613/status || echo 'not answering, see '"$LOG")"
