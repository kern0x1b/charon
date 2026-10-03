#!/usr/bin/env python3
"""selftest-registry-rows.py: the one reader the registry tools share, checked on every shape it has to
read and on the shape it must refuse.

    tools/selftest-registry-rows.py            exit 0 and a line per case, or exit 1 and the failures

The reason this exists, measured: `registry/Intents/constants.json` was
`{constants: {NAME: {introduced, rung}}, note, source}` and not a row list, and seven tools that walk
the registry read it as one - five with `document["entries"]` (KeyError) and two with a conditional
that left `entries` as None (TypeError). A reader that skips a file it cannot parse and a reader that
crashes on it cost the same thing, which is the 83 rows in it, and the duplicate it was written to
find: all 83 names are also rows of `Intents/ios10.json` or `Intents/ios18.json`, which nothing
reported while the file was unreadable. The coordinator's ruling of 2026-10-03 moved the manifest out
of the registry to `tools/intents/constants.json`, and this reader now refuses that shape by name.

So the cases are the two shapes that remain, the two refusals, and the one refusal that carries a
reason:

  1. `{"entries": [...]}`: the rows as they are, `api` read from the row, and the list handed back
     itself rather than a copy;
  2. `[...]`: a bare list, the same;
  3. a document holding no row member, and one holding both members the reader knows: refused with the
     keys named, because a shape this reader does not know is a file whose rows go uncounted, and an
     uncounted row cannot be told from a row that is not there;
  4. a document holding `constants`: refused, and the message names where that shape lives. This is the
     shape the Intents manifest had, so the refusal is what stops it being taught a second time;
  5. `tools/registry-duplicate-api.py` over a scratch registry holding two files that name one api: it
     must name the duplicate, and with the second file gone the duplicate is gone.

Each case builds its registry in a scratch directory of its own and never in the tree.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from registry_rows import ShapeError, documents, rows  # noqa: E402

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

    # The manifest's own shape, refused rather than read: its array length is 0, so a reader that walked
    # it saw none of its rows (measured with `xmake l` against modules/apple/backports.lua:1609).
    manifest = {"constants": {"SecondOne": {"introduced": "16.2"}, "FirstOne": {"introduced": "10.0"}},
                "note": "prose", "source": "tools/x.py"}
    refused_ok, message = refused(manifest)
    check("the manifest shape is refused, not read", refused_ok, message)
    check("the refusal says where that shape lives",
          refused_ok and "tools/intents/constants.json" in message, message)


def case_refusals():
    # Each case is the document, what is wrong with it, and a word of its own the message must carry,
    # so a refusal that says only "unknown shape" - which names nothing a fixer can use - fails here.
    for document, why, named in (({"note": "prose", "source": "tools/x.py"}, "an object with no row member", "note"),
                                 ({"entries": "not a list"}, "an object whose entries is not a list", "entries"),
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
        with open(os.path.join(registry, "ios16.json"), "w") as handle:
            json.dump({"framework": "Thing", "entries": [{"api": "Shared", "kind": "constant",
                                                          "status": "implemented"}]}, handle)
        with open(os.path.join(registry, "ios18.json"), "w") as handle:
            json.dump({"framework": "Thing", "entries": [{"api": "Shared", "kind": "constant",
                                                          "status": "implemented"}]}, handle)
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"),
                                os.path.join(scratch, "registry")], capture_output=True, text=True)
        check("a duplicate named by two files of one framework is named",
              found.returncode == 1 and "Shared" in found.stdout, found.stdout.strip()[:120])
        check("the reader counted both rows",
              "2 rows, 1 distinct api, 1 duplicated" in found.stdout, found.stdout.strip()[-80:])
        # The same tree with one file removed: the duplicate is gone, so the count is honest.
        os.remove(os.path.join(registry, "ios18.json"))
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


def case_documents_refuses_by_path():
    """A whole-tree walk meets the manifest and stops by name, not with a traceback naming neither."""
    scratch = tempfile.mkdtemp(prefix="selftest-registry-rows-")
    try:
        registry = os.path.join(scratch, "registry")
        os.makedirs(os.path.join(registry, "Thing"))
        with open(os.path.join(registry, "Thing", "ios16.json"), "w") as handle:
            json.dump({"entries": [{"api": "A"}]}, handle)
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"), registry],
                               capture_output=True, text=True)
        check("a walk over a clean registry claims its rows",
              found.returncode == 0 and "1 rows, 1 distinct api, 0 duplicated" in found.stdout,
              found.stdout.strip()[-80:])
        # Now the manifest is put back where it used to live, and every tool must name it and claim nothing.
        import shutil as _shutil
        _shutil.copyfile(os.path.join(ROOT, "tools", "intents", "constants.json"),
                         os.path.join(registry, "Thing", "constants.json"))
        found = subprocess.run([sys.executable, os.path.join(TOOLS, "registry-duplicate-api.py"), registry],
                               capture_output=True, text=True)
        check("the manifest under the registry is refused by one line, with no traceback",
              found.returncode == 1 and "Traceback" not in found.stderr and "refuses by name" in found.stderr,
              found.stderr.strip()[-120:])
        check("the refusal names the file it stopped on",
              "Thing" + os.sep + "constants.json" in found.stderr, found.stderr.strip()[-120:])
        check("the refusal says where that shape lives",
              "tools/intents/constants.json" in found.stderr, found.stderr.strip()[-120:])
        check("the refusal claims nothing about the tree",
              "nothing under" in found.stderr and "0 rows" not in found.stdout, found.stdout.strip()[-80:])
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def case_documents_walk():
    scratch = tempfile.mkdtemp(prefix="selftest-registry-rows-")
    try:
        os.makedirs(os.path.join(scratch, "Thing"))
        for relative in ("Thing/ios16.json", "Thing/ios18.json", "top.json"):
            with open(os.path.join(scratch, relative), "w") as handle:
                json.dump({"entries": [{"api": relative}]}, handle)
        found = documents(scratch)
        check("the walk reads every registry file under the root, at every depth",
              [os.path.relpath(path, scratch) for path, _ in found] ==
              ["Thing/ios16.json", "Thing/ios18.json", "top.json"],
              str([os.path.relpath(path, scratch) for path, _ in found]))
        check("the walk reads each file's rows through the one reader",
              sum(len(rows(document)) for _, document in found) == 3,
              str([(os.path.basename(p), len(rows(d))) for p, d in found]))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


for case in (case_shapes, case_refusals, case_tool_sees_the_duplicate,
             case_documents_refuses_by_path, case_documents_walk):
    case()

print("%d checks, %d failures" % (len(checks), len(failures)))
for failure in failures:
    print("FAIL  %s" % failure)
raise SystemExit(1 if failures else 0)