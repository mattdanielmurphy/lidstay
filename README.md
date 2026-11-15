# lidstay

Keeps a MacBook running with the lid closed, and turns on Low Power Mode while the lid is shut. No apps needed: one shell script run by a LaunchDaemon.

- Plugged in: always stays awake with the lid closed.
- On battery: stays awake down to 20%; below that, closing the lid sleeps it (`ON_BATTERY=0` to only stay awake when plugged in).
- Lid closed: the screen turns off (it otherwise stays lit behind the lid) and Low Power Mode comes on. Lid open: your previous Low Power setting comes back.
- Lid open: also stays awake (no idle sleep); the display still sleeps on its timer. `IDLE_SLEEP=1 ./install.sh` brings idle sleep back: lid open + idle past your Energy "sleep" timer + no app holding the Mac awake = sleep.
- Doesn't depend on Hammerspoon or any app: it's a root LaunchDaemon (`KeepAlive`), so reloads, crashes and logouts don't touch it. Hammerspoon's Lid menu only writes the pause file.

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

## Sony TV: on when you use the Mac, push up to switch

`tv.py` talks to a Sony Bravia (tested on a KD-43X85K) over the network, and Hammerspoon's **TV Follow** module (`~/.hammerspoon/modules/tv_follow.lua`) decides when:

1. **You use the Mac and the TV is off.** Your first touch after 10 idle minutes, or waking/unlocking the Mac, turns an off TV on, on the Mac's input. This is the only automatic switch: a TV that's on, showing anything else (an app, Settings, another HDMI), is never pulled back by itself.
2. **Push up to switch.** The TV sits above the laptop. While it isn't showing the Mac, the cursor stops at the laptop's top edge instead of vanishing onto it, and a bar at the top says "Keep pushing to switch the TV to your Mac". Keep pushing until it fills and the TV switches (turning on if needed); stop and it fades. Only pushes from the laptop screen count: a cursor left on the TV is moved down to the laptop. There are at least 8 s between switches.
3. **Windows leave the TV.** While the TV is off or on another input (and the laptop screen is open), windows on the TV move to the same spot on the laptop screen, and new ones that open on the TV follow. When the TV shows the Mac again, each one goes back where it was, unless you've moved it since. The list survives a Hammerspoon reload. The menu bar and Dock stay on the TV.
4. **Nothing is guessed when the TV can't be reached:** windows stay where they are.

All timings are in the Tweaks panel (⌃⌥⌘T → TV Follow).

### One-time setup on the TV (needed to switch inputs)

Without this, the Mac can only wake the TV, and it can't tell which input is showing, so windows stay put. On the TV: **Settings → Network & Internet → Home network setup → IP control**:

- **Authentication**: "Normal and Pre-Shared Key".
- **Pre-Shared Key**: any word or number you like.
- **Remote start**: On (lets the Mac turn the TV on from standby).

Then put the same key in this folder's `.env` as `BRAVIA_PSK=...` (the file isn't committed) and check it with `./tv.py check`.

### Pieces

- `tv.py status | mac | on | input N | check`: use it by hand too (`./tv.py mac` = TV on, Mac's input).
- `tv.py serve` runs as the user LaunchAgent `local.lidstay.tv` (`./tv-install.sh`, also run by `install.sh`; `TV=0` skips it), on 127.0.0.1:47613. It exists because macOS's Local Network privacy blocks Hammerspoon and Homebrew's Python from the TV, while Apple's `/usr/bin/python3` in a LaunchAgent is allowed. Log: `~/Library/Logs/lidstay-tv.log`.
- Different TV address or HDMI port: `BRAVIA_IP=192.168.1.20 BRAVIA_MAC_PORT=2 ./tv-install.sh`. The TV's address can change if your router hands it a new one; reserve it in the router to be safe.

## Update

    cd ~/projects/lidstay && git pull && ./install.sh

`install.sh` copies the script into place and restarts the daemon, so re-running it is how updates go live. Settings (`ON_BATTERY`, `MIN_BATTERY`, `IDLE_SLEEP`) are re-applied each time; pass them again if you changed them, e.g. `MIN_BATTERY=30 ./install.sh`.

Check it: `pmset -g | grep -E 'SleepDisabled|lowpowermode'` and `tail /var/log/lidstay.log`.

## Notes

- Don't run it alongside Amphetamine's Closed-Display Mode or another tool that flips `disablesleep`; they'll fight.
- A closed laptop in a bag gets hot. Low Power Mode helps, but unplug-and-pack means it keeps running until 20%.
- Test without root: `DRY_RUN=1 STATE=./tmp/s FAKE_LID=Yes FAKE_SRC=Battery FAKE_PCT=20 FAKE_SD=1 ./lidstay.sh once`
