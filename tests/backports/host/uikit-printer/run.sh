#!/bin/sh
# The port's UIPrinter against Mac Catalyst's own UIPrinter, one source for both sides.
#
# matrix.m is built twice: plain, against the host's UIKit, and with the port's class compiled beside it under a
# CharonHost name (the renames of uikit2/renames.sh), so both live in one process. Each build prints one line per
# measurement, and the two outputs must be equal line for line.
#
# The planted control: the port's reachability answer is forced to YES in a scratch copy of UIPrinter.m. The
# comparison must then go red, or it cannot tell a port that answers wrongly.
#
#   sh tests/backports/host/uikit-printer/run.sh
#
# Not run through heavy.sh: it compiles two files and runs two small binaries; the contact cases wait at most 35 s each.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../../../.." && pwd)
port=$tree/packages/a/apple-backports/UIKit
build=${BUILD:-$tree/.agent-work/runs/printer/run}
sdk=$(xcrun --sdk macosx --show-sdk-path)
ios=$sdk/System/iOSSupport/System/Library/Frameworks
. "$here/../uikit2/renames.sh"
rm -rf "$build"
mkdir -p "$build/host" "$build/port" "$build/plant"

FLAGS="-fobjc-arc -w -target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $ios"
LINK="-F $ios -framework Foundation -framework UIKit"

# the host: matrix.m as it is, against the system's own classes
xcrun clang $FLAGS $LINK "$here/matrix.m" -o "$build/host/matrix" 2> "$build/host/build.log" || {
    echo "the host build did not link:"; sed 's/^/    /' "$build/host/build.log" | head -8; exit 1; }

# the port: its class, compiled plain to learn the names it defines, then renamed beside the system's
xcrun clang $FLAGS -c "$port/UIPrinter.m" -o "$build/port/UIPrinter.plain.o" 2> "$build/port/UIPrinter.plain.log" || {
    echo "the port's UIPrinter.m did not compile:"; sed 's/^/    /' "$build/port/UIPrinter.plain.log" | head -8; exit 1; }
names=$(renames "$build/port/UIPrinter.plain.o")

# builds matrix.m and the port's object with $1 as the port's UIPrinter.m, runs it into $2
renamed() {
    src=$1
    out=$2
    xcrun clang $FLAGS $names -c "$src" -o "$out.printer.o"
    xcrun clang $FLAGS $names -c "$here/matrix.m" -o "$out.matrix.o"
    xcrun clang $FLAGS $LINK "$out.printer.o" "$out.matrix.o" -o "$out.bin" 2> "$out.link.log" || {
        echo "the renamed build did not link:"; sed 's/^/    /' "$out.link.log" | head -8; return 1; }
    "$out.bin" > "$out.txt"
}

renamed "$port/UIPrinter.m" "$build/port/run" || exit 1
"$build/host/matrix" > "$build/host/out.txt"
echo "== host lines: $(grep -c . "$build/host/out.txt"), port lines: $(grep -c . "$build/port/run.txt")"

echo "== the port against the host, line by line"
if diff "$build/host/out.txt" "$build/port/run.txt" > "$build/diff.txt"; then
    echo "SAME: the port's answers equal the host's on every line"
else
    echo "DIFFERENT: $(grep -c '^[<>]' "$build/diff.txt") lines differ; the first ones:"
    head -12 "$build/diff.txt" | sed 's/^/    /'
    exit 1
fi

echo
echo "== the planted control: the reachability answer forced to YES in a scratch copy of the port's UIPrinter.m"
sed 's/reached = (error == 0);/reached = YES;/' "$port/UIPrinter.m" > "$build/plant/UIPrinter.m"
cmp -s "$port/UIPrinter.m" "$build/plant/UIPrinter.m" && {
    echo "PLANT: the sed changed nothing, so the control proves nothing"; exit 1; }
renamed "$build/plant/UIPrinter.m" "$build/plant/run" || exit 1
if diff "$build/host/out.txt" "$build/plant/run.txt" > "$build/plant/diff.txt"; then
    echo "PLANT: the comparison passed a planted port, so it is not discriminating"; exit 1
fi
echo "PLANT: noticed, $(grep -c '^[<>]' "$build/plant/diff.txt") lines differ, the first:"
head -2 "$build/plant/diff.txt" | sed 's/^/    /'
echo
echo "uikit-printer: the port's UIPrinter answers as the host on every measured line; the planted control is red"
