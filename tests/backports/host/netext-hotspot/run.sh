#!/bin/sh
# run.sh - NEHotspotNetwork and NEHotspotConfiguration, measured two ways, with a mutant per comparison.
#
#     sh tests/backports/host/netext-hotspot/run.sh [--mutation]
#
# Two binaries, as tests/backports/host/netext-settings/ does: linking the port's classes into the process
# that holds Apple's own would let one implementation shadow the other, and a comparison that cannot say
# which one answered proves nothing. Both are built for Mac Catalyst, because NEHotspotNetwork and
# NEHotspotConfiguration are API_UNAVAILABLE(macos) in the SDK and only the Catalyst image carries them.
#
#   host   the probe alone, with -framework NetworkExtension. Every answer is Apple's; the probe prints a
#          dladdr line naming the image that answered each selector.
#   port   the probe TOGETHER WITH the port's two .m files, with no NetworkExtension linked.
#
# Two things the host cannot give, and what the harness does about each:
#   - the host crashes (SIGSEGV) on -[NEHotspotNetwork SSID] of an object made with alloc/init, so SSID and
#     BSSID of an unmeasured network are asserted on the port alone (nil), not compared;
#   - the fetch's answer on the port is CaptiveNetwork's; here it is compared with the host's, which is nil.
#
# --mutation breaks one answer per comparison in the port's source; each has to go red naming its own line.
# A mutation that does not apply or does not build is RUN FAILED and is never counted as noticed. The text
# is replaced with awk, not python, so the harness needs nothing but the Xcode toolchain.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
S="$root/packages/a/apple-backports"
W="$root/.agent-work/runs/netext-hotspot"
rm -rf "$W"
mkdir -p "$W"
failed=0
compared=0

sdk=$(xcrun --show-sdk-path --sdk macosx)
catalyst="-target arm64-apple-ios15.0-macabi -isysroot $sdk -fobjc-arc -O0 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability -I$S/NetworkExtension"

# replace_once <source> <target> <was> <now>: writes <target> with the one occurrence of <was> replaced.
# Exits non-zero, saying how many occurrences there were, unless <was> occurs exactly once.
replace_once() {
    awk -v was="$3" -v now="$4" '
        { text = text $0 "\n" }
        END {
            count = 0; rest = text
            while ((k = index(rest, was)) > 0) { count++; rest = substr(rest, k + length(was)) }
            if (count != 1) { printf "the text to break appears %d times, not once\n", count > "/dev/stderr"; exit 1 }
            k = index(text, was)
            printf "%s%s%s", substr(text, 1, k - 1), now, substr(text, k + length(was))
        }' "$1" > "$2"
}

echo "=== host: Apple's own answers, and the image that answered"
# shellcheck disable=SC2086
clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" -fobjc-arc -O0 -Wall -DHOST_SIDE=1 \
    "$here/probe.m" -framework NetworkExtension -framework Foundation -o "$W/host" || { echo "FAIL  host does not build"; exit 1; }
# The network op crashes on the host by design (see the header); its output up to the crash is kept.
"$W/host" network > "$W/host-network.txt" 2>&1 || echo "note  host network op exited $? (the SSID read; expected)"
"$W/host" config > "$W/host-config.txt" 2>&1 || echo "note  host config op exited $?"
"$W/host" fetch > "$W/host-fetch.txt" 2>&1 || echo "note  host fetch op exited $?"

echo "=== port: the port's own answers, Apple's framework not linked at all"
# shellcheck disable=SC2086
clang $catalyst "$here/probe.m" "$S/NetworkExtension/NEHotspotNetwork.m" "$S/NetworkExtension/NEHotspotConfiguration.m" \
    -framework Foundation -framework SystemConfiguration -o "$W/port" || { echo "FAIL  port does not build"; exit 1; }
"$W/port" network > "$W/port-network.txt" 2>&1 || echo "FAIL  port network op exited $?"
"$W/port" config > "$W/port-config.txt" 2>&1 || echo "FAIL  port config op exited $?"
"$W/port" fetch > "$W/port-fetch.txt" 2>&1 || echo "FAIL  port fetch op exited $?"

# compare <name> <host-file> <port-file>: both sides must answer the name, and the answers must be equal.
compare() {
    compared=$((compared + 1))
    h=$(grep "^$1	" "$2" | cut -f2)
    p=$(grep "^$1	" "$3" | cut -f2)
    if ! grep -q "^$1	" "$2" || ! grep -q "^$1	" "$3"; then
        echo "FAIL  $1  host='$h' port='$p' (one side did not answer it)"
        failed=$((failed + 1))
    elif [ "$h" = "$p" ]; then
        echo "ok    $1  $h"
    else
        echo "FAIL  $1  host='$h' port='$p'"
        failed=$((failed + 1))
    fi
}

# assert_port <name> <expected> <port-file>: a name the host cannot answer, checked against its value.
assert_port() {
    compared=$((compared + 1))
    got=$(grep "^$1	" "$3" | cut -f2)
    if ! grep -q "^$1	" "$3"; then
        echo "FAIL  $1  expected=$2 got=(no answer)"
        failed=$((failed + 1))
    elif [ "$got" = "$2" ]; then
        echo "ok    $1  $got  (port-only: the host crashes on it)"
    else
        echo "FAIL  $1  expected=$2 got=$got"
        failed=$((failed + 1))
    fi
}

# dladdr <name> <expected-image> <file>: which image answered the selector.
dladdr_is() {
    compared=$((compared + 1))
    got=$(grep "^dladdr	$1	" "$3" | cut -f3)
    if [ "$got" = "$2" ]; then
        echo "ok    dladdr.$1  $got"
    else
        echo "FAIL  dladdr.$1  expected=$2 got=$got"
        failed=$((failed + 1))
    fi
}

