#!/bin/bash
# Low Power Mode safety test for lidstay, with a fake pmset (no real settings touched).
# Checks: lidstay only ever writes the battery profile, never the charger one,
# and a restore that fails (as at shutdown) keeps the saved value for next time.
set -u
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "$DIR/tmp/lpmtest.XXXX")
mkdir -p "$T/bin"
cat > "$T/bin/pmset" <<'SHIM'
#!/bin/bash
# fake pmset: values in $T/b and $T/c, every call logged, $T/fail = refuse writes
echo "pmset $*" >> "$T/calls"
case "$*" in
  "-g custom") printf 'Battery Power:\n lowpowermode         %s\nAC Power:\n lowpowermode         %s\n' "$(cat $T/b)" "$(cat $T/c)";;
  "-b lowpowermode "*) [ -f "$T/fail" ] && { echo "'pmset' failed to save energy preferences" >&2; exit 1; }; echo "$3" > "$T/b";;
  "-c lowpowermode "*|"-a lowpowermode "*) [ -f "$T/fail" ] && exit 1; echo "$3" > "$T/c"; [ "$1" = -a ] && echo "$3" > "$T/b";;
esac
exit 0
SHIM
chmod +x "$T/bin/pmset"
export T PATH="$T/bin:$PATH" STATE="$T/state" PAUSE_FILE="$T/pause" FAKE_SRC=AC FAKE_PCT=80 FAKE_SD=1 FAKE_DISP=0 FAKE_IDLE=0 FAKE_BLOCK=0
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
tick() { FAKE_LID=$1 bash "$DIR/lidstay.sh" once >> "$T/out" 2>&1; }

# 1. Settings "Never" (0 0): close lid, open lid
echo 0 > "$T/b"; echo 0 > "$T/c"
tick Yes
check "lid closed: battery profile on"            '[ "$(cat $T/b)" = 1 ]'
check "lid closed: charger profile still off"     '[ "$(cat $T/c)" = 0 ]'
tick No
check "lid open: battery profile back to off"     '[ "$(cat $T/b)" = 0 ]'
check "lid open: charger profile still off"       '[ "$(cat $T/c)" = 0 ]'

# 2. Restore fails (Mac shutting down): saved value must survive the reboot
tick Yes
touch "$T/fail"; tick No; rm "$T/fail"
check "failed restore keeps the saved value"      '[ -f $T/state ] && [ "$(cat $T/state)" = 0 ]'
tick Yes   # after reboot, lid still shut: must not re-save the leaked 1
check "no re-save of the leaked value"            '[ "$(cat $T/state)" = 0 ]'
tick No
check "after reboot: battery back to off"         '[ "$(cat $T/b)" = 0 ] && [ ! -f $T/state ]'

# 3. Old-format state file "1 1" (what the old code left): charger never written
echo "0 1" > "$T/state"; echo 1 > "$T/b"; echo 0 > "$T/c"
tick No
check "old state file: charger ignored"           '[ "$(cat $T/c)" = 0 ] && [ "$(cat $T/b)" = 0 ]'

# 4. Battery user with "Only on Battery" (1 0) keeps it
echo 1 > "$T/b"; echo 0 > "$T/c"; tick Yes; tick No
check "Only on Battery setting kept"              '[ "$(cat $T/b)" = 1 ] && [ "$(cat $T/c)" = 0 ]'

check "never wrote the charger profile (-c/-a)"   '! grep -qE "lowpowermode" <(grep -E "pmset -(c|a) " $T/calls)'
echo "--- lowpowermode writes made:"; grep -E "lowpowermode [01]" "$T/calls" | sort | uniq -c
mv "$T" ~/.Trash/ 2>/dev/null
exit $fails
