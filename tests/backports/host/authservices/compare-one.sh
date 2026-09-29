#!/bin/sh
# compare-one.sh -- the host's and the port's ARGUMENT TYPES for one method, and whether they agree.
#
# The step that proved the reading works, kept as a script because it is the shortest statement of the
# rule: both sides are digit-stripped, because the host is arm64 and the port's objects are armv7 and
# the frame sizes and offsets differ with the pointer width, and a completion typed as a block is '@?'
# where the same completion typed as a SEL is '@:'. Comparing the letters alone drops the ':' and makes
# those two look alike, which is the one difference that has to be seen.
#
#   compare-one.sh <object> <class> <selector> [--library <dylib>]
#
# The object is one of the port's armv7 objects; the library is the port's built dylib when it is being
# compared whole rather than method by method.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
framework=${AS_FRAMEWORK:-/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices}
library=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --library) library=$2; shift 2 ;;
        *) break ;;
    esac
done
[ "$#" -eq 3 ] || { echo "usage: compare-one.sh <object> <class> <selector> [--library <dylib>]" >&2; exit 2; }
object=$1; className=$2; selectorName=$3
[ -n "$library" ] || library="$object"

build=${BUILD:-$(mktemp -d)}
cc -O2 -Wno-unused-parameter -o "$build/hostshape" "$here/hostshape.c" -framework Foundation

host=$("$build/hostshape" "$framework" "$className" "$selectorName" | sed 's/.*types \([^ ]*\) raw.*/\1/')
port=$(python3 "$here/portshape.py" "$library" "$className" "$selectorName" | sed 's/.*types //')
echo "  host   $host"
echo "  port   $port"
if [ "$host" != "$port" ]; then
    echo "  FAIL: the two disagree on the types of -$selectorName"
    exit 1
fi
echo "  ok: the two agree on the types of -$selectorName"
