#!/bin/bash
# Low Power Mode rule test for lidstay, with a fake pmset (no real settings touched).
# Rule: ON when the lid is closed (any power) or on battery below 20%; OFF otherwise.
set -u
DIR=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$DIR/tmp"
T=$(mktemp -d "$DIR/tmp/lpmtest.XXXX")
mkdir -p "$T/bin"
cat > "$T/bin/pmset" <<'SHIM'
#!/bin/bash
# fake pmset: values in $T/b and $T/c, every call logged, $T/fail = refuse writes
echo "pmset $*" >> "$T/calls"
case "$*" in
  "-g custom") printf 'Battery Power:\n lowpowermode         %s\nAC Power:\n lowpowermode         %s\n' "$(cat $T/b)" "$(cat $T/c)";;
  *lowpowermode*) [ -f "$T/fail" ] && { echo "'pmset' failed to save energy preferences" >&2; exit 1; }
    case "$1" in -a) echo "$3" > "$T/b"; echo "$3" > "$T/c";; -b) echo "$3" > "$T/b";; -c) echo "$3" > "$T/c";; esac;;
esac
exit 0
SHIM
chmod +x "$T/bin/pmset"
export T PATH="$T/bin:$PATH" PAUSE_FILE="$T/pause" FAKE_SD=1 FAKE_DISP=0 FAKE_IDLE=0 FAKE_BLOCK=0
fails=0
tick() { FAKE_LID=$1 FAKE_SRC=$2 FAKE_PCT=$3 bash "$DIR/lidstay.sh" once >> "$T/out" 2>&1; }
expect() {  # lid src pct want  (starts from the opposite setting, so a write is needed)
  local start=$((1 - $4)); echo $start > "$T/b"; echo $start > "$T/c"
  tick "$1" "$2" "$3"
  if [ "$(cat $T/b) $(cat $T/c)" = "$4 $4" ]; then echo "ok   lid=$1 $2 $3% -> $4"
  else echo "FAIL lid=$1 $2 $3% -> got $(cat $T/b) $(cat $T/c), want $4"; fails=$((fails+1)); fi
}
expect No  AC      80 0   # plugged in, lid open: off (the broken case)
expect No  AC      10 0   # just plugged in while low: off
expect No  Battery 80 0
expect No  Battery 20 0
expect No  Battery 19 1   # below 20% on battery: on
expect Yes AC      80 1   # clamshell on the charger: on
expect Yes Battery 80 1
expect Yes Battery 10 1

# A write that fails (Mac shutting down) is redone on the next tick
echo 1 > "$T/b"; echo 1 > "$T/c"; touch "$T/fail"
tick No AC 80; rm "$T/fail"
tick No AC 80
if [ "$(cat $T/b) $(cat $T/c)" = "0 0" ]; then echo "ok   failed write retried next tick"; else echo "FAIL retry"; fails=$((fails+1)); fi

# Already right: no write at all
: > "$T/calls"; tick No AC 80
if ! grep -q "lowpowermode [01]" "$T/calls"; then echo "ok   no write when already right"; else echo "FAIL extra write"; fails=$((fails+1)); fi

# Paused: rule still applies
echo manual > "$T/pause"; echo 1 > "$T/b"; echo 1 > "$T/c"; tick No AC 80; mv "$T/pause" "$T/pause.x"
if [ "$(cat $T/b) $(cat $T/c)" = "0 0" ]; then echo "ok   rule applies while paused"; else echo "FAIL paused"; fails=$((fails+1)); fi

mv "$T" ~/.Trash/ 2>/dev/null
exit $fails
