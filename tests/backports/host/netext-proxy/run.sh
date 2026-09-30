#!/bin/sh
# run.sh — the proxy and IPv4 settings objects, compared against Apple's own answers in two binaries.
#
#     sh tests/backports/host/netext-proxy/run.sh [--mutation]
#
# Same shape as the NEDNSSettings differential, for a reason that is now measured rather than assumed:
# all twenty-three property names of these four classes are carried by the host's own
# NetworkExtension, so none of them falls back to the header oracle.
#
#   host   the probe alone with -framework NetworkExtension: every answer Apple's, and a dladdr line per
#          class naming the image that answered.
#   port   the probe together with the port's two objects, built for the same Mac Catalyst target, with
#          Apple's framework not linked: every answer the port's.
#
# --mutation breaks one answer per comparison in the port's own source; each has to go red naming its
# comparison, and a mutation that does not build is RUN FAILED, never counted as noticed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
S="$root/packages/a/apple-backports"
W=${WORK:-$root/.agent-work/runs/netext-proxy}
W=${W%./*}/$(basename "$W")
rm -rf "$W"
mkdir -p "$W"

sdk=$(xcrun --show-sdk-path --sdk macosx)
port="-target arm64-apple-ios15.0-macabi -isysroot $sdk -fobjc-arc -O0 -Wall -Wno-unguarded-availability-new -I$S/NetworkExtension"

echo "=== host: Apple's own answers, and the image that answered"
# shellcheck disable=SC2086
clang -fobjc-arc -O0 -Wall -Wno-unguarded-availability-new -DHOST_SIDE=1 \
    "$here/probe.m" -framework NetworkExtension -framework Foundation -o "$W/host"
"$W/host" | tee "$W/host.txt"

echo "=== port: the port's own answers, Apple's framework not linked at all"
# shellcheck disable=SC2086
clang $port "$here/probe.m" "$S/NetworkExtension/NEProxySettings.m" "$S/NetworkExtension/NEIPv4Settings.m" \
    -framework Foundation -o "$W/port"
"$W/port" | tee "$W/port.txt"

echo "=== compared, name by name"
compared=0
failed=0
NAMES="NEProxyServer.dladdr NEProxySettings.dladdr NEIPv4Settings.dladdr NEIPv4Route.dladdr NEProxyServer.username NEProxyServer.password NEProxyServer.authenticationRequired NEProxySettings.autoProxyConfigurationEnabled NEProxySettings.proxyAutoConfigurationURL NEProxySettings.proxyAutoConfigurationJavaScript NEProxySettings.HTTPEnabled NEProxySettings.HTTPServer NEProxySettings.HTTPSEnabled NEProxySettings.HTTPSServer NEProxySettings.excludeSimpleHostnames NEProxySettings.exceptionList NEProxySettings.matchDomains NEIPv4Settings.addresses NEIPv4Settings.subnetMasks NEIPv4Settings.router NEIPv4Settings.includedRoutes NEIPv4Settings.excludedRoutes NEIPv4Route.destinationAddress NEIPv4Route.destinationSubnetMask NEIPv4Route.gatewayAddress roundTrip.HTTPEnabled roundTrip.exceptionList copy.isSameObject archive.hasData archive.errorDomain"
for name in $NAMES; do
    h=$(grep "^$name	" "$W/host.txt" | cut -f2 || true)
    p=$(grep "^$name	" "$W/port.txt" | cut -f2 || true)
    case "$name" in
        *.dladdr)
            # a proof line is not a comparison: the two sides must name DIFFERENT implementations, or
            # one of them is answering for both. That is the whole point of the two binaries.
            compared=$((compared + 1))
            if [ -z "$h" ] || [ -z "$p" ]; then
                echo "FAIL  $name  the proof is empty: host='$h' port='$p'"
                failed=$((failed + 1))
            elif [ "$h" = "$p" ]; then
                echo "FAIL  $name  both sides name '$h': one implementation is answering for both"
                failed=$((failed + 1))
            else
                echo "ok    $name  host='$h' port='$p' (different implementations, as it must be)"
            fi
            ;;
        *)
            compared=$((compared + 1))
            if [ -z "$h" ] || [ -z "$p" ]; then
                echo "FAIL  $name  host='$h' port='$p' (one side did not answer it)"
                failed=$((failed + 1))
            elif [ "$h" = "$p" ]; then
                echo "ok    $name  $h"
            else
                echo "FAIL  $name  host='$h' port='$p'"
                failed=$((failed + 1))
            fi
            ;;
    esac
done
echo "compared=$compared failed=$failed"
[ "$failed" -eq 0 ] || exit 1

if [ "${1:-}" = "--mutation" ]; then
    echo "=== one mutation per comparison: each must go red naming itself"
    failed=0
    set -- "NEProxyServer.username|_username = [username copy];|_username = @[@\"planted\"];" "roundTrip.exceptionList|_exceptionList = [list copy];|_exceptionList = @[@\"planted\"];" "NEProxySettings.HTTPEnabled|_httpEnabled = flag;|_httpEnabled = !flag;" "copy.isSameObject|    NEProxySettings *copy = [[NEProxySettings allocWithZone:zone] init];|    NEProxySettings *copy = (NEProxySettings *)self; (void)zone;"
    for mutation in "$@"; do
        name=$(printf '%s' "$mutation" | cut -d'|' -f1)
        was=$(printf '%s' "$mutation" | cut -d'|' -f2)
        now=$(printf '%s' "$mutation" | cut -d'|' -f3)
        mutant="$W/mutant-$name.m"
        found=0
        for source in "$S/NetworkExtension/NEProxySettings.m" "$S/NetworkExtension/NEIPv4Settings.m"; do
            if grep -qF "$was" "$source"; then
                python3 - "$source" "$mutant" "$was" "$now" <<'PYEOF'
import sys
source, target, was, now = sys.argv[1:5]
text = open(source).read()
if text.count(was) != 1:
    raise SystemExit("the text to break appears %d times, not once" % text.count(was))
open(target, "w").write(text.replace(was, now, 1))
PYEOF
                found=1
                break
            fi
        done
        if [ "$found" -eq 0 ]; then
            echo "RUN FAILED $name: the mutation did not apply to any of the port's sources" >&2
            failed=$((failed + 1))
            continue
        fi
        # shellcheck disable=SC2086
        if ! clang $port "$here/probe.m" "$mutant" "$S/NetworkExtension/NEIPv4Settings.m" \
             -framework Foundation -o "$W/mutant-$name" > "$W/mutant-$name.build" 2>&1; then
            echo "RUN FAILED $name: the mutant does not build (see $W/mutant-$name.build)" >&2
            failed=$((failed + 1))
            continue
        fi
        "$W/mutant-$name" > "$W/mutant-$name.txt" 2>&1 || true
        if diff -q "$W/mutant-$name.txt" "$W/port.txt" >/dev/null 2>&1; then
            echo "NOT NOTICED $name: the mutant answered exactly as the port does" >&2
            failed=$((failed + 1))
        else
            echo "noticed $name: $(diff "$W/port.txt" "$W/mutant-$name.txt" | grep '^[<>]' | head -1 | cut -c1-88)"
        fi
    done
    echo "mutations: 4, failures: $failed"
    [ "$failed" -eq 0 ] || exit 1
fi
echo "PASS: the port's answers agree with Apple's, name by name"
