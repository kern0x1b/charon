#!/bin/sh
# Two processes, one probe, the same script, compared as rendered bytes.
#
# The port's CIImageAccumulator re-implements a class the framework already has, so a process that
# linked both would get the framework's. The port's copy is therefore built here under a name of its
# own and linked beside the framework: the framework's accumulator is in the process and is never
# asked, and the two never touch the same object. The pixel formats and the parameter names come from
# the framework in the port process - the same values the port's own constants carry, over 136 of them
# measured equal to the host's.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
GRAPHICS=${GRAPHICS:-$here/../../../../../packages/a/apple-backports/Graphics}
TOLERANCE=${1:-0.0005}
BUILD=${BUILD:-$(mktemp -d)}
quiet="-Wno-nonnull -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-protocol-method-implementation -Wno-nullability-completeness -Wno-availability -Wno-objc-missing-property-synthesis -Wno-incomplete-implementation"
rm -rf "$BUILD"
mkdir -p "$BUILD/host" "$BUILD/port"
# The port's classes under the names its build gives them; the sed below renames both the sources and
# the header, so the two always agree.
sed -e 's/CIImageAccumulator/CharonCIImageAccumulator/g' -e 's/CharonCharon/Charon/g' "$GRAPHICS/CIImageAccumulator9.m" > "$BUILD/port/CIImageAccumulator.m"
sed -e 's/CIFilterShape/CharonCIFilterShape/g' -e 's/CharonCharon/Charon/g' "$GRAPHICS/CIFilterShape9.m" > "$BUILD/port/CIFilterShape.m"
sed -e 's/\bCIImageAccumulator\b/CharonCIImageAccumulator/g' -e 's/\bCIFilterShape\b/CharonCIFilterShape/g' -e 's/CharonCharon/Charon/g' "$here/port-support.h" > "$BUILD/port/declarations.h"

# The system answers: the probe alone, against the framework the host carries.
xcrun clang -fobjc-arc $quiet "$here/probe.m" -framework CoreImage -framework CoreGraphics -framework ImageIO -framework Foundation -o "$BUILD/host/probe"

# The port answers: the same probe, the port's own accumulator under its own name, and the framework
# for everything the accumulator is built out of.
sed 's/CIImageAccumulator/CharonCIImageAccumulator/g' "$GRAPHICS/CIImageAccumulator9.m" > "$BUILD/port/CIImageAccumulator.m"
xcrun clang -fobjc-arc $quiet -DCHARON_PORT -include "$BUILD/port/declarations.h" -c "$BUILD/port/CIImageAccumulator.m" -o "$BUILD/port/accumulator.o"
xcrun clang -fobjc-arc $quiet -DCHARON_PORT_ACCUMULATOR=1 -include "$BUILD/port/declarations.h" -c "$here/probe.m" -o "$BUILD/port/probe.o"
xcrun clang -fobjc-arc $quiet "$BUILD/port/probe.o" "$BUILD/port/accumulator.o" -framework CoreImage -framework CoreGraphics -framework ImageIO -framework Foundation -o "$BUILD/port/probe"

"$BUILD/host/probe" > "$BUILD/host/answers.txt"
"$BUILD/port/probe" > "$BUILD/port/answers.txt"
python3 "$here/../../modelio/compare.py" "$BUILD/host/answers.txt" "$BUILD/port/answers.txt" "$TOLERANCE" ciimage
status=$?
echo "answers: $BUILD/host/answers.txt $BUILD/port/answers.txt"
exit $status
