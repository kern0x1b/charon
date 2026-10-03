#!/bin/sh
# run.sh -- the capture-device capability members the port carries (iOS 17 and 17.2), the port against the
# host's own camera, in one binary and in one process.
#
# The same shape as tests/backports/host/avf-globals' controls phase, for the same reason: the port's code is a
# CATEGORY on AVCaptureDevice and AVCaptureDeviceFormat, and those are APPLE's classes on this host. A copy
# compiled here unchanged would replace Apple's own implementations in this process and the probe would be
# comparing the port against itself. So the copies are renamed at their @implementation lines and land on
# stand-in owners this build declares (charon_host_AVCaptureDevice, charon_host_AVCaptureDeviceFormat), while
# the category names stay, so a category the port spells differently still fails to compile.
#
# WHAT MAKES IT A CHECK AND NOT A COMPARISON:
#   * the member list is read from the port's registry, never typed here, and every row of it must be answered
#     on both sides: a member one side does not carry is a red;
#   * every answer is compared against expectations.tsv, which carries BOTH columns - what this host's camera
#     answers and what the port answers - and the reason where the two differ. The hardware differs (this
#     camera has reaction effects, an iPhone 4S has not), so "the two columns are equal" is not the claim;
#     "each column is the one the table names, and the port's is the answer for the port's devices" is;
#   * the two CLASS properties are read out of the APPLICATION's Info.plist, so they are asked four times
#     with four plists the harness writes itself, and the expectation for each run is COMPUTED from the plist
#     that run used. That is the check that the rule is the rule and not a constant in either direction;
#   * the run is PLANTED and the plant must go red, and CONTROL=1 puts the unmutated sources through the
#     identical path and must stay clean;
#   * a mutation that does not build is RUN FAILED, never a noticed mutation.
#
# Run DIRECTLY: three small compiles, four small runs.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
control=${CONTROL:-0}
# AVFCAPSMUTANT=1 plants a wrong capability answer; AVFCAPSMUTANT=prefcam plants the preferred-camera pair's
# persistence away. Each is named, so a run that plants neither is not called a mutation.
mutant=${AVFCAPSMUTANT:-0}
build=${AVF_CAPS_BUILD:-$root/.agent-work/avf-capabilities-build}
rm -rf "$build"
mkdir -p "$build/src" "$build/o"

for source in AVCaptureDeviceReactions17.m AVCaptureDeviceFormatDepthZoom17.m; do
    [ -f "$avf/$source" ] || {
        echo "FAIL: $avf/$source does not exist, so the surface this run checks for is not there"
        exit 1
    }
done
[ -f "$avf/CharonAVCaptureDeviceReactions17.h" ] || {
    echo "FAIL: $avf/CharonAVCaptureDeviceReactions17.h does not exist, so these members are declared nowhere"
    exit 1
}

# THE LIST IS BUILT FROM THE REGISTRY and the port's own header, never typed here. For a property the
# SELECTOR THE HEADER DECLARES is asked for, so a row whose getter= is something other than the property's
# name asks a selector both sides have. A property the header does not declare is reported, not guessed at.
python3 - "$avf/CharonAVCaptureDeviceReactions17.h" "$root/packages/a/apple-backports/registry/AVFoundation" \
        "$build/members.tsv" <<'MEMBERS'
import json, os, re, sys
header, registry, out = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(header).read()
# every property and method the header declares, with its owner, its accessor and whether it is a class member
current = None
declared = {}
for line in text.split("\n"):
    owner = re.match(r"@interface\s+(\w+)\s+\((\w+)\)", line.strip())
    if owner:
        current = (owner.group(1), owner.group(2))
        continue
    if current is None:
        continue
    attributes = line.split("@property", 1)[1] if "@property" in line else None
    if attributes:
        getter = re.search(r"getter=(\w+)", attributes)
        rest = attributes[attributes.index(")") + 1:] if "(" in attributes else attributes
        rest = rest.split("API_AVAILABLE")[0].split("API_UNAVAILABLE")[0]
        rest = re.sub(r"<[^<>]*>", " ", rest)
        tokens = re.findall(r"\b([A-Za-z_]\w*)\b", rest)
        if not tokens:
            raise SystemExit("cannot tell the property name on this line, so this run must not guess: " + line)
        # `class` is in the attribute list, which is AFTER "@property": `@property(class, readonly) BOOL x`.
        isClass = line.split("@property", 1)[1].lstrip().startswith("(class")
        declared.setdefault((current[0], tokens[-1]), (getter.group(1) if getter else tokens[-1],
                                                      "class" if isClass else "instance"))
        continue
    method = re.match(r"^[-+] \([^)]*\)\s*(\w+)\s*:?\s*$|API_AVAILABLE|NS_SWIFT_NAME", line.strip())
    signature = re.match(r"^[-+] \(([^)]*)\)\s*(\w+)\s*(:|;)", line.strip())
    if signature:
        declared.setdefault((current[0], signature.group(2)),
                            (signature.group(2), "class" if signature.group(1).startswith("instancetype") is False
                             and signature.group(0).startswith("+") else "instance"))
