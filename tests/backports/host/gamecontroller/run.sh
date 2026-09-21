#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/GameController}
out=${BUILD:-$(mktemp -d)}
renames=""
for name in GCController GCControllerElement GCControllerButtonInput GCControllerAxisInput GCControllerDirectionPad GCGamepad GCExtendedGamepad GCMicroGamepad GCPhysicalInputProfile GCMotion; do
    renames="$renames -D$name=CharonHost$name"
done
objects=""
for source in GCElements7 GCPhysicalInputProfile14 GCGamepads7 GCMicroGamepad9 GCMotion8 GCController CharonGCTables; do
    xcrun clang -fobjc-arc -w $renames -I"$port" -c "$port/$source.m" -o "$out/$source.o"
    objects="$objects $out/$source.o"
done
xcrun clang -fobjc-arc -w -framework Foundation -framework GameController "$here/differential.m" $objects -o "$out/differential"
"$out/differential"
