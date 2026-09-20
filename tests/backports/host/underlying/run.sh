#!/bin/sh
# run.sh — runs the scheduler of the operation queue of the port beside the system's queue over the same cases, and writes what the
# system answered where the device test reads it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
DEVICE=${DEVICE:-$here/../../device}
BUILD=${BUILD:-$(mktemp -d)}
xcrun clang -fobjc-arc -fvisibility=hidden -w -DCharonOperationScheduler=CharonHostCharonOperationScheduler -c "$FOUNDATION/CharonOperationScheduler.m" -o "$BUILD/scheduler.o"
xcrun clang -fobjc-arc -w -I"$DEVICE" -I"$FOUNDATION" "$here/differential.m" "$DEVICE/underlying-cases.m" "$DEVICE/check.m" "$BUILD/scheduler.o" -framework Foundation -o "$BUILD/differential"
"$BUILD/differential" "$BUILD/underlying.json"
python3 "$here/../foundation2/embed.py" "$BUILD/underlying.json" "$DEVICE/underlying-expectations.h"
sed -i.bak 's/foundation2_expectations/underlying_expectations/' "$DEVICE/underlying-expectations.h" && rm -f "$DEVICE/underlying-expectations.h.bak"