rows, unnamed, refusals = [], [], []
for name in sorted(os.listdir(registry)):
    if not name.startswith("reactions") or not name.endswith(".json"):
        continue
    for entry in json.load(open(os.path.join(registry, name))).get("entries", []):
        api = entry["api"]
        if entry["kind"] == "method":
            match = re.match(r"^-\[(\w+) (\w+)\]$", api)
            if not match:
                continue
            owner, member = match.group(1), match.group(2)
            sign = "-"
        elif entry["kind"] == "property":
            owner, member = api.split(".", 1)
            sign = ""
        else:
            continue
        if (owner, member) not in declared:
            unnamed.append(api)
            continue
        accessor, kind = declared[(owner, member)]
        # The one method row, -performEffectForReaction:, is asked by its own phase below: its answer is a
        # refusal and not a value, so asking it here through the value path would ask the wrong question.
        if entry["kind"] == "method":
            refusals.append(api)
            continue
        rows.append((api, owner, sign + accessor, kind))
if unnamed:
    raise SystemExit("no declaration in %s for %s, so this run would ask a selector neither side has"
                     % (header, " ".join(unnamed)))
with open(out, "w") as handle:
    for row in rows:
        handle.write("%s\t%s\t%s\t%s\n" % row)
print("the probe is asked about %d member(s) with a value, and %d refusal(s) of its own: %s"
      % (len(rows), len(refusals), " ".join(refusals)))
MEMBERS

# THE PROLOGUE: the two stand-ins with the same categories the port's sources implement, and nothing else. The
# port's OWN members are NOT declared here: what the port's copy carries is asked of the port's copy through the
# runtime, and a prologue that declared them would answer that question itself.
#
# What IS declared here is the stand-in device list, because the port's preferred-camera pair asks the release
# for its devices: `[AVCaptureDevice devicesWithMediaType:]` and `[AVCaptureDevice defaultDeviceWithMediaType:]`.
# On the real target those two are the RELEASE's own functions over the release's own cameras (which is why the
# port calls them instead of naming a position), and here they are modelled over a list this build hands them -
# which is what makes "the most recent camera is gone" askable at all.
#
# The two macros at the end are what route the port's OWN call sites to the stand-in: they rename the class name
# everywhere in the copied source, in a method body as well as at an @implementation line, so the port's code
# asks the stand-in and not Apple's camera. The control that this is happening, and not the probe talking to the
# stand-in behind the port's back, is the preferred-camera phase: its steps change with the list this run hands
# the stand-in, which only the port's own code can do.
python3 - "$avf/CharonAVCaptureDeviceReactions17.h" "$build/src/prologue.h" <<'PROLOGUE'
import re, sys
header, out = sys.argv[1], sys.argv[2]
text = open(header).read()
categories = re.findall(r"@interface\s+(\w+)\s+\((\w+)\)", text)
if len(categories) != 3:
    raise SystemExit("expected the three categories this header declares and found %d: %s"
                     % (len(categories), categories))
lines = ["// Generated by tests/backports/host/avf-capabilities/run.sh from " + header + ": stand-in owners for",
         "// the port's two categories, because AVCaptureDevice and AVCaptureDeviceFormat are Apple's classes on",
         "// this host and a copy compiled here unchanged would replace their own methods in this process.",
         "#import <Foundation/Foundation.h>",
         "#import <AVFoundation/AVFoundation.h>",
         "",
         "// The stand-in device list. +devicesWithMediaType: and +defaultDeviceWithMediaType: are the release's own",
         "// functions on a real target and are implemented over this list in standins.rn; -uniqueID is how the port",
         "// names a device across a launch, so it is the one member the list carries.",
         "@interface charon_host_AVCaptureDevice : NSObject",
         "+ (void)charon_host_setPresentDevices:(NSArray *)devices;",
         "+ (NSArray *)devicesWithMediaType:(NSString *)mediaType;",
         "+ (id)defaultDeviceWithMediaType:(NSString *)mediaType;",
         "@property(nonatomic, copy) NSString *uniqueID;",
         "@property(nonatomic, copy) NSString *localizedName;",
         "@property(nonatomic) long position;",
         "@property(nonatomic) BOOL connected;",
         "@end",
         "",
         "@interface charon_host_AVCaptureDeviceFormat : NSObject",
         "@end",
         ""]
