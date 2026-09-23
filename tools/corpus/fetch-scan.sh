#!/bin/zsh
# fetch-scan.sh <app-name> <ipa-url>
# Download IPA -> extract -> verify arch/cryptid of main -> scan demand -> DELETE ipa.
# Keeps the extracted .app (for Katabasis handoff); deletes only the .ipa.
set -e
NAME="$1"; URL="$2"
SP="${0:A:h:h}"
# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location -- SP alone broke silently the moment this script
# moved from coordination/corpus-tools/ to charon/tools/corpus/ (2026-09-23). See
# tools/corpus/README.md.
CORPUS_ROOT="${CHARON_CORPUS_ROOT:-$HOME/Git/projects/ios/coordination}"
[ -d "$CORPUS_ROOT/corpus" ] || { echo "fetch-scan.sh: no corpus/ data directory found at $CORPUS_ROOT/corpus. Set CHARON_CORPUS_ROOT."; exit 1; }
DIR="$CORPUS_ROOT/corpus/$NAME"
mkdir -p "$DIR"
echo "[$NAME] disk before: $(df -h "$SP" | awk 'NR==2{print $4" free"}')"
curl -sL --max-time 900 -o "$DIR/app.ipa" "$URL"
echo "[$NAME] downloaded $(du -h "$DIR/app.ipa" | cut -f1)"
rm -rf "$DIR/extracted"
unzip -q -o "$DIR/app.ipa" -d "$DIR/extracted"
APP=$(find "$DIR/extracted/Payload" -maxdepth 1 -name '*.app' -type d | head -1)
[ -n "$APP" ] || { echo "no .app found"; exit 1; }
MAIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
echo "[$NAME] main: $(file "$MAIN" | sed 's#.*: ##')  cryptid: $(otool -l "$MAIN" | awk '/cryptid/{print $2; exit}')"
rm -f "$DIR/app.ipa"                       # disk discipline: drop the big compressed file now
echo "[$NAME] ipa deleted; disk now: $(df -h "$SP" | awk 'NR==2{print $4" free"}')"
# aggregate.py is a NEIGHBOR SCRIPT, found beside this file wherever it is copied to
# (${0:A:h}); CHARON_TOOLS_DIR overrides for a one-off run from an unusual layout.
TOOLS="${CHARON_TOOLS_DIR:-}"
if [ -z "$TOOLS" ] || [ ! -f "$TOOLS/aggregate.py" ]; then
  for c in "${0:A:h}"; do
    if [ -f "$c/aggregate.py" ]; then TOOLS="$c"; break; fi
  done
fi
[ -n "$TOOLS" ] || { echo "fetch-scan.sh: no aggregate.py found. Set CHARON_TOOLS_DIR."; exit 1; }
python3 "$TOOLS/aggregate.py" ingest "$NAME" "$APP"
python3 "$TOOLS/scan-selectors.py" "$NAME" "$APP"
