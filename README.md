# Batocera + Steam/Ubisoft Connect fixes

## Disclaimer

These scripts modify a system file (`/usr/bin/batocera-steam`) and
force-kill processes matching certain patterns. Tested only on
Batocera 43.1 (2026/05/29 build) with an NVIDIA RTX 5080. Behavior
on other Batocera versions, hardware, or Steam/Proton builds is not
guaranteed.

Use at your own risk. No warranty of any kind. Read the scripts
before running them, especially the `pkill -f "steam.exe"` pattern
noted under Known Limitation above — verify it doesn't match anything
unexpected on your own system before relying on it.

Two independent fixes for Batocera's Flatpak Steam integration,
developed and tested on Batocera 43.1 (2026/05/29 build) with an
RTX 5080 / NVIDIA 590.48.1.0 driver.

## 1. Steam quit hang (`batocera-steam-exitfix.sh`)

**Symptom:** quitting Steam sometimes freezes instead of closing.

**Cause:** a race condition in `/usr/bin/batocera-steam`'s background
log watcher. Matches [Batocera issue #16567](https://github.com/batocera-linux/batocera.linux/issues/16567) --
if that issue is closed/merged by the time you read this, you
probably don't need this fix anymore.

**Install:**
```
cp batocera-steam-exitfix.sh /userdata/system/services/batocerasteamexitfix
chmod +x /userdata/system/services/batocerasteamexitfix
```
Then enable it: **Start -> System Settings -> Services -> batocerasteamexitfix**

Runs once at boot, patches the installed script in place, and is
idempotent -- safe to leave enabled permanently, including across
Batocera updates that would otherwise silently revert the fix.

## 2. Ubisoft Connect processes hang on game exit (`ubisoft-watcher.sh`)

**Symptom:** exiting a Ubisoft-published game (Assassin's Creed,
Scott Pilgrim vs The World, etc.) under Proton leaves Ubisoft Connect
processes (`upc.exe`, `UplayWebCore.exe`) running. These don't close
on their own, and can block Steam's own exit (see fix #1) or just sit
there consuming resources until manually killed. This is a
widely-reported Proton/Ubisoft Connect issue, not specific to
Batocera -- see multiple ProtonDB pages for various Ubisoft titles.

**Fix:** a background watcher that detects when the actual game
binary has closed (not just the launcher/wrapper processes around it)
and force-kills the Ubisoft leftovers automatically. Works generically
for any Ubisoft-published game -- nothing to configure per-title.

**Install:**
```
mkdir -p /userdata/system/watcher
cp ubisoft-watcher.sh /userdata/system/watcher/ubisoft-watcher.sh
chmod +x /userdata/system/watcher/ubisoft-watcher.sh
```

Create the service wrapper at `/userdata/system/services/ubisoftwatcher`:
```bash
#!/bin/bash
case "$1" in
  start)
    /userdata/system/watcher/ubisoft-watcher.sh &
    echo $! > /tmp/ubisoftwatcher.pid
    ;;
  stop)
    kill $(cat /tmp/ubisoftwatcher.pid) 2>/dev/null
    ;;
esac
exit 0
```
```
chmod +x /userdata/system/services/ubisoftwatcher
```

Then enable it: **Start -> System Settings -> Services -> ubisoftwatcher**

**Important:** the watcher script must live outside
`/userdata/system/scripts/` -- that specific folder is Batocera's
built-in hook system, and any script placed there gets invoked
synchronously on every game launch/exit. A long-running background
script placed there will block every game from launching until it
exits, which it never does by design. Use a plain folder instead (this
guide uses `/userdata/system/watcher/`).

### Known limitation
The cleanup uses `pkill -9 -f "steam.exe"`, which is intentionally
broad. On the systems this was tested on, the real Linux-side Steam
client and its own helper processes never contain the literal text
`steam.exe` in their command lines -- that string only appears in the
Windows-side Steamworks API shim inside the game's Proton prefix. If
you ever notice the entire Steam client itself closing unexpectedly
right when you exit a game, this pattern is matching something it
shouldn't on your setup, and needs to be narrowed further.

### Debug logging
Set `DEBUG_LOG=1` near the top of `ubisoft-watcher.sh` to log every
detection cycle to `ubisoft-watcher.log` next to the script. Off by
default to avoid unnecessary disk writes; useful if you need to
troubleshoot detection on a setup that behaves differently from the
one this was built on.