for owner, category in categories:
    lines += ["@interface charon_host_%s (%s)" % (owner, category), "@end", ""]
lines += ["// The rename. Defined after every declaration above, which already carry the stand-in names.",
          "#define AVCaptureDevice charon_host_AVCaptureDevice",
          "#define AVCaptureDeviceFormat charon_host_AVCaptureDeviceFormat",
          ""]
open(out, "w").write("\n".join(lines) + "\n")
print("the host build's prologue declares %d stand-in categories over 2 stand-in owners, and renames the two"
      % len(categories))
print("  owner names in the port's sources, in a method body as well as at an @implementation line")
PROLOGUE
# The stand-ins' own OBJECTS, in a source of their own and not in the prologue: the prologue is prepended to
# both copies, so an @implementation in it would define each class twice ("duplicate symbol
# _OBJC_CLASS_$_charon_host_AVCaptureDevice").
{
    echo '#import "prologue.h"'
    cat <<'STANDINS'

// The list this build hands the port. One entry per camera of a device of this port's bands.
static NSArray *charon_host_present_devices;

@implementation charon_host_AVCaptureDevice

+ (void)charon_host_setPresentDevices:(NSArray *)devices
{
    charon_host_present_devices = [devices copy];
}

// "+devicesWithMediaType: ... devices currently connected and available for capture" (AVCaptureDevice.h:105):
// a camera that is not connected is not one of them, which is the whole point of the history phase.
+ (NSArray *)devicesWithMediaType:(NSString *)mediaType
{
    NSMutableArray *found = [NSMutableArray array];
    for (id device in charon_host_present_devices)
        if ([(id)device connected])
            [found addObject:device];
    return found;
}

// "+defaultDeviceWithMediaType: ... will return the built in camera that is primarily used for capture and
// recording" (AVCaptureDevice.h:120). What it models: the first connected video device of that list, which on a
// device of this port's bands is the camera on the back - measured on an iPhone 4S in
// tests/backports/device/avcapture.m:91, where +defaultDeviceWithDeviceType:mediaType:position: answers
// firstObject of the discovery list and that list is ordered back before front
// (facts/AVFoundation/AVCaptureDeviceDiscovery.md). Nothing in the port depends on that rule: the port asks
// this function, so the release's own answer is what it gets.
+ (id)defaultDeviceWithMediaType:(NSString *)mediaType
{
    return [[self devicesWithMediaType:mediaType] firstObject];
}

@end

@implementation charon_host_AVCaptureDeviceFormat

@end
STANDINS
} > "$build/src/standins.rn"

# THE COPIES: the port's own header import is dropped, because on this host its @interface AVCaptureDeviceFormat
# category would collide with the macOS SDK's own declarations and its forward declarations are Apple's business.
# The class name is NOT rewritten here: the prologue's two macros do it, in a method body as well as at an
# @implementation line, so the port's own `[AVCaptureDevice devicesWithMediaType:]` reaches the stand-in. Each
# copy is asserted to carry the owner lines this harness was written against, as WHOLE WORDS - a count of
# substrings would also match the port's CharonAVCaptureDeviceReactions17.h import and prove nothing.
# The fourth field is how many bodies of the copy are expected to send a message to a renamed class, so the
# "the macros have something to rename" assertion is not applied to the format-only object, which has none.
for triple in "AVCaptureDeviceReactions17.m:reactions17.rn:2:4" "AVCaptureDeviceFormatDepthZoom17.m:depthzoom17.rn:1:0"; do
    src=$(printf '%s\n' "$triple" | cut -d: -f1)
    python3 - "$avf/$src" "$build/src/prologue.h" "$build/src/$(printf '%s\n' "$triple" | cut -d: -f2)" \
            "$(printf '%s\n' "$triple" | cut -d: -f3)" "$(printf '%s\n' "$triple" | cut -d: -f4)" <<'COPY'
import re, sys
source, prologue, out, expected, bodies = (sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]),
                                          int(sys.argv[5]))
text = open(source).read()
drop = '#import "CharonAVCaptureDeviceReactions17.h"\n'
if text.count(drop) != 1:
    raise SystemExit("%s imports the Charon header %d time(s), so this copy is not the one the harness was "
                     "written against" % (source, text.count(drop)))
