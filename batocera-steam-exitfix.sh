#!/bin/bash
#
# batocera-steam-exitfix.sh
#
# Problem: on Batocera 43.1 (2026/05/29 build), quitting Steam can
# freeze/hang instead of closing cleanly. Root cause is a race
# condition in /usr/bin/batocera-steam's background log-watcher: it
# uses "tail -f" without a proper exit path, and its subshell doesn't
# redirect stdin/stdout or clean up its child process group on kill.
# This matches Batocera GitHub issue #16567.
#
# Fix: three targeted patches to the installed batocera-steam script:
#   1. tail -f -> tail -F (handles log rotation/recreation, common
#      cause of tail hanging indefinitely) with stderr suppressed.
#   2. The background subshell gets its stdio explicitly redirected
#      to /dev/null so it can't block on an inherited terminal/pipe.
#   3. The final "kill $log_watcher_pid" becomes a pkill -P first (to
#      reap the subshell's children too) before killing the pid
#      itself.
#
# Why this file exists instead of just running the patch once: Batocera
# system updates typically replace files under /usr wholesale, silently
# reverting this fix. Installing this as a Batocera service means the
# patch is reapplied automatically on every boot, so it survives
# updates without you needing to remember to redo it by hand.
#
# Installation:
#   1. Save this file as /userdata/system/services/batocerasteamexitfix
#   2. chmod +x /userdata/system/services/batocerasteamexitfix
#   3. Start -> System Settings -> Services -> enable
#      "batocerasteamexitfix"
#
# This is a workaround for an upstream bug, not a permanent fix --
# check whether Batocera issue #16567 has been resolved in your
# installed version before assuming you still need this.

TARGET=/usr/bin/batocera-steam

apply_patch() {
    [ -f "$TARGET" ] || return 1

    # Only patch if not already patched (idempotent -- safe to run on
    # every boot even after an update reverts a prior patch, and safe
    # to run again if the file was already fixed).
    if grep -q "tail -F" "$TARGET" 2>/dev/null; then
        return 0
    fi

    sed -i "s/tail -f -n 0 \"\$log_file\"/tail -F -n 0 \"\$log_file\" 2>\/dev\/null/" "$TARGET"
    sed -i 's/) &$/) <\/dev\/null >\/dev\/null 2>\&1 \&/' "$TARGET"
    sed -i 's/kill "$log_watcher_pid"/pkill -P "$log_watcher_pid" 2>\/dev\/null; kill "$log_watcher_pid" 2>\/dev\/null/' "$TARGET"
}

case "$1" in
    start)
        apply_patch
        ;;
    stop)
        # Nothing to stop -- this is a one-shot patch applied at boot,
        # not a running process.
        ;;
esac
exit 0
