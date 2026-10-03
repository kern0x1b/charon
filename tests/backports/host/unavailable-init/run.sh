#!/bin/sh
# run.sh - the pair every SensorKit class whose SDK 26.2 header closes with NS_UNAVAILABLE, held to
# what the HOST's own SensorKit does about it.
#
#   1. probe.m asks the host, over all eighteen classes: is the selector in the class's OWN method list
#      (the corpus row's question), and what does a caller reach at run time (the behaviour).
#   2. check_host.py holds that against expectations.tsv, which is what the host answered once. A
#      difference means the oracle moved, which is the one thing the table exists to notice.
#   3. check_port.py holds the PORT to the same table: the class's @implementation block raises what the
#      host raises with the host's reason - or spells out NSObject's pair for the four whose own class
#      carries neither selector - and the compiled armv7 object carries -init and +new.
#   4. four plants, each of which must turn step 3 red, and the check's own control: an object carrying
#      neither selector must not look green.
#
# WHY A HOST ORACLE AND NOT A DEVICE. The port's own configuration is a cross-compile for
# armv7-apple-ios6.1.3, which cannot be run on this machine, and the host carries SensorKit with the
# classes implemented, so the host answers the pair where a device would. What the host is NOT is a
# measurement of iOS: the framework is the same family and the two disagree in one place already
# recorded - under Mac Catalyst the SRSensorReader class is declared and implements nothing, while the
# native class this probe opens implements both and raises.
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

# The classes, and the sources and objects to check, are the table's rows - not a list written twice.
python3 - "$here/expectations.tsv" "$build/classes.txt" "$build/sources.txt" "$build/objects.txt" <<'PY'
import sys
table, classes_path, sources_path, objects_path = sys.argv[1:5]
classes, seen_sources, seen_objects = [], [], []
for line in open(table, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    fields = line.rstrip("\n").split("\t")
    if fields[0] == "framework":
        continue
    classes.append(fields[1])
    if fields[-2] not in seen_sources:
        seen_sources.append(fields[-2])
    if fields[-1] not in seen_objects:
        seen_objects.append(fields[-1])
open(classes_path, "w").write("\n".join(classes) + "\n")
open(sources_path, "w").write("\n".join(seen_sources) + "\n")
open(objects_path, "w").write("\n".join(seen_objects) + "\n")
PY

echo "--- the host's own answer, and the table it is held to"
xcrun clang -fobjc-arc -w "$here/probe.m" -framework Foundation -o "$build/probe"
"$build/probe" /System/Library/Frameworks/SensorKit.framework/SensorKit < "$build/classes.txt" \
    > "$build/host.out"
python3 "$here/check_host.py" "$build/host.out"

echo "--- the port: the source, the macro's own body, and the compiled armv7 objects"
for source in $(cat "$build/sources.txt"); do
    object="$build/$(basename "$source").o"
    "$cc" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -I "$appledir" -I "$appledir/SensorKit" \
        -fobjc-arc -c "$appledir/$source" -o "$object" > "$build/cc.log" 2>&1 ||
        { echo "COMPILE FAILED for $source:"; cat "$build/cc.log"; exit 1; }
done
mkdir -p "$build/objects"
for object in $(cat "$build/objects.txt"); do cp "$build/$object" "$build/objects/$object"; done
python3 "$here/check_port.py" "$appledir" "$build/objects" "$charon"

survived=0
plant() {
    label=$1; file=$2; from=$3; to=$4
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant/SensorKit"
    cp "$appledir/CharonValueStore.h" "$build/mutant/CharonValueStore.h"
    cp "$appledir/SensorKit/CharonSensorKit.h" "$build/mutant/CharonSensorKit.h"
    cp "$appledir/SensorKit/CharonSensorKitValue.h" "$build/mutant/SensorKit/CharonSensorKitValue.h"
    cp "$appledir/SensorKit/CharonSensorKitNames.h" "$build/mutant/SensorKit/CharonSensorKitNames.h"
    cp "$appledir/SensorKit/CharonSensorKitProtocols.h" "$build/mutant/SensorKit/CharonSensorKitProtocols.h"
    for source in $(cat "$build/sources.txt"); do cp "$appledir/$source" "$build/mutant/SensorKit/"; done
    target="$build/mutant/SensorKit/$file"
    if ! python3 - "$target" "$from" "$to" <<'PY'
import sys
path, needle, replacement = sys.argv[1:4]
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
    for source in $(cat "$build/sources.txt"); do
        "$cc" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -I "$build/mutant" \
            -I "$build/mutant/SensorKit" -fobjc-arc -c "$build/mutant/SensorKit/$(basename "$source")" \
            -o "$built/$(basename "$source").o" > "$build/mutant-cc.log" 2>&1 || ok=0
    done
    if [ "$ok" = 0 ]; then
        echo "MUTANT DID NOT BUILD, which is not the same as being noticed: $label"
        survived=$((survived + 1))
        return
    fi
    if python3 "$here/check_port.py" "$build/mutant" "$built" "$charon" > "$build/mutant.out" 2>&1; then
        echo "MUTANT SURVIVED: $label"
        survived=$((survived + 1))
    else
        echo "  caught: $(grep -m 1 '^FAIL' "$build/mutant.out" | cut -c1-110)"
    fi
}

echo "--- the plants"

plant "a class that must refuse instead returns NSObject's object" SensorKit170.m \
    "CHARON_SENSORKIT_UNCREATABLE_NEW_AND_INIT(@\"\")" \
    "CHARON_SENSORKIT_INHERITED_NEW_AND_INIT"

plant "the reason the host gives is another one" SensorKit164.m \
    "CHARON_SENSORKIT_UNCREATABLE_NEW_AND_INIT(@\"Not available\")" \
    "CHARON_SENSORKIT_UNCREATABLE_NEW_AND_INIT(@\"Not here\")"

plant "the macro itself stops raising" CharonSensorKitValue.h \
    "        [NSException raise:NSInternalInconsistencyException format:reason_text];          \\" \
    "        (void)reason_text;                                                                   \\"

plant "the pair is deleted outright" SensorKit260.m \
    "CHARON_SENSORKIT_INHERITED_NEW_AND_INIT
" ""

echo "--- the check's own control: an object carrying neither selector must not look green"
: > "$build/empty.o"
mkdir -p "$build/empty"
cp "$build/objects"/*.o "$build/empty/"
cp "$build/empty.o" "$build/empty/SensorKit260.m.o"
if python3 "$here/check_port.py" "$appledir" "$build/empty" "$charon" > "$build/empty.out" 2>&1; then
    echo "FAIL an object with no -init was accepted"
    survived=$((survived + 1))
else
    echo "  caught: $(grep -m 1 '^FAIL' "$build/empty.out" | cut -c1-110)"
fi

if [ "$survived" -ne 0 ]; then echo "$survived plants survived; this check proves nothing"; exit 1; fi
echo "sensorkit-init: OK - 18 classes against the host's answer, 4 plants noticed, the control red"