text = text.replace(drop, "")
owners = re.findall(r"^@(?:implementation|interface)\s+(AVCaptureDevice|AVCaptureDeviceFormat)\b", text, re.M)
if len(owners) != expected:
    raise SystemExit("%s names %d owner line(s) at an @implementation/@interface and this copy is written for "
                     "%d: %s" % (source, len(owners), expected, owners))
# Not vacuous: the owner names also have to appear in the bodies, where the macros do their work.
found = len(re.findall(r"\[AVCaptureDevice(?:Format)?\b", text))
if found != bodies:
    raise SystemExit("%s sends %d message(s) to a renamed class in a body and this copy is written for %d, so"
                     " the two macros would rename a different number of places than this harness was written"
                     " against" % (source, found, bodies))
open(out, "w").write(open(prologue).read() + text)
print("the copy of %s carries the prologue and names %d owner line(s) the macros will rename" % (source, len(owners)))
COPY
done
objects=""
for pair in "reactions17.rn:reactions17.o" "depthzoom17.rn:depthzoom17.o" "standins.rn:standins.o"; do
    src=${pair%%:*}; obj=${pair##*:}
    if ! xcrun clang -fobjc-arc -w -x objective-c -I"$avf" -I"$build/src" -c "$build/src/$src" \
            -o "$build/o/$obj" > "$build/o/$obj.log" 2>&1; then
        echo "RUN FAILED: the port's $src did not build - a build failure is never a noticed mutation"
        head -8 "$build/o/$obj.log"
        exit 1
    fi
    [ -f "$build/o/$obj" ] || { echo "FAIL: $obj was not written, so the link below would measure nothing"; exit 1; }
    objects="$objects $build/o/$obj"
done
# The plant is applied AFTER the first compile, the only order in which the guard below can see it: a
# plant applied before it leaves the object identical to its own recompile, and the guard then refuses a
# mutation that did happen.
if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    case "$mutant" in
    1|reactions) plant=reactions ;;
    prefcam)     plant=prefcam ;;
    *) echo "FAIL: AVFCAPSMUTANT=$mutant is not a plant this harness writes; run it as 1 or as prefcam"
       exit 1 ;;
    esac
    python3 - "$build/src/reactions17.rn" "$plant" <<'PERTURB'
import sys
path, plant = sys.argv[1], sys.argv[2]
text = open(path).read()
# Each plant is a (before, after) pair asserted to occur EXACTLY once before anything is written: Python's
# str.replace on a missing needle is a silent no-op, and a "planted" run over an unplanted file reported a
# mutant as applied four times running (2026-10-03).
plants = {
    "reactions": ("""- (BOOL)canPerformReactionEffects
{
    return NO;
}""", """- (BOOL)canPerformReactionEffects
{
    return YES; /* PLANTED */
}"""),
    "prefcam": ("""    [[NSUserDefaults standardUserDefaults] setObject:[history copy]
                                              forKey:CHARON_CAPTURE_USER_PREFERRED_HISTORY_KEY];""",
                 """    /* PLANTED: the choice is not persisted, so the next launch forgets it. */
    (void)[history copy];"""),
}
before, after = plants[plant]
if text.count(before) != 1:
    raise SystemExit("the %s mutation target is not unique (%d matches), so this run proves nothing"
                     % (plant, text.count(before)))
out = text.replace(before, after)
if out.count(before) != 0 or out.count(after) != 1:
    raise SystemExit("the %s mutation did not take, so this run proves nothing" % plant)
open(path, "w").write(out)
print("# the mutation applied: " + {"reactions": "-canPerformReactionEffects answers YES for a camera with no"
                                         " reactions",
                                     "prefcam": "+setUserPreferredCamera: no longer persists the choice"}[plant])
PERTURB
fi
if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    # The plant is applied AFTER the first compile, the only order in which the guard below can see it: a
    # plant applied before it leaves the object identical to its own recompile and the guard then refuses a
    # mutation that did happen.
    before=$(shasum -a 256 "$build/o/reactions17.o" | cut -d' ' -f1)
    if ! xcrun clang -fobjc-arc -w -x objective-c -I"$avf" -I"$build/src" -c "$build/src/reactions17.rn" \
            -o "$build/o/reactions17.o" > "$build/o/reactions17.rebuild.log" 2>&1; then
        echo "RUN FAILED: the port's reactions17.rn did not build after the mutation"
        head -6 "$build/o/reactions17.rebuild.log"
        exit 1
    fi
    after=$(shasum -a 256 "$build/o/reactions17.o" | cut -d' ' -f1)
    [ "$before" != "$after" ] || {
        echo "FAIL: reactions17.o is byte-for-byte what it was before the mutation, so the probe links the same"
        echo "      object and this mutation can never be noticed"
        exit 1
    }
    echo "rebuilt reactions17.o after the mutation, and it differs: ${before%????????????????????????????????????????????????} -> ${after%????????????????????????????????????????????????}"
