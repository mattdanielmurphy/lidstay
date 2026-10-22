# lidstay context
- Root LaunchDaemon `local.lidstay` runs `/usr/local/bin/lidstay` (copy of lidstay.sh) every 5s; logs to /var/log/lidstay.log.
- `pmset disablesleep` must be set before the lid closes (clamshell sleep is near-instant), so it's armed whenever power policy allows; disablesleep also kills idle sleep, so the Mac never idle-sleeps with the lid open either (Matt wants that, 2026-10-22). IDLE_SLEEP=1 re-enables emulated idle sleep (lid open, HIDIdleTime >= pmset sleep timer, no PreventUserIdleSystemSleep/PreventSystemSleep assertions).
- Independent of Hammerspoon: lid_sleep.lua only writes the pause file. Never bootout local.lidstay or flip `pmset disablesleep` from other tools/agents.
- Saved Low Power values live in /var/db/lidstay.lowpower while the lid is shut; restored per profile (-b/-c) on open or on SIGTERM.
- Matt's Mac has an Amphetamine Power Protect sudoers rule allowing passwordless `pmset -a disablesleep 1/0`; lowpowermode still needs root.
- Menu bar icon: `menubar.swift` (AppKit NSStatusItem), compiled by install.sh with swiftc to /usr/local/bin/lidstay-menu, run by user LaunchAgent `local.lidstay.menu`. Default on; auto-off when ~/.hammerspoon/modules/lid_sleep.lua exists (Matt uses his ⚙︎ menu). Writes the same pause file.
