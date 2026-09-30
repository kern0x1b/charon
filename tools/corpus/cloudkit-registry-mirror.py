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
print("implementations in the %d sources: %d" % (len(files), len(impl)))
print("rows in values.json: %d" % len(rows))
print("implemented with no row: %d %s" % (len(without_row), without_row))
print("rows with no definition: %d %s" % (len(without_code), without_code[:6]))