fi
if ! xcrun clang -fobjc-arc -w -I"$avf" "$here/probe.m" $objects -framework Foundation -framework AVFoundation \
        -framework CoreMedia -o "$build/probe" > "$build/probe.log" 2>&1; then
    echo "FAIL: the probe did not build"; head -14 "$build/probe.log"; exit 1
fi
"$build/probe" "$build/members.tsv" > "$build/table" 2> "$build/stderr" || {
    echo "FAIL: the probe did not run"; head -10 "$build/stderr"; exit 1; }

# 1. the controls, each named, so a run that examined nothing cannot pass
check_control() {
    line=$(grep "^CONTROL	$1	" "$build/table" | cut -f3 || true)
    [ -n "$line" ] || { echo "FAIL: control $1 printed nothing, so the run examined nothing"; exit 1; }
    case "$2" in
        ABSENT) [ "$line" = ABSENT ] || { echo "FAIL: control $1 answered [$line], expected ABSENT"; exit 1; } ;;
        *) case "$line" in HAS*|one) : ;; *) echo "FAIL: control $1 answered [$line], expected HAS"; exit 1; ;; esac ;;
    esac
    echo "ok  control $1 = $line"
}
check_control AVCaptureNoSuchClass ABSENT
check_control AVCaptureDevice HAS
check_control AVCaptureDeviceFormat HAS
check_control charon_host_AVCaptureDevice HAS
check_control charon_host_AVCaptureDeviceFormat HAS

# 2. every member both sides are asked about must be answered by both
members=$(grep -c '^RESPONDS	' "$build/table" || true)
listed=$(wc -l < "$build/members.tsv" | tr -d ' ')
if [ "$members" != "$listed" ]; then
    echo "FAIL: the list names $listed members and the probe answered $members"
    exit 1
fi
lacks=$(grep '^RESPONDS	' "$build/table" | grep -e 'host=no' -e 'port=no' || true)
if [ -n "$lacks" ]; then
    echo "FAIL: a member both sides are asked about is missing from one of them:"
    echo "$lacks" | head -12
    exit 1
fi
echo "ok  $members members are answered by both sides"

# 3. the answers, each against the table. BOTH columns: the host's is measured here and the port's is the
#    answer for the port's own devices, and where they differ the table says why.
compared=0; wrong=0; : > "$build/wrong.log"
while IFS=$(printf '\t') read -r api host port why; do
    case "$api" in ''|\#*) continue ;; esac
    line=$(grep "^ANSWER	$api	" "$build/table" | head -1)
    [ -n "$line" ] || { echo "FAIL: the probe printed no ANSWER row for $api"; exit 1; }
    got_host=$(printf '%s\n' "$line" | cut -f3)
    got_port=$(printf '%s\n' "$line" | cut -f4)
    want_host="host=[$host]"
    want_port="port=[$port]"
    ok=1
    [ "$got_host" = "$want_host" ] || ok=0
    [ "$got_port" = "$want_port" ] || ok=0
    compared=$((compared + 1))
    if [ "$ok" = 0 ]; then
        wrong=$((wrong + 1))
        printf 'DIFFERS\t%s\twant %s %s\tgot %s %s\n' "$api" "$want_host" "$want_port" "$got_host" "$got_port" \
            >> "$build/wrong.log"
    fi
done < "$here/expectations.tsv"

