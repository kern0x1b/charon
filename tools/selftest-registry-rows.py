#!/usr/bin/env python3
"""selftest-registry-rows.py: the one reader the registry tools share, checked on every shape it has to
read and on the shape it must refuse.

    tools/selftest-registry-rows.py            exit 0 and a line per case, or exit 1 and the failures

The reason this exists, measured: `registry/Intents/constants.json` is
`{constants: {NAME: {introduced, rung}}, note, source}` and not a row list, and four tools that walk
the registry read it as one - two with `document["entries"]` (KeyError) and two with a conditional
that left `entries` as None (TypeError). A reader that skips a file it cannot parse and a reader that
crashes on it cost the same thing, which is the 83 rows in it, and the duplicate it was written to
find: all 83 names are also rows of `Intents/ios10.json` or `Intents/ios18.json`, which nothing
reported while the file was unreadable.

So the cases are the three shapes and the two refusals, and each is asked of the reader and of a tool
that uses it:

  1. `{"entries": [...]}`: the rows as they are, `api` read from the row;
  2. `[...]`: a bare list, the same;
  3. `{"constants": {NAME: {...}}}`: every constant is a row, its `api` the key it is filed under, and
     the row is a copy, so the document read is not changed;
  4. a document holding no row member, and one holding both: refused with the keys named, because a
     shape this reader does not know is a file whose rows go uncounted, and an uncounted row cannot be
     told from a row that is not there;
  5. `tools/registry-duplicate-api.py` over a scratch registry that holds one constants document and
     one entries document naming the same api: it must name the duplicate. That is the finding the
     crash was hiding, so the reader is only any use if a tool can still report it.

Each case builds its registry in a scratch directory of its own and never in the tree.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from registry_rows import ShapeError, apis, documents, rows  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")

checks = []
failures = []


def check(name, holds, detail=""):
    checks.append(name)
    if not holds:
        failures.append("%s%s" % (name, (": " + detail) if detail else ""))


def refused(document):
    """Whether the reader refuses this document, and what it says about it."""
    try:
        rows(document)
    except ShapeError as error:
        return True, str(error)
    return False, ""


def case_shapes():
    entries = {"framework": "Thing", "entries": [{"api": "A", "status": "implemented"},
                                                 {"api": "B", "introduced": "9.0"}]}
    got = rows(entries)
    check("the entries shape yields its rows with api read from the row",
          [row.get("api") for row in got] == ["A", "B"], str(got))
    check("the entries shape hands back the row objects themselves",
          got is entries["entries"], "a copy was made")

    bare = [{"api": "A"}, {"api": "B"}]
    check("a bare list is a row list", rows(bare) is bare)

    constants = {"constants": {"SecondOne": {"introduced": "16.2"}, "FirstOne": {"introduced": "10.0"}},
                 "note": "prose", "source": "tools/x.py"}
    got = rows(constants)
    check("the constants shape yields a row per constant", len(got) == 2, str(got))
    check("a constant's api is the key it is filed under",
          apis(constants) == ["FirstOne", "SecondOne"], str(apis(constants)))
    check("a constant's own fields are kept", got[0].get("introduced") == "10.0", str(got[0]))
    check("the constants shape does not write api back into the document",
          "api" not in constants["constants"]["FirstOne"], str(constants["constants"]))
    check("the note and the source are not rows: only the constants are",
          [row.get("api") for row in rows(constants)] == ["FirstOne", "SecondOne"]
          and not any(row.get("api") in ("note", "source") for row in rows(constants)),
          str(rows(constants)))


def case_refusals():
    # Each case is the document, what is wrong with it, and a word of its own the message must carry,
    # so a refusal that says only "unknown shape" - which names nothing a fixer can use - fails here.
    for document, why, named in (({"note": "prose", "source": "tools/x.py"}, "an object with no row member", "note"),
                                 ({"entries": [], "constants": {}}, "an object holding both row members", "constants"),
                                 ("a string", "a document that is not an object or a list", "str")):
        refused_ok, message = refused(document)
        check("refused: %s" % why, refused_ok, message)
        check("refused: %s names what it saw" % why, refused_ok and named in message, message)


def case_tool_sees_the_duplicate():
    """The finding the crash was hiding: a constants document and an entries document naming one api."""
    scratch = tempfile.mkdtemp(prefix="selftest-registry-rows-")
    try:
        registry = os.path.join(scratch, "registry", "Thing")
        os.makedirs(registry)
        with open(os.path.join(registry, "constants.json"), "w") as handle:
            json.dump({"constants": {"Shared": {"introduced": "16.2"}}, "note": "n", "source": "s"}, handle)
        with open(os.path.join(registry, "ios16.json"), "w") as handle:
            json.dump({"framework": "Thing", "entries": [{"api": "Shared", "kind": "constant",
                                                          "status": "implemented"}]}, handle)
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"),
                                os.path.join(scratch, "registry")], capture_output=True, text=True)
        check("a duplicate between a constants document and an entries document is named",
              found.returncode == 1 and "Shared" in found.stdout, found.stdout.strip()[:120])
        check("the reader counted both rows",
              "2 rows, 1 distinct api, 1 duplicated" in found.stdout, found.stdout.strip()[-80:])
        # The same tree without the constants document: the duplicate is gone, so the count is honest.
        os.remove(os.path.join(registry, "constants.json"))
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"),
                                os.path.join(scratch, "registry")], capture_output=True, text=True)
        check("with the constants document gone the duplicate is gone",
              found.returncode == 0 and "1 rows, 1 distinct api, 0 duplicated" in found.stdout,
              found.stdout.strip()[-80:])
        # An empty registry is a refusal in the tool that claims one, not a clean run over nothing.
        empty = os.path.join(scratch, "empty")
        os.makedirs(empty)
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"), empty],
                               capture_output=True, text=True)
        check("a registry with no file in it claims nothing",
              found.returncode == 0 and found.stdout.strip() == "0 rows, 0 distinct api, 0 duplicated",
              found.stdout.strip()[:120])
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def case_documents_walk():
    scratch = tempfile.mkdtemp(prefix="selftest-registry-rows-")
    try:
        os.makedirs(os.path.join(scratch, "Thing"))
        for relative in ("Thing/ios16.json", "Thing/constants.json", "top.json"):
            with open(os.path.join(scratch, relative), "w") as handle:
                json.dump({"entries": [{"api": relative}]} if relative != "Thing/constants.json"
                          else {"constants": {relative: {"introduced": "1.0"}}}, handle)
        found = documents(scratch)
        check("the walk reads every registry file under the root, at every depth",
              [os.path.relpath(path, scratch) for path, _ in found] ==
              ["Thing/constants.json", "Thing/ios16.json", "top.json"],
              str([os.path.relpath(path, scratch) for path, _ in found]))
        check("the walk reads each file's rows through the one reader",
              sum(len(rows(document)) for _, document in found) == 3,
              str([(os.path.basename(p), len(rows(d))) for p, d in found]))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


for case in (case_shapes, case_refusals, case_tool_sees_the_duplicate, case_documents_walk):
    case()

print("%d checks, %d failures" % (len(checks), len(failures)))
for failure in failures:
    print("FAIL  %s" % failure)
raise SystemExit(1 if failures else 0)