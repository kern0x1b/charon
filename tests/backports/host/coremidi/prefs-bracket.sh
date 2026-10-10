#!/bin/sh
# The host-probe rule (coordinator ruling, 2026-10-10) and the check that keeps it.
#
# A host CoreMIDI probe MAY create process-lifetime virtual sources and destinations and connect ports to them: the oracle
# needs it. It must NOT make anything persist:
#   - no MIDIDeviceCreate / MIDIExternalDeviceCreate that outlives the process;
#   - no MIDISetup* call;
#   - no MIDIObjectSetProperty* on an object the probe did not create;
#   - never MIDIRestart, never MIDIBluetoothDriverActivateAllConnections.
# Every probe run is bracketed by this check: the persistent MIDI preferences (the ByHost com.apple.MIDI.*.plist files and
# everything under ~/Library/Audio/MIDI Configurations) are hashed, read only, before and after, and the run fails when
# the two digests differ. A difference is reported with the files and the lines that differ (held in memory: nothing is
# copied), so that a change made by another process of the machine at the same moment can be told from one of the probe.
#
# Usage:
#   sh prefs-bracket.sh digest            print the digest of the persistent MIDI preferences
#   sh prefs-bracket.sh run <command...>  run the command between two digests; exit 1 when they differ, else the command's status
#   sh prefs-bracket.sh selftest          prove the check can fail: a stand-in home with a preference file is changed under it
# MIDI_PREFS_HOME names the home the preferences are read from (default $HOME); selftest makes its own stand-in home.
set -eu

home=${MIDI_PREFS_HOME:-$HOME}

# The files: the MIDI setup of this host and the saved configurations.
files() {
    root=${1:-$home}
    if [ -d "$root/Library/Preferences/ByHost" ]; then
        find "$root/Library/Preferences/ByHost" -type f -name 'com.apple.MIDI.*.plist' -print
    fi
    if [ -d "$root/Library/Audio/MIDI Configurations" ]; then
        find "$root/Library/Audio/MIDI Configurations" -type f -print
    fi
}

# One line per file: its hash and its path. A file that appears or disappears changes the listing.
listing() {
    files "$1" | LC_ALL=C sort | while IFS= read -r file; do
        printf '%s  %s\n' "$(shasum -a 256 < "$file" | cut -d' ' -f1)" "$file"
    done
}

digest() {
    listing "${1:-$home}" | shasum -a 256 | cut -d' ' -f1
}

# The text of each file, for the report of a difference (a property list is printed as plutil reads it).
texts() {
    files "$1" | LC_ALL=C sort | while IFS= read -r file; do
        printf '== %s\n' "$file"
        plutil -p "$file" 2>/dev/null || cat -v "$file"
    done
}

# The lines of $1 that $2 does not have, and the other way round.
differing_lines() {
    A="$1" B="$2" awk 'BEGIN {
        na = split(ENVIRON["A"], al, "\n"); nb = split(ENVIRON["B"], bl, "\n")
        for (i = 1; i <= na; i++) inA[al[i]] = 1
        for (i = 1; i <= nb; i++) inB[bl[i]] = 1
        for (i = 1; i <= na; i++) if (!(al[i] in inB)) print "  before only: " al[i]
        for (i = 1; i <= nb; i++) if (!(bl[i] in inA)) print "  after only:  " bl[i]
    }'
}

run() {
    before=$(digest)
    before_listing=$(listing "$home")
    before_text=$(texts "$home")
    status=0
    "$@" || status=$?
    after=$(digest)
    if [ "$before" != "$after" ]; then
        echo "prefs-bracket: the persistent MIDI preferences changed during the run (before $before, after $after)" >&2
        differing_lines "$before_listing" "$(listing "$home")" >&2
        differing_lines "$before_text" "$(texts "$home")" >&2
        exit 1
    fi
    echo "prefs-bracket: the persistent MIDI preferences are byte-identical before and after ($after)"
    return "$status"
}

selftest() {
    # The stand-in home is a folder of this checkout's run area, removed as soon as the check has been read.
    area=${MIDI_PREFS_SELFTEST_DIR:-$(cd "$(dirname "$0")/../../../.." && pwd)/.agent-work/runs/prefs-bracket-selftest}
    rm -rf "$area"
    mkdir -p "$area/Library/Preferences/ByHost" "$area/Library/Audio/MIDI Configurations"
    printf 'one\n' > "$area/Library/Preferences/ByHost/com.apple.MIDI.TEST.plist"
    printf 'cfg\n' > "$area/Library/Audio/MIDI Configurations/Setup.plist"
    a=$(digest "$area")
    b=$(digest "$area")
    printf 'two\n' > "$area/Library/Preferences/ByHost/com.apple.MIDI.TEST.plist"
    c=$(digest "$area")
    printf 'cfg\n' > "$area/Library/Audio/MIDI Configurations/Other.plist"
    d=$(digest "$area")
    rm -rf "$area"
    if [ "$a" != "$b" ] || [ "$a" = "$c" ] || [ "$c" = "$d" ]; then
        echo "prefs-bracket: selftest FAILED (same $([ "$a" = "$b" ] && echo yes || echo no), changed file seen $([ "$a" != "$c" ] && echo yes || echo no), new file seen $([ "$c" != "$d" ] && echo yes || echo no))" >&2
        exit 1
    fi
    echo "prefs-bracket: selftest ok (an unchanged tree keeps its digest; a changed and an added file change it)"
}

case "${1:-}" in
    digest) digest ;;
    run) shift; run "$@" ;;
    selftest) selftest ;;
    *) echo "usage: prefs-bracket.sh digest | run <command...> | selftest" >&2; exit 2 ;;
esac