# 4. THE PREFERRED-CAMERA PAIR. Five rules of the header (AVCaptureDevice.h:661-663 for the user's choice, :674
#    for the system's) and one step each, so none of them can be a constant that happens to be right for one
#    step. The expectation for every step is computed HERE from the fixture that step used - the list of cameras
#    the stand-in was given and the choice the probe made before it - by a second implementation of the four
#    rules in python, and then compared with what the port answered. A model that repeats the port's code would
#    only test that it is self-consistent, so the model is written from the header's sentences:
#
#      the most recent entry of the history that is in the list of connected cameras now, else the release's own
#      best present camera once the history is not empty, else nil while nothing was ever chosen;
#      the system's answer is the user's answer, or that same best camera;
#      a nil set adds nothing to the history.
cat > "$build/prefcam-fixture.tsv" <<'FIXTURE'
# step	cameras the stand-in is given	choice the probe makes before the step	a nil set after it	cleared before it
before-any-set	back-camera,front-camera	-	no	no
after-front-is-chosen	back-camera,front-camera	front-camera	no	no
after-back-is-chosen	back-camera,front-camera	back-camera	no	no
after-nil-is-set	back-camera,front-camera	-	yes	no
most-recent-gone-next-best-answers	front-camera	-	no	no
no-camera-at-all	-	-	no	no
history-exhausted	back-camera	front-camera	no	yes
nothing-ever-chosen	back-camera,front-camera	-	no	yes
FIXTURE
#    One python block, run once: it writes what differs to the log and prints "compared wrong" for the verdict
#    below, so the counts and the differences come from the same pass and cannot disagree.
: > "$build/prefcam-wrong.log"
: > "$build/persist-wrong.log"
python3 - "$build/table" "$build/prefcam-fixture.tsv" "$build/prefcam-wrong.log" > "$build/prefcam-counts" <<'PREFCAM'
import sys
table, fixture, log = sys.argv[1], sys.argv[2], sys.argv[3]
DEPTH = 3                                   # the port's history depth; the header says "a short history"
seen = {}
for line in open(table):
    fields = line.rstrip("\n").split("\t")
    if len(fields) >= 5 and fields[0] == "PREFCAM" and fields[1] != "host":
        seen[fields[1]] = (fields[2], fields[3], fields[4])
host = [line.rstrip("\n").split("\t") for line in open(table) if line.startswith("PREFCAM\thost\t")]
if not host or "auth=0 (notDetermined)" not in host[0][2]:
    raise SystemExit("the host line does not carry this process's camera authorization, so the host's nil for"
                     " the preferred-camera pair cannot be read for what it is: %s" % (host[0][2] if host else "(no line)"))
history, compared, wrong = [], 0, 0
with open(log, "w") as handle:
    for line in open(fixture):
        if line.startswith("#") or not line.strip():
            continue
        step, cameras, chosen, nil_set, cleared = line.rstrip("\n").split("\t")
        if cleared == "yes":
            history = []
        if chosen != "-":
            history = [chosen] + [entry for entry in history if entry != chosen]
            del history[DEPTH:]
        present = [camera for camera in cameras.split(",") if camera != "-"]
        user = next((entry for entry in history if entry in present),
                    present[0] if (present and history) else None)
        system = user if user else (present[0] if present else None)
        stored = "%d %s [%s]" % (len(history), "entry" if len(history) == 1 else "entries", ",".join(history))
        want = ("user=[%s]" % (user or "nil"), "system=[%s]" % (system or "nil"), "defaults=[%s]" % stored)
        compared += 1
        got = seen.get(step)
        if got is None:
            wrong += 1
            handle.write("%s\twant %s %s %s\tgot (no PREFCAM row for this step)\n"
                         % (step, want[0], want[1], want[2]))
        elif got != want:
            wrong += 1
            handle.write("%s\twant %s %s %s\tgot %s %s %s\n"
                         % (step, want[0], want[1], want[2], got[0], got[1], got[2]))
print(compared, wrong)
PREFCAM
read -r compared_prefcam wrong_prefcam < "$build/prefcam-counts"
echo "note: the host's own preferred-camera line, with this process's camera authorization beside it:"
grep "^PREFCAM	host	" "$build/table" | sed 's/^/note: /'

# 5. PERSISTENCE ACROSS LAUNCHES. Two processes of one bundle: the first chooses a camera, the second only
#    reads. The header's promise is "across app launches and reboots" (:661), so a value kept in one process's
#    own memory cannot answer it.
mkdir -p "$build/two-launches.app/Contents/MacOS"
cp "$build/probe" "$build/two-launches.app/Contents/MacOS/probe"
cat > "$build/two-launches.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>probe</string>
  <key>CFBundleIdentifier</key><string>org.charon.probe.avf-two-launches</string>
  <key>CFBundleName</key><string>avf-two-launches</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
"$build/two-launches.app/Contents/MacOS/probe" "$build/members.tsv" set > "$build/launch1.table" 2>&1 || {
    echo "FAIL: the first launch of the persistence pair did not run"; head -8 "$build/launch1.table"; exit 1; }
"$build/two-launches.app/Contents/MacOS/probe" "$build/members.tsv" read > "$build/launch2.table" 2>&1 || {
    echo "FAIL: the second launch of the persistence pair did not run"; head -8 "$build/launch2.table"; exit 1; }
