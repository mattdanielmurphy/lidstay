# lidstay

Keeps a MacBook running with the lid closed, and turns on Low Power Mode while the lid is shut. No apps needed: one shell script run by a LaunchDaemon.

- Plugged in: always stays awake with the lid closed.
- On battery: stays awake down to 20%; below that, closing the lid sleeps it (`ON_BATTERY=0` to only stay awake when plugged in).
- Lid closed: Low Power Mode on. Lid open: your previous Low Power setting comes back.
- Idle sleep still works: blocking lid-close sleep (`pmset disablesleep`, the flag Amphetamine uses) also blocks normal idle sleep, so lidstay does it itself. Lid open + idle past your Energy "sleep" timer + no app holding the Mac awake = sleep.

## Install / remove

    git clone https://github.com/mattdanielmurphy/lidstay.git ~/projects/lidstay
    cd ~/projects/lidstay
    ./install.sh          # asks for your password once
    ./uninstall.sh        # puts normal sleep back

## Pause (let the lid sleep again)

    echo $(( $(date +%s) + 2*3600 )) > /Users/Shared/lidstay/pause_until   # 2 hours
    echo manual > /Users/Shared/lidstay/pause_until                       # until resumed
    mv /Users/Shared/lidstay/pause_until /Users/Shared/lidstay/pause_until.done  # resume

## Menu bar icon (optional)

`install.sh` also builds `menubar.swift` (with `swiftc` from Apple's Command Line Tools, no Xcode needed) and starts it at login: a laptop icon (moon while paused) with Allow lid sleep for 1/2/4/8 hours, until you turn it back, or Keep awake. Updating with `git pull && ./install.sh` rebuilds it.

Skip it with `MENUBAR=0 ./install.sh`. It's skipped automatically where Matt's Hammerspoon ⚙︎ menu already has the same items in a "Lid" submenu.

## Update

    cd ~/projects/lidstay && git pull && ./install.sh

`install.sh` copies the script into place and restarts the daemon, so re-running it is how updates go live. Settings (`ON_BATTERY`, `MIN_BATTERY`) are re-applied each time; pass them again if you changed them, e.g. `MIN_BATTERY=30 ./install.sh`.

Check it: `pmset -g | grep -E 'SleepDisabled|lowpowermode'` and `tail /var/log/lidstay.log`.

## Notes

- Don't run it alongside Amphetamine's Closed-Display Mode or another tool that flips `disablesleep`; they'll fight.
- A closed laptop in a bag gets hot. Low Power Mode helps, but unplug-and-pack means it keeps running until 20%.
- Test without root: `DRY_RUN=1 STATE=./tmp/s FAKE_LID=Yes FAKE_SRC=Battery FAKE_PCT=20 FAKE_SD=1 ./lidstay.sh once`
