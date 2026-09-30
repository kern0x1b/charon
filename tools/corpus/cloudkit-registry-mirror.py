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

# A row is keyed by (kind, api), not by the name alone. `+[CKRecordID new]` and `CKRecordID` are
# two different things the registry says something about, and keying both on the bare name made
# the member row answer the class row's question: with the class row deleted, the member row still
# put CKRecordID in the row set and every direction read 0. A method row is a member of a class, a
# constant row is a global symbol of its own, and a class row is the class.
def key(row):
    return (row["kind"], row["api"])

def owner(api):
    """the class a member row belongs to: a bracketed method, or the head of a dotted property"""
    if api[:2] in ("+[", "-["):
        return api[2:].split(" ")[0]
    if "." in api and "(" not in api:
        return api.split(".")[0]
    return api.split("(")[0].strip("+-[]")

rows_by_key = {key(r): r for r in rows}
class_rows = {r["api"]: r for r in rows if r["kind"] == "class"}
member_rows = [r for r in rows if r["kind"] == "method"]
row_apis = {r["api"] for r in rows}

def defined_here(row):
    """(kind, api) -> the file that defines it, or None.

    A method is defined by its class, and so is a PROPERTY: a property row's api is a selector,
    `CKRecordZone.zoneID`, and the thing that has to exist for it is the class that owns it. Until
    CloudKit had property rows this tool never had to say so - it was class-only because the registry
    was - and 4490 property rows in the other frameworks are admitted by the gate, which is the
    arbiter. A property whose class the tree does not define is still a failure: the row names a
    member of a class that is not here.
    """
    if row["kind"] in ("method", "property"):
        return impl.get(owner(row["api"]))
    if row["kind"] == "constant":
        return externs.get(row["api"])
    return impl.get(row["api"])

without_row = sorted(("class", c) for c in impl
                     if not c.startswith("Charon")
                     and c not in row_apis and ("+[%s new]" % c) not in row_apis)
without_code = sorted(key(r) for r in rows
                      if r.get("status") == "implemented" and defined_here(r) is None)
# The third direction, and the one this series' own CKSyncEngine row fell into: a row that says
# `absent` while the tree defines it. The owner's rule is that `absent` is only for hardware the
# device physically lacks, so a row reading `absent` over code that is here is a false claim about
# the tree - and nothing caught it, which is how it survived a review read and a green check.
wrong_status = sorted(key(r) for r in rows
                      if r.get("status") == "absent" and defined_here(r) is not None)
# The fourth: a member row that is carried while its class is not. A member cannot exist without
# its class, so `+[CKRecordID new]` reading `implemented` beside a class row that is `absent`, or
# with no class row at all, says the class is here and not here in the same breath. A constant row
# is a global symbol and stands on its own, so only a method row is asked this.
orphan = sorted(key(r) for r in member_rows
                if r.get("status") == "implemented"
                and (owner(r["api"]) not in class_rows
                     or class_rows[owner(r["api"])].get("status") == "absent"))
def label(ks):
    return ["%s %s" % (k, a) for k, a in ks]
print("implementations in the %d sources: %d" % (len(files), len(impl)))
print("rows in values.json: %d" % len(rows))
print("implemented with no row: %d %s" % (len(without_row), label(without_row)))
print("rows with no definition: %d %s" % (len(without_code), label(without_code)))
print("marked absent but defined here: %d %s" % (len(wrong_status), label(wrong_status)))
print("member carried without its class: %d %s" % (len(orphan), label(orphan)))

# A CHECK THAT CANNOT FAIL IS NOT EVIDENCE, and this one could not: it printed its numbers and
# returned nothing, so `python3 ...; echo $?` read 0 whatever it had found. The gate's own rule is
# "built, but no entry in registry/" for a definition with no row; this is the other direction, a
# row with no code, and the third, a row that understates what is here. Each is a failure, and the
# exit says so.
if without_row:
    print("FAIL a definition with no registry row, which is the gate's \"built, but no entry in"
          " registry/\": %s" % ", ".join(label(without_row)))
if without_code:
    print("FAIL a row with no definition in this tree: %s" % ", ".join(label(without_code)))
if wrong_status:
    print("FAIL a row marked absent while the tree defines it, which is only for hardware the"
          " device lacks: %s" % ", ".join(label(wrong_status)))
if orphan:
    print("FAIL a member row carried while its class row is absent or missing, which says the"
          " class is here and not here at once: %s" % ", ".join(label(orphan)))
sys.exit(1 if (without_row or without_code or wrong_status or orphan) else 0)
