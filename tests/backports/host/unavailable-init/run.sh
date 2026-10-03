#!/bin/sh
# run.sh - the -init and +new that the SDK 26.2 headers of these frameworks close with NS_UNAVAILABLE,
# held to what Apple's own class was measured to do about them.
#
#   1. probe.m asks the host's own framework, one class per process: is the selector in the class's OWN
#      method list (the corpus row's question), and what does a caller reach at run time (the behaviour).
#      One process per class because a class's -init can hang or crash the host - measured: three
#      PassKit classes die with SIGSEGV when initialised directly - and a probe that stopped at the first
#      of those would answer one class and call it a measurement.
#   2. check_host.py holds that against expectations.tsv, per framework, for the rows whose oracle is the
#      host. A difference means the oracle moved, which is the one thing the table exists to notice.
#   3. check_port.py holds the PORT to the same table, per framework: where Apple's class implements the
#      selector, the class's @implementation block must raise what was measured with the reason that was
#      measured, and the compiled armv7 object must carry the two selectors; where Apple's class carries
#      NEITHER, the block must not define them and the object must not carry them, because a definition
#      would put the selector in the port's metadata where Apple's has none and answer the same thing.
#   4. the plants, each of which must turn step 3 red, and the check's own control.
#
# A framework with no binary on this host (HomeKit has none: /System/Library/Frameworks/HomeKit.framework
# holds only PlugIns) has no host half, and its rows carry `ios16` as their oracle - read out of the arm64e
# cache of iOS 16.0 with tools/corpus/objc-inventory.lua, which is a real release's own metadata. That
# answers the row's question and not the behaviour, so the rows of that framework name what they carry.
#
# WHY A HOST ORACLE AND NOT A DEVICE. The port's own configuration is a cross-compile for
# armv7-apple-ios6.1.3, which cannot be run on this machine, and the host carries HealthKit, PassKit and
# SensorKit with the classes implemented, so the host answers the pair where a device would. What the host
# is NOT is a measurement of iOS, and where the two can be compared they are compared: the cache of iOS
# 16.0 carries SRSensorReader and SRFetchResult, and it agrees with the host on both questions for both.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
charon=$(cd "$charon" && pwd)
appledir="$charon/packages/a/apple-backports"
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"

