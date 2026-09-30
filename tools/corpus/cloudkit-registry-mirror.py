#!/usr/bin/env python3
"""mirror.py - the two directions of the registry against the code, and the counts both ways.

  * every `@implementation X` in the series' own sources has a row that names X
  * every row in values.json has a definition in one of those files

The gate refuses "built, but no entry in registry/" for the first, and the reviewer refused the series for
the second - a class with no row and a row with no code are the same mistake from two ends.
"""
import json
import os
import re
import sys

SRC = "packages/a/apple-backports/CloudKit"
REG = "packages/a/apple-backports/registry/CloudKit/values.json"
files = sorted(f for f in os.listdir(SRC) if f.endswith((".m", ".h")))
impl = {}          # class -> file
externs = {}       # constant -> file
for name in files:
    text = open(os.path.join(SRC, name), encoding="utf-8", errors="replace").read()
    # comments go first: CKNotifications8.m:119 is a SENTENCE that begins "// @implementation block is
    # private to its class", and counting it is how this script once reported a class that does not exist
    text = re.sub(r"//[^\n]*", "", text)
    for cls in re.findall(r"@implementation\s+(\w+)", text):
        impl.setdefault(cls, name)
    for sym in re.findall(r"^\s*(?:extern\s+)?[\w *]*?\b(\w+)\s*=\s*", text, re.M):
        externs.setdefault(sym, name)

rows = json.load(open(REG))["entries"]
apis = {r["api"] for r in rows}
def base(api):
    if api[:2] in ("+[", "-["):
        return api[2:].split(" ")[0]
    return api.split("(")[0].strip("+-[]")

without_row = sorted(c for c in impl
                     if not c.startswith("Charon")
                     and c not in apis and ("+[%s new]" % c) not in apis)
without_code = sorted(r["api"] for r in rows
                     if r.get("status") == "implemented"
                     and base(r["api"]) not in impl and base(r["api"]) not in externs)
# The third direction, and the one this series' own CKSyncEngine row fell into: a row that says
# `absent` while the tree defines the class. The owner's rule is that `absent` is only for hardware
# the device physically lacks, so a row reading `absent` over code that is here is a false claim
# about the tree - and nothing caught it, which is how it survived a review read and a green check.
wrong_status = sorted(r["api"] for r in rows
                      if r.get("status") == "absent" and base(r["api"]) in impl)
print("implementations in the %d sources: %d" % (len(files), len(impl)))
print("rows in values.json: %d" % len(rows))
print("implemented with no row: %d %s" % (len(without_row), without_row))
print("rows with no definition: %d %s" % (len(without_code), without_code))
print("marked absent but defined here: %d %s" % (len(wrong_status), wrong_status))

# A CHECK THAT CANNOT FAIL IS NOT EVIDENCE, and this one could not: it printed its numbers and
# returned nothing, so `python3 ...; echo $?` read 0 whatever it had found. The gate's own rule is
# "built, but no entry in registry/" for a definition with no row; this is the other direction, a
# row with no code, and the third, a row that understates what is here. Each is a failure, and the
# exit says so.
if without_row:
    print("FAIL a definition with no registry row, which is the gate's \"built, but no entry in"
          " registry/\": %s" % ", ".join(without_row))
if without_code:
    print("FAIL a row with no definition in this tree: %s" % ", ".join(without_code))
if wrong_status:
    print("FAIL a row marked absent while the tree defines it, which is only for hardware the"
          " device lacks: %s" % ", ".join(wrong_status))
sys.exit(1 if (without_row or without_code or wrong_status) else 0)
