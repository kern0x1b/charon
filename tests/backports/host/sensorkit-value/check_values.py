#!/usr/bin/env python3
"""check_values.py - the five value-object accessors, in the source and in the compiled armv7 object.

    python3 check_values.py <the port's SensorKit170.m> <the port's SensorKit150.m> <SensorKit170.o> <SensorKit150.o>

Prints the five, one line each, whether the source implements them the way the store works and whether
the compiled object carries the selector. Exits 0 only when all five are both, and non-zero naming which.

WHY SOURCE AND OBJECT, and why nothing here is a differential. There is no behavioural oracle for these
five on this machine: the host's SensorKit marks SRKeyboardMetrics, SRSpeechMetrics and SRFaceMetrics
API_UNAVAILABLE(macos), so a typed call cannot name them, and the port's CharonSensorKit.h cannot be
compiled against the host's newer SDK at all (clang: "typedef redefinition with different types
('NSInteger' vs 'enum SRAcousticSettingsSampleLifetime')"). What the host DOES answer was measured once,
separately, by host-answers.m in this directory, and its output is what the port's answers have to be:
zero for both counts over all ten sentiment categories, and nil for both speech properties. This file
holds the port to implementing exactly that - a count out of the store and a property out of the store,
which is zero and nil when nothing is stored - and to the compiled object carrying the selectors, which
is what the linker binds an @selector() against.

A source check alone would pass on a method the compiler never emitted; an object check alone would pass
on a method that returns a constant. Both are asked for because they fail differently.
"""
import re
import subprocess
import sys

PROPERTIES = ["faceAnchor", "speechRecognition", "soundClassification"]
COUNTS = ["wordCountForSentimentCategory:", "emojiCountForSentimentCategory:"]

# What the port has to be doing, as the source has to spell it. The key of a value property is the
# property's own name (CharonValueStore's own rule), and a count's key carries its category, because a
# count per category is ten numbers and one key per method would hold one of them.
COUNT_SHAPE = "longLongValue"


def selectors(obj):
    out = subprocess.run(["otool", "-v", "-s", "__TEXT", "__objc_methname", obj],
                         check=True, capture_output=True, text=True).stdout
    found = set()
    for line in out.split("\n"):
        match = re.match(r"^[0-9a-f]{6,}  (\S+)$", line)
        if match:
            found.add(match.group(1))
    return found


def main():
    if len(sys.argv) != 5:
        sys.exit("check_values.py: pass SensorKit170.m SensorKit150.m and their two armv7 objects")
    src170, src150, obj170, obj150 = sys.argv[1:5]
    with open(src170, encoding="utf-8", errors="replace") as handle:
        body170 = handle.read()
    with open(src150, encoding="utf-8", errors="replace") as handle:
        body150 = handle.read()
    in170, in150 = selectors(obj170), selectors(obj150)

    failures, ok_lines = [], []

    for name in PROPERTIES:
        implemented = re.search(r"CHARON_VALUE_PROPERTY\(\s*id\s*,\s*%s\s*\)" % re.escape(name), body170)
        carried = name in in170
        line = "%-26s source=%s object=%s" % (name, "store-backed" if implemented else "MISSING",
                                              "selector present" if carried else "SELECTOR ABSENT")
        print(line)
        if implemented and carried:
            ok_lines.append(line)
        if not implemented:
            failures.append("%s is not a store-backed value property in %s" % (name, src170))
        if not carried:
            failures.append("%s is not in the compiled object %s" % (name, obj170))

    # The key helper a count reads through. It exists in the port's own file, and the harness checks the
    # three things that make it right rather than the three words of its name: that the CATEGORY is in it,
    # that the selector is in it, and that both reach the string. A count that returned 7, or one whose
    # key forgot the category so all ten categories answered the same number, is caught here - and both
    # of those plants SURVIVED the first version of this file, which is why they are checked and not
    # assumed.
    helper = re.search(r"static NSString \*CharonKeyboardSentimentKey\([^)]*\)\s*\{(.*?)\n\}", body150, re.S)
    helper_body = helper.group(1) if helper else ""
    key_ok = ("stringWithFormat" in helper_body and "(long)category" in helper_body
              and "selector" in helper_body)
    print("%-26s source=%s" % ("CharonKeyboardSentimentKey", "selector and category both in the key"
                               if key_ok else "MISSING OR INCOMPLETE"))
    if not key_ok:
        failures.append("CharonKeyboardSentimentKey does not build a key from both the selector and the "
                        "category, so every category would answer the same number")

    for name in COUNTS:
        body = re.search(r"-\(NSInteger\)%s[^\n]*\n\{(.*?)\n\}" % re.escape(name), body150, re.S)
        body_text = body.group(1) if body else ""
        reads_store = ("charon_valueForKey:CharonKeyboardSentimentKey(" in body_text
                       and re.escape("@\"%s\"" % name) in body_text)
        carries_type = COUNT_SHAPE in body_text
        implemented = reads_store and carries_type
        carried = name in in150
        line = "%-26s source=%s object=%s" % (name, "store-backed count" if implemented else "MISSING",
                                              "selector present" if carried else "SELECTOR ABSENT")
        print(line)
        if implemented and carried:
            ok_lines.append(line)
        if not reads_store:
            failures.append("%s does not read its count out of the store under its own key with the "
                            "category in it" % name)
        if not carries_type:
            failures.append("%s does not read its count through longLongValue, so a count of nothing "
                            "would not be zero" % name)
        if not carried:
            failures.append("%s is not in the compiled object %s" % (name, obj150))

    for failure in failures:
        print("FAIL " + failure)
    ok = sum(1 for line in ok_lines)
    print("sensorkit-value: %d of %d accessors in the source and in the object, %d failures%s"
          % (ok, len(PROPERTIES) + len(COUNTS), len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())