first=$(grep "^PERSIST	first-launch	" "$build/launch1.table" | cut -f3 || true)
second=$(grep "^PERSIST	second-launch	" "$build/launch2.table" | cut -f3 || true)
# Nothing here exits: a planted run has to reach the verdict below, which is where "the mutation was noticed" is
# decided over the table, the steps and this pair together.
persist_wrong=0
[ -n "$first" ] && [ -n "$second" ] || {
    echo "FAIL: a launch of the persistence pair printed no PERSIST line, so nothing was compared"
    echo "      first=[$first] second=[$second]"
    exit 1
}
echo "      across two launches of one bundle: the first chose [$first], the second read [$second]"
if [ "$first" != front-camera ] || [ "$second" != front-camera ]; then
    persist_wrong=$((persist_wrong + 1))
    {
        echo "DIFFERS	persistence	AVCaptureDevice.h:661 promises the choice across app launches and"
        echo "    reboots, and the first launch left [$first] while the second read [$second]"
    } >> "$build/persist-wrong.log"
fi
# And a bundle of its own must see nothing: the choice is the application's, not the system's.
mkdir -p "$build/other-launch.app/Contents/MacOS"
cp "$build/probe" "$build/other-launch.app/Contents/MacOS/probe"
sed 's/org.charon.probe.avf-two-launches/org.charon.probe.avf-other-launch/' \
    "$build/two-launches.app/Contents/Info.plist" > "$build/other-launch.app/Contents/Info.plist"
"$build/other-launch.app/Contents/MacOS/probe" "$build/members.tsv" read > "$build/launch3.table" 2>&1 || {
    echo "FAIL: the third launch did not run"; head -8 "$build/launch3.table"; exit 1; }
third=$(grep "^PERSIST	second-launch	" "$build/launch3.table" | cut -f3 || true)
if [ "$third" != nil ]; then
    persist_wrong=$((persist_wrong + 1))
    {
        echo "DIFFERS	one-application	another bundle of its own read [$third], so what is kept is not"
        echo "    this application's own choice"
    } >> "$build/persist-wrong.log"
fi
echo "      a bundle of its own reads [$third], so what is kept is one application's own choice"
[ "$persist_wrong" = 0 ] &&
    echo "ok  the choice survives a launch and stays in the application that made it"

# 6. THE VERDICT, for a planted run and for its control. Both the table and the preferred-camera steps count: a
#    plant that only one of the two can see is a plant that proves nothing.
if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    if [ $((wrong + wrong_prefcam + persist_wrong)) = 0 ]; then
        echo "FAIL: the mutation left every answer, every step and both launches as they were, so this check"
        echo "      cannot fail and proves nothing"
        exit 1
    fi
    echo "ok  the mutation was noticed: $wrong of $compared table answers, $wrong_prefcam of $compared_prefcam"
    echo "    preferred-camera steps, and $persist_wrong of the two checks around surviving a launch differ"
    echo "    from what the header's rules give"
    head -4 "$build/wrong.log"
    head -4 "$build/prefcam-wrong.log"
    head -4 "$build/persist-wrong.log"
    exit 0
fi
if [ "$mutant" != 0 ] && [ "$control" != 0 ]; then
    if [ $((wrong + wrong_prefcam + persist_wrong)) != 0 ]; then
        echo "FAIL: the control is not clean: $wrong of $compared table answers, $wrong_prefcam of"
        echo "      $compared_prefcam preferred-camera steps and $persist_wrong of the two checks around"
        echo "      surviving a launch differ through the identical path, so the red would be the path and not"
        echo "      the mutation"
        head -4 "$build/wrong.log"
        head -4 "$build/prefcam-wrong.log"
        head -4 "$build/persist-wrong.log"
        exit 1
    fi
    echo "ok  the control is clean: the unmutated sources through the identical build-and-run path"
    exit 0
fi
if [ "$persist_wrong" != 0 ]; then
    echo "FAIL: $persist_wrong of the two checks around the choice surviving a launch are not what the"
    echo "      header's rule gives"
    head -8 "$build/persist-wrong.log"
    exit 1
fi
if [ "$wrong" != 0 ]; then
    echo "FAIL: $wrong of $compared answers differ from expectations.tsv"
    head -12 "$build/wrong.log"
    exit 1
fi
echo "ok  $compared answers are the ones expectations.tsv names, the host's and the port's columns both"
if [ "$wrong_prefcam" != 0 ]; then
    echo "FAIL: $wrong_prefcam of $compared_prefcam preferred-camera steps differ from the header's rules"
    head -12 "$build/prefcam-wrong.log"
    exit 1
fi
echo "ok  $compared_prefcam preferred-camera steps are the ones the header's four rules give, computed here"
echo "    from the fixture each step used"
grep "^PREFCAM	host	" "$build/table" | sed 's/^/    the host: /'

