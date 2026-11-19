#!/bin/bash
# lidstay: keep a MacBook awake with the lid closed, and run Low Power Mode by
# one rule. Runs as root from a LaunchDaemon (pmset needs root).
#
# Low Power Mode rule (Matt, 2026-11-19): ON while the lid is closed (charger
# or battery) or while on battery below LOW_BATTERY%; OFF in every other case,
# including right after plugging in with the lid open. lidstay owns the
# setting: each tick it writes both profiles (pmset -a) if they differ from the
# rule, so a failed write (e.g. during shutdown) is fixed on the next tick.
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
#   LOW_BATTERY=20  on battery, Low Power Mode comes on below this %
#   IDLE_SLEEP=0    1 = still sleep when idle with the lid open (0 = never)
#   INTERVAL=5      seconds between checks
#   DRY_RUN=1       print the pmset commands instead of running them
#
# Pause (normal sleep, as if lidstay weren't installed): write to $PAUSE_FILE
#   an epoch time to pause until then, or "manual" to pause until the file is removed.
#   Hammerspoon's menu writes it; any user can.
#   FAKE_LID / FAKE_SRC / FAKE_PCT / FAKE_SD / FAKE_IDLE / FAKE_BLOCK / FAKE_DISP / FAKE_LPM ("b c")   override readings (for testing)
#
# Screen: with sleep disabled the built-in screen stays lit behind a closed lid
# (macOS only turns it off as part of sleeping). So while the lid is shut the
# display is put to sleep, and again whenever something wakes it. Opening the
# lid wakes it at the old brightness. (Setting brightness directly doesn't work
# here: DisplayServices ignores the built-in panel while the lid is closed.)

ON_BATTERY=${ON_BATTERY:-1}
MIN_BATTERY=${MIN_BATTERY:-20}
LOW_BATTERY=${LOW_BATTERY:-20}
IDLE_SLEEP=${IDLE_SLEEP:-0}
INTERVAL=${INTERVAL:-5}
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

display_on() {  # powerd holds this assertion exactly while a display is on
  if [ -n "$FAKE_DISP" ]; then [ "$FAKE_DISP" = 1 ]; return; fi
  pmset -g assertions | grep -q "Prevent sleep while display is on"
}

screen_off() {
  display_on || return
  run pmset displaysleepnow
  log "lid closed: screen off"
}

# Low Power Mode values for the battery (b) and charger (c) profiles, e.g. "0 0"
lowpower_values() {
  if [ -n "$FAKE_LPM" ]; then echo "$FAKE_LPM"; return; fi
  pmset -g custom | awk '/^Battery/{s="b"} /^AC/{s="c"} $1=="lowpowermode"{v[s]=$2} END{print v["b"]+0, v["c"]+0}'
}

lowpower_want() {  # $1 = AC/Battery, $2 = battery %, $3 = 1 if lid closed; prints 1/0
  if [ "$3" = 1 ]; then echo 1
  elif [ "$1" = Battery ] && [ "${2:-100}" -lt "$LOW_BATTERY" ]; then echo 1
  else echo 0; fi
}

lowpower_apply() {  # $1 = 1/0, $2 = reason for the log
  local b c; read -r b c <<< "$(lowpower_values)"
  [ "$b" = "$1" ] && [ "$c" = "$1" ] && return
  run pmset -a lowpowermode "$1" 2>/dev/null || return   # retried next tick
  log "Low Power Mode $([ "$1" = 1 ] && echo on || echo off) ($2)"
}

set_awake() {  # $1 = 1 to keep awake, 0 to allow normal sleep
  [ "$(sleep_disabled)" = "$1" ] && return
  run pmset -a disablesleep "$1"
  log "disablesleep $1"
}

cleanup() {
  set_awake 0
  lowpower_apply 0 "lidstay stopped"
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
  local src pct lid=0 want=0
  src=$(power_source)
  pct=$(battery_pct)
  lid_closed && lid=1
  # Low Power Mode follows its rule even while paused
  lowpower_apply "$(lowpower_want "$src" "$pct" "$lid")" \
    "$([ "$lid" = 1 ] && echo "lid closed" || echo "lid open"), $src ${pct}%"
  if paused; then
    set_awake 0
    return
  fi
  if [ "$src" = AC ]; then
    want=1
  elif [ "$ON_BATTERY" = 1 ] && [ "${pct:-0}" -ge "$MIN_BATTERY" ]; then
    want=1
  fi

  if [ "$lid" = 1 ]; then
    screen_off
    if [ "$want" = 0 ] && [ "$(sleep_disabled)" = 1 ]; then
      set_awake 0
      log "lid closed and $src at ${pct}%: sleeping now"
      run pmset sleepnow
      return
    fi
  else
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

log "started (ON_BATTERY=$ON_BATTERY MIN_BATTERY=$MIN_BATTERY LOW_BATTERY=$LOW_BATTERY IDLE_SLEEP=$IDLE_SLEEP)"
while true; do
  tick
  sleep "$INTERVAL" & wait $!
done
