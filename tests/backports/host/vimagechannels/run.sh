#!/bin/sh
# The port's channel moves held against the host's own vImage, case by case: the same channels in, the same
# channels out, every byte of every destination row compared including the bytes neither side may write.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ACCELERATE=$here/../../../../packages/a/apple-backports/Accelerate
REGISTRY=$here/../../../../packages/a/apple-backports/registry/Accelerate
build=${VIMAGECHANNELS_BUILD:-${TMPDIR:-/tmp}/charon-vimagechannels-host}
rm -rf "$build"
mkdir -p "$build"

# Every API name the objects define is renamed in the port's own translation units, so this one can hold the
# port's answers and the host's side by side. The names come from the port's registry, not from a list kept
# here, so a name added to the library is renamed too.
names=$(python3 -c "
import json, sys
for part in sys.argv[1:]:
    for entry in json.load(open(part))['entries']:
        if entry['kind'] == 'function':
            print(entry['api'].rstrip('()'))
" "$REGISTRY/ios7channels.json" "$REGISTRY/ios8channels.json" "$REGISTRY/ios16channels.json")

renames=""
for name in $names; do
    renames="$renames -D$name=charon_host_$name"
done

objects=""
for source in vImageChannels7.m vImageChannels8.m vImageChannels16.m; do
    xcrun clang -fobjc-arc -w $renames -I"$ACCELERATE" -c "$ACCELERATE/$source" -o "$build/$(basename "$source").o"
    objects="$objects $build/$(basename "$source").o"
done

xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations \
    "$here/differential.m" $objects \
    -framework Foundation -framework Accelerate -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result