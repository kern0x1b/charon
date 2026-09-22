#!/bin/sh
# Not a differential: there is no host JSContext to hold the backport to, since the contract is
# the header's own, not a running release's behaviour, and the classes carry names the host's own
# JavaScriptCore.framework also exports. Renamed at compile time so this can link against a real
# JSGlobalContextRef, JSEvaluateScript and the rest of the C API without the two colliding.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/JavaScriptCore}
out=${BUILD:-$(mktemp -d)}
renames=""
for name in JSContext JSValue JSManagedValue JSVirtualMachine; do
    renames="$renames -D$name=CharonHost$name"
done
objects=""
for source in JSVirtualMachine JSContext JSValue JSManagedValue JSExportBridge; do
    xcrun clang -fobjc-arc -w $renames -I"$port" -c "$port/$source.m" -o "$out/$source.o"
    objects="$objects $out/$source.o"
done
xcrun clang -fobjc-arc -w -framework Foundation -framework JavaScriptCore -framework CoreGraphics $renames "$here/checks.m" $objects -o "$out/checks"
"$out/checks"
