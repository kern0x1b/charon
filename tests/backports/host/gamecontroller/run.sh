#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/GameController}
out=${BUILD:-$(mktemp -d)}
renames=""
for name in GCController GCControllerElement GCControllerButtonInput GCControllerAxisInput GCControllerDirectionPad GCGamepad GCExtendedGamepad GCMicroGamepad GCPhysicalInputProfile GCMotion GCGamepadSnapshot GCExtendedGamepadSnapshot GCMicroGamepadSnapshot; do
    renames="$renames -D$name=CharonHost$name"
done
# the ten snapshot functions and the two version constants, so both copies link side by side
for name in GCGamepadSnapShotDataV100FromNSData NSDataFromGCGamepadSnapShotDataV100 \
            GCExtendedGamepadSnapShotDataV100FromNSData NSDataFromGCExtendedGamepadSnapShotDataV100 \
            GCExtendedGamepadSnapshotDataFromNSData NSDataFromGCExtendedGamepadSnapshotData \
            GCMicroGamepadSnapShotDataV100FromNSData NSDataFromGCMicroGamepadSnapShotDataV100 \
            GCMicroGamepadSnapshotDataFromNSData NSDataFromGCMicroGamepadSnapshotData \
            GCCurrentExtendedGamepadSnapshotDataVersion GCCurrentMicroGamepadSnapshotDataVersion; do
    renames="$renames -D$name=charonHost_$name"
done
objects=""
for source in GCElements7 GCPhysicalInputProfile14 GCGamepads7 GCMicroGamepad9 GCMotion8 GCController CharonGCTables GCSnapshots7 GCSnapshots9 GCSnapshots16; do
    xcrun clang -fobjc-arc -w $renames -I"$port" -c "$port/$source.m" -o "$out/$source.o"
    objects="$objects $out/$source.o"
done
xcrun clang -fobjc-arc -w -framework Foundation -framework GameController "$here/differential.m" $objects -o "$out/differential"
"$out/differential"