cc=$(ls -d "$HOME"/.xmake/packages/l/llvm/*/*/bin/clang 2>/dev/null | head -1)
sdk=$(cat /tmp/land/sdkpath 2>/dev/null || ls -d "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/iPhoneOS16.4.sdk | head -1)
if [ -z "$cc" ] || [ -z "$sdk" ]; then
    echo "FAIL no pinned toolchain: expected clang under \$HOME/.xmake/packages/l/llvm/*/*/bin and the"
    echo "     iPhoneOS 16.4 SDK the port builds against (BP_SDK, or /tmp/land/sdkpath)."
    exit 1
fi

# The frameworks to run, the classes, and the sources and objects to check, are the table's rows - not a
# list written twice. A framework named on the command line wins over the table's own set.
python3 - "$here/expectations.tsv" "$build" ${1+"$@"} <<'PY'
import sys
table, outdir = sys.argv[1], sys.argv[2]
asked = sys.argv[3:]
header, rows = None, []
for line in open(table, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    fields = line.rstrip("\n").split("\t")
    if header is None:
        header = fields
        continue
    rows.append(dict(zip(header, fields)))
frameworks = asked or sorted({r["framework"] for r in rows})
for name in frameworks:
    mine = [r for r in rows if r["framework"] == name]
    with open("%s/%s.classes" % (outdir, name), "w") as handle:
        handle.write("".join(r["class"] + "\n" for r in mine))
    with open("%s/%s.sources" % (outdir, name), "w") as handle:
        handle.write("".join(r["port-source"] + "\n" for r in mine))
    with open("%s/%s.objects" % (outdir, name), "w") as handle:
        handle.write("".join(r["port-object"] + "\n" for r in mine))
open("%s/frameworks" % outdir, "w").write("".join(name + "\n" for name in frameworks))
PY

echo "--- the host's own frameworks, one class per process, and the table each is held to"
survived=0
xcrun clang -fobjc-arc -w "$here/probe.m" -framework Foundation -o "$build/probe"
for framework in $(cat "$build/frameworks"); do
    # No test on the path first, on purpose: this OS ships these frameworks out of the dyld shared
    # cache and there is no file under the path at all (measured 2026-10-03: SensorKit.framework holds
    # Versions and two dangling symlinks, HealthKit's binary is a symlink to a Versions/Current that is
    # not there, and dlopen of both succeeds). dlopen is the question, so the probe answers it, and
    # check_host.py says whether a framework that cannot be opened leaves rows unchecked.
    binary="/System/Library/Frameworks/$framework.framework/$framework"
    : > "$build/$framework.host"
    while read -r class; do
        [ -n "$class" ] || continue
        if ! echo "$class" | timeout 10 "$build/probe" "$binary" > "$build/one.out" 2>&1; then
            echo "CLASS $class did not survive the host (exit $?): Apple's own class, asked directly"
        fi
        cat "$build/one.out" >> "$build/$framework.host"
    done < "$build/$framework.classes"
    python3 "$here/check_host.py" "$framework" "$build/$framework.host"
done

echo "--- the port: the source, the macro's own body, and the compiled armv7 objects"
for framework in $(cat "$build/frameworks"); do
    mkdir -p "$build/objects/$framework"
    for source in $(sort -u "$build/$framework.sources"); do
        object="$build/objects/$framework/$(basename "$source").o"
        "$cc" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -I "$appledir" \
            -I "$appledir/$framework" -fobjc-arc -c "$appledir/$source" -o "$object" \
            > "$build/cc.log" 2>&1 ||
            { echo "COMPILE FAILED for $source:"; cat "$build/cc.log"; exit 1; }
    done
    python3 "$here/check_port.py" "$appledir" "$build/objects/$framework" "$charon" "$framework"
done

# A plant is the port's own tree with one line changed, compiled and asked again. The framework, the
# file and the needle come from the table so that a plant always applies to a row that exists.
plant() {
    label=$1; framework=$2; file=$3; from=$4; to=$5
    : > "$build/mutant-cc.log"
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant/$framework"
    for header in CharonValueStore.h CharonHKStore.h CharonHKTypes.h CharonHAPBignum.h \
                  CharonHapCrypto.h CharonHomeKitConstants.h CharonHomeKitConstruction.h \
                  CharonHomeKitInternal.h CharonHomeKitModel.h CharonHomeKitProtocols.h \
                  CharonHomeKitStore.h CharonPassKit.h CharonPassKitStandin.h CharonSensorKit.h; do
        [ -f "$appledir/$header" ] && cp "$appledir/$header" "$build/mutant/$header"
    done
    for header in CharonHKStore.h CharonHKTypes.h CharonSensorKit.h CharonSensorKitNames.h \
                  CharonSensorKitProtocols.h CharonSensorKitValue.h CharonHomeKitInternal.h \
                  CharonHomeKitModel.h CharonHomeKitProtocols.h CharonHomeKitStore.h; do
        [ -f "$appledir/$framework/$header" ] && cp "$appledir/$framework/$header" "$build/mutant/$framework/$header"
    done
    for source in $(sort -u "$build/$framework.sources"); do cp "$appledir/$source" "$build/mutant/$framework/"; done
    target="$build/mutant/$framework/$file"
    if ! python3 - "$target" "$from" "$to" <<'PY'
import sys
path, needle, replacement = sys.argv[1:4]
# plants.py writes a newline as the two characters \n so that one plant is one line of its output.
replacement = replacement.replace("\\n", "\n")
text = open(path, encoding="utf-8").read()
if needle not in text:
    sys.exit(1)
open(path, "w", encoding="utf-8").write(text.replace(needle, replacement, 1))
PY
    then
        echo "MUTATION DID NOT APPLY: $label"
        survived=$((survived + 1))
        return
    fi
    built=$build/mutant/objects
    mkdir -p "$built"
    ok=1
    for source in $(sort -u "$build/$framework.sources"); do
        "$cc" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -I "$build/mutant" \
            -I "$build/mutant/$framework" -fobjc-arc -c "$build/mutant/$framework/$(basename "$source")" \
            -o "$built/$(basename "$source").o" >> "$build/mutant-cc.log" 2>&1 ||
            { echo "=== $source" >> "$build/mutant-cc.log"; ok=0; }
    done
    if [ "$ok" = 0 ]; then
        echo "MUTANT DID NOT BUILD, which is not the same as being noticed: $label"
        grep -m 2 "error:" "$build/mutant-cc.log" | cut -c1-140 | sed 's/^/  /' 
        survived=$((survived + 1))
        return
    fi
    if python3 "$here/check_port.py" "$build/mutant" "$built" "$charon" "$framework" \
        > "$build/mutant.out" 2>&1; then
        echo "MUTANT SURVIVED: $label"
        survived=$((survived + 1))
    else
        echo "  caught: $(grep -m 1 '^FAIL' "$build/mutant.out" | cut -c1-110)"
    fi
}

echo "--- the plants"
# Each plant is chosen from the table by plants.py rather than written here, so it keeps applying when a
# row moves: the file is the one the table names for the class, the needle is that class's own call.
while IFS="$(printf '\t')" read -r label framework file from to; do
    [ -n "${label:-}" ] || continue
    plant "$label" "$framework" "$file" "$from" "$to"
done <<PLANTS
$(python3 "$here/plants.py" "$here/expectations.tsv" "$appledir" $(cat "$build/frameworks"))
PLANTS

echo "--- the check's own control: an object carrying neither selector must not look green"
# The control replaces an object the table says MUST carry -init, chosen from the table rather than taken
# as the first one: an object whose rows all say `none` would agree with an empty file, and a control
# that cannot fail is not a control. Columns 9 and 13 are port-init and port-object.
framework=$(head -1 "$build/frameworks")
victim=$(awk -F'\t' -v f="$framework" 'NR > 1 && $1 == f && $10 == "raise" { print $NF; exit }' \
    "$here/expectations.tsv")
: > "$build/empty.o"
rm -rf "$build/empty"
mkdir -p "$build/empty"
cp "$build/objects/$framework"/*.o "$build/empty/"
cp "$build/empty.o" "$build/empty/$victim"
if python3 "$here/check_port.py" "$appledir" "$build/empty" "$charon" "$framework" \
    > "$build/empty.out" 2>&1; then
    echo "FAIL an object with no -init was accepted"
    survived=$((survived + 1))
else
    echo "  caught: $(grep -m 1 '^FAIL' "$build/empty.out" | cut -c1-110)"
fi

if [ "$survived" -ne 0 ]; then echo "$survived plants survived; this check proves nothing"; exit 1; fi
echo "unavailable-init: OK - $(grep -c . "$build/$framework.classes") classes of $framework, "\
"3 plants noticed, the control red"
