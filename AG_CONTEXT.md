# lidstay context
- Root LaunchDaemon `local.lidstay` runs `/usr/local/bin/lidstay` (copy of lidstay.sh) every 5s; logs to /var/log/lidstay.log.
- `pmset disablesleep` must be set before the lid closes (clamshell sleep is near-instant), so it's armed whenever power policy allows; side effect: no idle sleep while armed.
- Saved Low Power values live in /var/db/lidstay.lowpower while the lid is shut; restored per profile (-b/-c) on open or on SIGTERM.
- Matt's Mac has an Amphetamine Power Protect sudoers rule allowing passwordless `pmset -a disablesleep 1/0`; lowpowermode still needs root.
