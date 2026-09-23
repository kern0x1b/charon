#!/bin/zsh
# Was hardcoded to a dead Claude session's own per-session /private/tmp scratchpad
# (claude-501/.../priceless-kepler-a7622c/...) -- gone the moment that session's temp dir was
# cleaned, and unlike sel-universe.sh's caches/sel/ this one could NOT be pointed at a known
# durable replacement: as of 2026-09-23 no directory in this workspace holds
# corpus/<app>/extracted/Payload for the 10-app corpus (checked coordination/corpus/ and
# katabasis/targets/ -- katabasis holds a different, older app set entirely: OneBusAway, Zebra,
# iSH, not ish/ppsspp/pojav/provenance/delta/utm/aidoku/yattee/session/telegram). Rather than
# invent a path and fail silently again, this now refuses to run without one named explicitly.
: "${CHARON_SCRATCH_DIR:?set to a directory holding tools/aggregate.py and, per corpus app, corpus/<app>/extracted/Payload/*.app -- no such directory is currently known to exist}"
SP=$CHARON_SCRATCH_DIR
rm -f "$SP/tools/store.json"
for app in ish ppsspp pojav provenance delta utm aidoku yattee session telegram; do
  APP=$(find "$SP/corpus/$app/extracted/Payload" -maxdepth 1 -name '*.app' -type d | head -1)
  [ -n "$APP" ] && python3 "$SP/tools/aggregate.py" ingest "$app" "$APP" 2>&1 | tail -1
done
echo "REINGEST-DONE"