# 7. THE FOUR INFO.PLISTS. The two class properties answer out of the APPLICATION's bundle, so the probe runs
#    as a bundle four times, with four plists this script writes, and the expectation for each run is
#    computed from the plist that run used. A rule answered with a constant cannot pass this: the two rows
#    change their answer between runs.
run_plist() {
    name=$1
    plist=$2
    bundle="$build/$name.app"
    mkdir -p "$bundle/Contents/MacOS"
    cp "$build/probe" "$bundle/Contents/MacOS/probe"
    cp "$plist" "$bundle/Contents/Info.plist"
    "$bundle/Contents/MacOS/probe" "$build/members.tsv" > "$build/$name.table" 2> "$build/$name.stderr" || {
        echo "FAIL: the probe did not run with the $name Info.plist"; head -6 "$build/$name.stderr"; exit 1; }
}
# Four plists, each written with the value the key really takes, and the expectation for each run COMPUTED
# from the file that run used - read out of the plist, not remembered from the name.
#   UIBackgroundModes                          an ARRAY of strings; "voip" among them is the header's voip app
#   NSCameraReactionEffectsEnabled             true: the header's opt-in for every other application
#   NSCameraReactionEffectGesturesEnabledDefault
#                                             false is what disables gesture detection ("A value of true
#                                             enables gesture detection and a value of false disables it",
#                                             AVCaptureDevice.h:2465)
mkplist() {
    file=$1
    shift
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        for key in "$@"; do
            echo "  <key>$key</key>"
            case "$key" in
                UIBackgroundModes) echo "  <array><string>voip</string></array>" ;;
                NSCameraReactionEffectGesturesEnabledDefault) echo "  <false/>" ;;
                *) echo "  <true/>" ;;
            esac
        done
        echo '</dict></plist>'
    } > "$file"
}
mkplist "$build/empty.plist"
mkplist "$build/voip.plist" UIBackgroundModes
mkplist "$build/optin.plist" NSCameraReactionEffectsEnabled
mkplist "$build/gesturesoff.plist" NSCameraReactionEffectGesturesEnabledDefault
for name in empty voip optin gesturesoff; do run_plist "$name" "$build/$name.plist"; done
for name in empty voip optin gesturesoff; do
    plist="$build/$name.plist"
    want_enabled=0
    grep -q "<key>UIBackgroundModes</key>" "$plist" && want_enabled=1
    grep -q "<key>NSCameraReactionEffectsEnabled</key>" "$plist" && want_enabled=1
    want_gestures=1
    if grep -A1 "<key>NSCameraReactionEffectGesturesEnabledDefault</key>" "$plist" | grep -q "<false/>"; then
        want_gestures=0
    fi
    got=$(grep "^ANSWER	AVCaptureDevice.reactionEffectsEnabled	" "$build/$name.table" | head -1 | cut -f4 || true)
    [ "$got" = "port=[$want_enabled]" ] || {
        echo "FAIL: with the $name Info.plist the port's reactionEffectsEnabled answered [$got], and the"
        echo "      header's rule (AVCaptureDevice.h:2448) says [$want_enabled] for that plist"
        exit 1
    }
    got=$(grep "^ANSWER	AVCaptureDevice.reactionEffectGesturesEnabled	" "$build/$name.table" | head -1 | cut -f4 || true)
    [ "$got" = "port=[$want_gestures]" ] || {
        echo "FAIL: with the $name Info.plist the port's reactionEffectGesturesEnabled answered [$got], and"
        echo "      the header's default (AVCaptureDevice.h:2461) says [$want_gestures] for that plist"
        exit 1
    }
    echo "ok  the $name Info.plist: reactionEffectsEnabled=$want_enabled, reactionEffectGesturesEnabled=$want_gestures"
done
echo "ok  over four Info.plists the port's reactionEffectsEnabled answered YES exactly for voip and for the"
echo "    NSCameraReactionEffectsEnabled opt-in, and its reactionEffectGesturesEnabled NO only for"
echo "    NSCameraReactionEffectGesturesEnabledDefault - the header's rules, not two constants"

echo "note: the host's own answers for the two class properties are the platform's rules, not this port's:"
grep "^ANSWER	AVCaptureDevice.reactionEffectsEnabled	" "$build/table"
grep "^ANSWER	AVCaptureDevice.reactionEffectGesturesEnabled	" "$build/table"
echo "note: the camera this ran against: $(grep '^CAMERA	' "$build/table")"
exit 0
