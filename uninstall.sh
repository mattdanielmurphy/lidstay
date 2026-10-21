#!/bin/bash
# Stop lidstay, put normal sleep and Low Power settings back, and remove it.
set -e
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
LABEL=local.lidstay
launchctl bootout system/$LABEL 2>/dev/null || true   # lidstay restores settings on exit
pmset -a disablesleep 0
TRASH="/Users/${SUDO_USER:-$(stat -f %Su /dev/console)}/.Trash"
mv /Library/LaunchDaemons/$LABEL.plist "$TRASH/" 2>/dev/null || true
mv /usr/local/bin/lidstay "$TRASH/lidstay.sh" 2>/dev/null || true
echo "lidstay removed. SleepDisabled is now $(pmset -g | awk '/SleepDisabled/{print $2}')."