echo "=== NEHotspotNetwork: the defaults of an object the system did not fill in"
for name in network.class network.securityType network.signalStrength network.isSecure \
            network.didAutoJoin network.didJustJoin network.isChosenHelper network.setters; do
    compare "$name" "$W/host-network.txt" "$W/port-network.txt"
done
assert_port network.SSID "(nil)" "$W/port-network.txt"
assert_port network.BSSID "(nil)" "$W/port-network.txt"

echo "=== NEHotspotNetwork: fetchCurrent, on the main thread, once, after the call returned"
for name in fetch.calls fetch.network fetch.onMainThread fetch.beforeReturn; do
    compare "$name" "$W/host-fetch.txt" "$W/port-fetch.txt"
done
dladdr_is fetchCurrent NetworkExtension "$W/host-fetch.txt"
dladdr_is fetchCurrent port "$W/port-fetch.txt"

echo "=== NEHotspotConfiguration: defaults, setters, copy and the keyed archive"
for name in config.SSID config.SSIDPrefix config.hidden config.joinOnce config.lifeTimeInDays \
            prefix.SSID prefix.SSIDPrefix wep.SSID set.joinOnce set.hidden set.lifeTimeInDays \
            copy.isSameObject copy.class copy.joinOnce copy.hidden copy.lifeTimeInDays \
            archive.hasData archive.error roundTrip.class roundTrip.SSID roundTrip.joinOnce \
            roundTrip.hidden roundTrip.lifeTimeInDays; do
    compare "$name" "$W/host-config.txt" "$W/port-config.txt"
done
dladdr_is initWithSSID NetworkExtension "$W/host-config.txt"
dladdr_is initWithSSID port "$W/port-config.txt"

echo "compared=$compared failed=$failed"
[ "$failed" -eq 0 ] || exit 1

if [ "${1:-}" = "--mutation" ]; then
    echo "=== one mutation per comparison: each must go red naming itself"
    mutations=0
    failed=0
    # name | file | the text to break | what replaces it
    set -- \
      "config.SSIDPrefix|NEHotspotConfiguration.m|_SSIDPrefix = @\"\";|_SSIDPrefix = nil;" \
      "set.hidden|NEHotspotConfiguration.m|_hidden = hidden;|_hidden = !hidden;" \
      "copy.joinOnce|NEHotspotConfiguration.m|copy->_joinOnce = _joinOnce;|copy->_joinOnce = NO;" \
      "copy.lifeTimeInDays|NEHotspotConfiguration.m|copy->_lifeTimeInDays = [_lifeTimeInDays copy];|copy->_lifeTimeInDays = nil;" \
      "roundTrip.hidden|NEHotspotConfiguration.m|_hidden = [coder decodeBoolForKey:@\"hidden\"];|_hidden = NO;" \
      "fetch.onMainThread|NEHotspotNetwork.m|dispatch_async(dispatch_get_main_queue(), ^{|dispatch_async(dispatch_get_global_queue(0, 0), ^{"
    for mutation in "$@"; do
        name=$(printf '%s' "$mutation" | cut -d'|' -f1)
        file=$(printf '%s' "$mutation" | cut -d'|' -f2)
        was=$(printf '%s' "$mutation" | cut -d'|' -f3)
        now=$(printf '%s' "$mutation" | cut -d'|' -f4)
        mdir="$W/mutant-$name"
        mkdir -p "$mdir"
        cp "$S/NetworkExtension/NEHotspotNetwork.m" "$S/NetworkExtension/NEHotspotConfiguration.m" "$mdir/"
        if ! replace_once "$S/NetworkExtension/$file" "$mdir/$file" "$was" "$now"; then
            echo "RUN FAILED $name: the mutation did not apply to the port's source" >&2
            failed=$((failed + 1))
            continue
        fi
        other=NEHotspotNetwork.m
        [ "$file" = NEHotspotNetwork.m ] && other=NEHotspotConfiguration.m
        # shellcheck disable=SC2086
        if ! clang $catalyst "$here/probe.m" "$mdir/$file" "$mdir/$other" -framework Foundation -framework SystemConfiguration \
                -o "$mdir/port" > "$mdir/build.txt" 2>&1; then
            echo "RUN FAILED $name: the mutant does not build (see $mdir/build.txt)" >&2
            failed=$((failed + 1))
            continue
        fi
        "$mdir/port" network > "$mdir/network.txt" 2>&1 || echo "note  mutant exited $? (its output is compared)"
        "$mdir/port" config > "$mdir/config.txt" 2>&1 || echo "note  mutant exited $? (its output is compared)"
        "$mdir/port" fetch > "$mdir/fetch.txt" 2>&1 || echo "note  mutant exited $? (its output is compared)"
        if cmp -s "$mdir/config.txt" "$W/port-config.txt" && cmp -s "$mdir/fetch.txt" "$W/port-fetch.txt"; then
            echo "NOT NOTICED $name: the mutant answered exactly as the port does" >&2
            failed=$((failed + 1))
        else
            if ! cmp -s "$mdir/config.txt" "$W/port-config.txt"; then
                first=$(diff "$W/port-config.txt" "$mdir/config.txt" | grep '^[<>]' | head -1 | cut -c1-90)
            else
                first=$(diff "$W/port-fetch.txt" "$mdir/fetch.txt" | grep '^[<>]' | head -1 | cut -c1-90)
            fi
            echo "noticed $name: $first"
            mutations=$((mutations + 1))
        fi
    done
    echo "mutations noticed: $mutations, failures: $failed"
    [ "$failed" -eq 0 ] || exit 1
fi
