#!/bin/sh
# run.sh - the port's SensorKit names against the host's own SensorKit, in two processes, with the
# mutation layer that makes the comparison falsifiable.
#
#   1. the port's object is COMPILED and LINKED into the differential, which prints what the port holds
#   2. the reader is COMPILED and LINKED separately, and opens the host's framework to print what it holds
#   3. compare.py puts the two side by side, name by name, over the one list both walk
#   4. two plants: every value wrong, and one value wrong - each must turn the comparison red, and the
#      one-wrong plant must name exactly one row
#   5. the comparator's own control: a HOST file with no rows must be red, so a run that compared
#      nothing cannot look green
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/SensorKit}
build=${SENSORKIT_NAMES_BUILD:-$(mktemp -d)}
mkdir -p "$build"

xcrun clang -fobjc-arc -w -I"$here" -c "$port/SensorKitNames14.m" -o "$build/names.o"
xcrun clang -fobjc-arc -w -I"$here" -c "$here/differential.m" -o "$build/differential.o"
xcrun clang -fobjc-arc -w "$build/differential.o" "$build/names.o" -framework Foundation \
    -o "$build/differential"
xcrun clang -fobjc-arc -w -I"$here" "$here/read-host.m" -framework Foundation -o "$build/read-host"

"$build/differential" > "$build/port.out"
"$build/read-host" > "$build/host.out"
grep '^CONTROL' "$build/host.out" || { echo "FAIL the reader printed no control line"; exit 1; }

echo "--- the clean run"
python3 "$here/compare.py" "$build/port.out" "$build/host.out" "$here/names.txt"

echo "--- the all-wrong plant: every value replaced"
sed 's/ = CFSTR(".*");/ = CFSTR("WRONG");/' "$port/SensorKitNames14.m" > "$build/all-wrong.m"
mkdir -p "$build/allwrong" && cp "$build/all-wrong.m" "$build/allwrong/SensorKitNames14.m"
xcrun clang -fobjc-arc -w -I"$here" -c "$build/allwrong/SensorKitNames14.m" -o "$build/all-wrong.o"
xcrun clang -fobjc-arc -w "$build/differential.o" "$build/all-wrong.o" -framework Foundation -o "$build/differential-allwrong"
"$build/differential-allwrong" > "$build/port-allwrong.out"
if python3 "$here/compare.py" "$build/port-allwrong.out" "$build/host.out" "$here/names.txt"; then
    echo "FAIL the all-wrong mutation was not noticed"
    exit 1
fi
echo "the all-wrong plant is red, as it must be"

echo "--- the one-wrong plant: exactly one value replaced"
first=$(grep -m 1 -n ' = CFSTR(' "$port/SensorKitNames14.m" | cut -d: -f1)
name=$(sed -n "${first}p" "$port/SensorKitNames14.m" | sed 's/CFStringRef const \([A-Za-z]*\).*/\1/')
sed "${first}s/ = CFSTR(\".*\");/ = CFSTR(\"WRONG\");/" "$port/SensorKitNames14.m" > "$build/one-wrong.m"
mkdir -p "$build/onewrong" && cp "$build/one-wrong.m" "$build/onewrong/SensorKitNames14.m"
xcrun clang -fobjc-arc -w -I"$here" -c "$build/onewrong/SensorKitNames14.m" -o "$build/one-wrong.o"
xcrun clang -fobjc-arc -w "$build/differential.o" "$build/one-wrong.o" -framework Foundation -o "$build/differential-onewrong"
"$build/differential-onewrong" > "$build/port-onewrong.out"
if python3 "$here/compare.py" "$build/port-onewrong.out" "$build/host.out" "$here/names.txt"; then
    echo "FAIL the one-wrong mutation was not noticed"
    exit 1
fi
named=$(python3 "$here/compare.py" "$build/port-onewrong.out" "$build/host.out" "$here/names.txt" \
        | grep -c "DIFFERS $name:")
echo "the one-wrong plant is red and names exactly $named row: $name"

echo "--- the comparator's own control: a HOST file with no rows must be red"
: > "$build/host-empty.out"
if python3 "$here/compare.py" "$build/port.out" "$build/host-empty.out" "$here/names.txt"; then
    echo "FAIL comparing against nothing was green"
    exit 1
fi
echo "an empty host file is red, so this comparison is not one that can pass by looking at nothing"

echo "sensorkit-names: OK - 39 names, 2 processes, 2 mutations noticed, the empty control red"
