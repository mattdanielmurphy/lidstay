# lidstay

Keeps a MacBook running with the lid closed, and turns on Low Power Mode while the lid is shut. No apps needed: one shell script run by a LaunchDaemon.

- Plugged in: always stays awake with the lid closed.
- On battery: stays awake down to 20%; below that, closing the lid sleeps it (`ON_BATTERY=0` to only stay awake when plugged in).
- Lid closed: Low Power Mode on. Lid open: your previous Low Power setting comes back.
- Idle sleep still works: blocking lid-close sleep (`pmset disablesleep`, the flag Amphetamine uses) also blocks normal idle sleep, so lidstay does it itself. Lid open + idle past your Energy "sleep" timer + no app holding the Mac awake = sleep.

## Install / remove

    ./install.sh          # asks for your password once
    ./uninstall.sh        # puts normal sleep back

Check it: `pmset -g | grep -E 'SleepDisabled|lowpowermode'` and `tail /var/log/lidstay.log`.

## Notes

- Don't run it alongside Amphetamine's Closed-Display Mode or another tool that flips `disablesleep`; they'll fight.
- A closed laptop in a bag gets hot. Low Power Mode helps, but unplug-and-pack means it keeps running until 20%.
- Test without root: `DRY_RUN=1 STATE=./tmp/s FAKE_LID=Yes FAKE_SRC=Battery FAKE_PCT=20 FAKE_SD=1 ./lidstay.sh once`
