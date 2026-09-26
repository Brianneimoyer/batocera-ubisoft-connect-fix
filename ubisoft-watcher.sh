#!/bin/bash
#
# ubisoft-watcher.sh
#
# Problem: Ubisoft Connect (upc.exe / UplayWebCore.exe) does not exit
# cleanly under Proton when the game it launched closes. This leaves
# orphaned processes running that can hang Steam's own shutdown
# sequence, forcing the user to either kill them by hand or wait for
# a freeze on exit. This is a widely reported issue across many
# Ubisoft-published titles under Proton (see ProtonDB reports for
# multiple Ubisoft games).
#
# Fix: this script runs continuously in the background (as a Batocera
# service) and watches for the actual Ubisoft-launched game binary to
# disappear. Once it does, it force-kills every leftover
# "Ubisoft Game Launcher" process, and the internal Windows-side Steam
# shim that Proton games use, which for the same reason also does not
# self-terminate.
#
# Detection notes (why this isn't a one-line pgrep):
#   Steam tags any Ubisoft Connect-integrated launch with the flag
#   "-uplay_steam_mode". Naively matching on that flag alone finds
#   many false positives, because several supervisor/wrapper
#   processes also carry that flag in their own command line as
#   *descriptive text* of what they are managing, without it meaning
#   the game is actually still running:
#     - Steam's "reaper" process and the "proton ... waitforexitandrun"
#       wrapper chain: excluded by filtering out "waitforexitandrun".
#     - Ubisoft Connect's own upc.exe / UplayWebCore.exe processes:
#       excluded by filtering out "Ubisoft Game Launcher".
#     - The in-prefix Windows Steam API shim
#       (c:\windows\system32\steam.exe): excluded by filtering out
#       that specific path, since it can outlive the real game.
#   What's left after all three exclusions is the actual game binary
#   itself (e.g. S:\steamapps\common\<Game>\<Game>.exe).
#
# This generic approach works for ANY Ubisoft-published game, not
# just one hardcoded title -- nothing here needs to be edited when
# you add a new Ubisoft game to your library.
#
# Set DEBUG_LOG=1 below to log every detection cycle to
# ubisoft-watcher.log next to this script. Useful for troubleshooting
# if this ever stops working correctly on your system; noisy and
# unnecessary otherwise.

DEBUG_LOG=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/ubisoft-watcher.log"
CHECK_INTERVAL=5

log() {
    if [ "$DEBUG_LOG" = "1" ]; then
        echo "$(date): $1" >> "$LOG"
    fi
}

game_running() {
    for p in /proc/[0-9]*/cmdline; do
        [ -r "$p" ] || continue
        cmd=$(tr '\0' ' ' < "$p" 2>/dev/null)
        lc="${cmd,,}"
        if [[ "$cmd" == *"-uplay_steam_mode"* ]] \
            && [[ "$cmd" != *"Ubisoft Game Launcher"* ]] \
            && [[ "$cmd" != *"waitforexitandrun"* ]] \
            && [[ "$lc" != c:*windows*system32*steam.exe* ]]; then
            log "MATCH: $cmd"
            return 0
        fi
    done
    return 1
}

was_running=0

while true; do
    if game_running; then
        if [ "$was_running" != "1" ]; then
            log "game_running became TRUE"
        fi
        was_running=1
    else
        if [ "$was_running" = "1" ]; then
            log "game_running became FALSE, cleaning up leftover processes"
            pkill -9 -f "Ubisoft Game Launcher" 2>/dev/null
            pkill -9 -f "steam.exe" 2>/dev/null
            log "cleanup commands issued"
        fi
        was_running=0
    fi
    sleep "$CHECK_INTERVAL"
done
