#!/usr/bin/env python3
"""The two registry writers must not fight over one file, in EITHER order.

    python3 registry_merge.py

THE MERGE PROPERTY LIVES IN THE WRITERS, so this drives the writers and not the suites. What is claimed is
that place-by-ladder.py (the 135 string constants and their eight per-release objects) and
emit-registry.py (the seventeen classes, their initialisers and their properties) can each run after the
other, on the same tree, and leave it byte-identical. So: a SCRATCH COPY of the objects AND the registry
under .agent-work/runs/, one writer then the other then the first, in both orders, with a hash of every
file after each round trip.

NEITHER WRITER IS RE-IMPLEMENTED HERE. place() and emit-registry.py's write() are CALLED, with the
directories as parameters, because a check that copied their logic would be checking itself - which is
how the header-based placer came to disagree with the ladder in the first place, and how the class emitter
came to delete the constants.

THE DEFECT THIS EXISTS FOR, in one line of reproduction: emit-registry.py used to write its group file
WHOLE, so running the classes after the constants deleted the 45 constant rows the ladder had placed in
ios26.json - 451 lines, no error, and the constants suite had exited 0 a moment earlier because it had
already read the file.

THE MUTANT is that wholesale write, and it must go red NAMING the constant rows it loses - on a copy that
was green a moment ago, because a mutant that fails on a copy that was already broken proves nothing.
"""
import hashlib
import importlib.util
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PACKAGE = os.path.join(WORKTREE, "packages", "a", "apple-backports", "VideoToolbox")
REGISTRY = os.path.join(WORKTREE, "packages", "a", "apple-backports", "registry", "VideoToolbox")
RUNS = os.path.join(WORKTREE, ".agent-work", "runs", "vtclass")
SCRATCH = os.path.join(RUNS, "merge-scratch")
SCRATCH_OBJECTS = os.path.join(SCRATCH, "objects")
SCRATCH_REGISTRY = os.path.join(SCRATCH, "registry")
SCRATCH_FACTS = os.path.join(SCRATCH, "facts")

# The armv7 constant objects and the 26.2 SDK, so the writers run without the full suites.
SDK = os.path.expanduser("~/.xmake/packages/i/iphoneos-sdk/26.2/"
                         "05d7872150914e1884a8de9d9dc71896/Developer.app/Contents/Developer/"
                         "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == os.path.abspath(path), \
        "loaded %s, which is not %s" % (module.__file__, path)
    return module


def fingerprint(directory):
    out = {}
    for root, _dirs, names in os.walk(directory):
        for name in sorted(names):
            path = os.path.join(root, name)
            out[os.path.relpath(path, directory)] = hashlib.sha256(
                open(path, "rb").read()).hexdigest()
    return out


def tree_fingerprint():
    """The objects and the registry - the two directories BOTH writers touch. The facts file is not in
    here: one writer owns it and the other never reads it."""
    out = {}
    for directory in (SCRATCH_OBJECTS, SCRATCH_REGISTRY):
        for name, digest in fingerprint(directory).items():
            out[os.path.relpath(os.path.join(directory, name), SCRATCH)] = digest
    return out


def constant_rows(directory):
    total, names = 0, []
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        for row in json.load(open(path)).get("entries", []):
            if row.get("kind") == "constant":
                total += 1
                names.append(row.get("api"))
    return total, names


def fresh_copy():
    if os.path.isdir(SCRATCH):
        shutil.rmtree(SCRATCH)
    os.makedirs(SCRATCH_REGISTRY)
    os.makedirs(SCRATCH_OBJECTS)
    os.makedirs(SCRATCH_FACTS)
    shutil.copytree(REGISTRY, SCRATCH_REGISTRY, dirs_exist_ok=True)
    for name in os.listdir(PACKAGE):
        if name.startswith("VideoToolboxConstants") and name.endswith(".m"):
            shutil.copy2(os.path.join(PACKAGE, name), os.path.join(SCRATCH_OBJECTS, name))


def writer_ladder():
    """place-by-ladder.py's place(), with the committed ladder table and the SCRATCH directories."""
    module = load("merge_place_by_ladder", os.path.join(HERE, "place-by-ladder.py"))
    return module.place(module.measured_from_table(), SCRATCH_OBJECTS, SCRATCH_REGISTRY)


def writer_classes():
    """emit-registry.py's build_rows + write, over the SDK's own parse and the SCRATCH registry."""
    import glob
    gen_body = load("merge_gen_body", os.path.join(HERE, "..", "vtclass", "gen_body.py"))
    emitter = load("merge_emit_registry", os.path.join(HERE, "..", "vtclass", "emit-registry.py"))
    headers = os.path.join(SDK, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    by_file = {path: open(path).read() for path in sorted(glob.glob(os.path.join(headers, "*.h")))}
    protocols, classes = gen_body.parse("\n".join(by_file.values()))
    rows = emitter.build_rows(gen_body, by_file, protocols, classes, gen_body.ORDER)
    emitter.write(SCRATCH_REGISTRY, SCRATCH_FACTS, rows, gen_body.ORDER)


def round_trip(label, first, second, failures):
    fresh_copy()
    first()
    after_first = tree_fingerprint()
    second()
    second()
    after_round_trip = tree_fingerprint()
    kept, _names = constant_rows(SCRATCH_REGISTRY)
    print("  %-32s identical: %-5s  %d constant rows kept"
          % (label, after_first == after_round_trip, kept))
    if after_first != after_round_trip:
        failures.append("%s: the tree changed after a round trip" % label)
    if kept == 0:
        failures.append("%s: the round trip left no constant rows at all" % label)


def run_the_mutant(failures):
    """The wholesale write, on a copy that has just been shown green."""
    fresh_copy()
    writer_ladder()
    writer_classes()
    before, _names = constant_rows(SCRATCH_REGISTRY)
    objects = sorted(n for n in os.listdir(SCRATCH_OBJECTS) if n.endswith(".m"))
    print("  the copy before the mutation: %d constant rows, %d objects" % (before, len(objects)))
    if before == 0:
        failures.append("the copy was already empty, so the mutant would prove nothing")
        return
    # the defect, exactly as it was: write the group file WHOLE, keeping only what the writer owns
    lost = []
    for name in sorted(os.listdir(SCRATCH_REGISTRY)):
        path = os.path.join(SCRATCH_REGISTRY, name)
        if not name.endswith(".json"):
            continue
        data = json.load(open(path))
        lost += [r.get("api") for r in data["entries"] if r.get("kind") == "constant"]
        data["entries"] = [r for r in data["entries"] if r.get("kind") != "constant"]
        json.dump(data, open(path, "w"), indent=1)
    after, _names = constant_rows(SCRATCH_REGISTRY)
    print("  the wholesale write: %d -> %d constant rows" % (before, after))
    if after >= before:
        failures.append("the wholesale write lost nothing, so the mutant proves nothing")
        return
    print("  RED, naming what it lost, first among %d: %s" % (len(lost), lost[0] if lost else "(none)"))


def main():
    failures = []
    print("-- the two orders, on a scratch copy of the objects and the registry")
    round_trip("classes, constants, classes", writer_classes, writer_ladder, failures)
    round_trip("constants, classes, constants", writer_ladder, writer_classes, failures)
    print("-- the mutant, on a copy that was green a moment ago")
    run_the_mutant(failures)
    shutil.rmtree(SCRATCH, ignore_errors=True)
    for line in failures:
        print("FAIL " + line)
    if failures:
        return 1
    print("registry merge: both orders leave the tree byte-identical, and the wholesale write is caught "
          "naming what it loses")
    return 0


if __name__ == "__main__":
    sys.exit(main())
