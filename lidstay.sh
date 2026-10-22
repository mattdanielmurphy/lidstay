#!/bin/bash
# lidstay: keep a MacBook awake with the lid closed, and switch on Low Power
# Mode while the lid is shut. Runs as root from a LaunchDaemon (pmset needs root).
#
# Why disablesleep is set ahead of time: closing the lid sleeps the Mac within
# a second, before any watcher could react, so the flag must already be on.
# That flag also stops normal idle sleep, so with the lid open the Mac stays
# awake too (the default). IDLE_SLEEP=1 brings idle sleep back: lid open, idle
# past the Energy "sleep" timer, nothing holding the Mac awake.
#
# Settings (env vars, set in the LaunchDaemon plist):
#   ON_BATTERY=1    also stay awake on battery (0 = only when plugged in)
#   MIN_BATTERY=20  on battery, let the Mac sleep again below this %
#   IDLE_SLEEP=0    1 = still sleep when idle with the lid open (0 = never)
#   INTERVAL=5      seconds between checks
#   DRY_RUN=1       print the pmset commands instead of running them
#
# Pause (normal sleep, as if lidstay weren't installed): write to $PAUSE_FILE
#   an epoch time to pause until then, or "manual" to pause until the file is removed.
#   Hammerspoon's menu writes it; any user can.
#   FAKE_LID / FAKE_SRC / FAKE_PCT / FAKE_SD / FAKE_IDLE / FAKE_BLOCK   override readings (for testing)

ON_BATTERY=${ON_BATTERY:-1}
MIN_BATTERY=${MIN_BATTERY:-20}
IDLE_SLEEP=${IDLE_SLEEP:-0}
INTERVAL=${INTERVAL:-5}
STATE=${STATE:-/var/db/lidstay.lowpower}   # saved Low Power values while lid is shut
PAUSE_FILE=${PAUSE_FILE:-/Users/Shared/lidstay/pause_until}

log() { echo "$(date '+%F %T') $*"; }

run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then echo "DRY: $*"; else "$@"; fi
}

lid_closed() {
  local v=${FAKE_LID:-$(ioreg -r -k AppleClamshellState -d 1 | awk -F'= ' '/"AppleClamshellState"/{print $2; exit}')}
  [ "$v" = Yes ]
}

power_source() {  # prints AC or Battery
  if [ -n "$FAKE_SRC" ]; then echo "$FAKE_SRC"; return; fi
  pmset -g batt | grep -q "AC Power" && echo AC || echo Battery
}

battery_pct() {
  if [ -n "$FAKE_PCT" ]; then echo "$FAKE_PCT"; return; fi
  pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d %
}

sleep_disabled() { [ -n "$FAKE_SD" ] && { echo "$FAKE_SD"; return; }; pmset -g | awk '/SleepDisabled/{print $2; exit}'; }

idle_secs() {  # seconds since the last keyboard/mouse input
  if [ -n "$FAKE_IDLE" ]; then echo "$FAKE_IDLE"; return; fi
  ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'
}

sleep_timer_min() {  # the Energy "sleep" timer for this power source (0 = never)
  local prof=b; [ "$1" = AC ] && prof=c
  pmset -g custom | awk -v want=$prof '/^Battery/{s="b"} /^AC/{s="c"} s==want && $1=="sleep"{print $2; exit}'
}

idle_sleep_blocked() {  # an app is holding the Mac awake (Amphetamine, audio, caffeinate...)
  if [ -n "$FAKE_BLOCK" ]; then [ "$FAKE_BLOCK" = 1 ]; return; fi
  pmset -g assertions | awk '$1=="PreventUserIdleSystemSleep" || $1=="PreventSystemSleep" {n+=$2} END{exit !(n>0)}'
}

# Low Power Mode values for the battery (b) and charger (c) profiles, e.g. "0 0"
lowpower_values() {
  pmset -g custom | awk '/^Battery/{s="b"} /^AC/{s="c"} /lowpowermode/{v[s]=$2} END{print v["b"]+0, v["c"]+0}'
}

lowpower_on() {
  [ -f "$STATE" ] && return
  lowpower_values > "$STATE"
  run pmset -a lowpowermode 1
  log "lid closed: Low Power Mode on (saved $(cat "$STATE"))"
}

lowpower_restore() {
  [ -f "$STATE" ] || return
  read -r b c < "$STATE"
  run pmset -b lowpowermode "${b:-0}"
  run pmset -c lowpowermode "${c:-0}"
  mv "$STATE" "$STATE.last"
  log "Low Power Mode restored (battery $b, charger $c)"
}

set_awake() {  # $1 = 1 to keep awake, 0 to allow normal sleep
  [ "$(sleep_disabled)" = "$1" ] && return
  run pmset -a disablesleep "$1"
  log "disablesleep $1"
}

cleanup() {
  set_awake 0
  lowpower_restore
  log "stopped"
  exit 0
}
trap cleanup TERM INT

paused() {  # true while a pause is in effect; clears an expired one
  [ -f "$PAUSE_FILE" ] || return 1
  local until; until=$(head -c 40 "$PAUSE_FILE" | tr -d '[:space:]')
  [ "$until" = manual ] && return 0
  if [ -n "$until" ] && [ "$until" -eq "$until" ] 2>/dev/null && [ "$until" -gt "$(date +%s)" ]; then
    return 0
  fi
  mv "$PAUSE_FILE" "$PAUSE_FILE.done" 2>/dev/null
  log "pause over: back to staying awake"
  return 1
}

tick() {
  if paused; then
    lowpower_restore
    set_awake 0
    return
  fi
  local src pct want=0
  src=$(power_source)
  pct=$(battery_pct)
  if [ "$src" = AC ]; then
    want=1
  elif [ "$ON_BATTERY" = 1 ] && [ "${pct:-0}" -ge "$MIN_BATTERY" ]; then
    want=1
  fi

  if lid_closed; then
    lowpower_on
    if [ "$want" = 0 ] && [ "$(sleep_disabled)" = 1 ]; then
      set_awake 0
      log "lid closed and $src at ${pct}%: sleeping now"
      run pmset sleepnow
      return
    fi
  else
    lowpower_restore
    local timer idle
    timer=$(sleep_timer_min "$src")
    idle=$(idle_secs)
    if [ "$IDLE_SLEEP" = 1 ] && [ "$want" = 1 ] && [ "${timer:-0}" -gt 0 ] && [ "${idle:-0}" -ge $((timer * 60)) ] && ! idle_sleep_blocked; then
      set_awake 0
      log "idle ${idle}s (timer ${timer}m): sleeping now"
      run pmset sleepnow
      return
    fi
  fi
  set_awake "$want"
}

if [ "${1:-}" = once ]; then tick; exit 0; fi

log "started (ON_BATTERY=$ON_BATTERY MIN_BATTERY=$MIN_BATTERY IDLE_SLEEP=$IDLE_SLEEP)"
while true; do
  tick
  sleep "$INTERVAL" & wait $!
done
