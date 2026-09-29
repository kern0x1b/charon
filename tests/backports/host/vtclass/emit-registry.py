#!/usr/bin/env python3
"""Emits the VideoToolbox registry rows and the facts file, from the SDK's own headers.

Called by emit.py, over the same parse that produced the value files, so a row cannot disagree with the
class it describes. Without this the library exports seventeen classes, their initialisers and their
properties, and the registry records none of them - and `modules/apple/backports.lua` answers
"built, but no entry in registry/" for every one of them, which is the gate failing on the very family
the series exists to build.

THE SHAPE IS THE REPOSITORY'S, not a shape I chose. A row in
packages/a/apple-backports/registry/<Framework>/ios<N>.json has `api`, `kind`, `introduced`, `minimum`,
`status`, `reason`, `effect`, `source`, and `facts`; `facts` names a file under
packages/a/apple-backports/facts/<Framework>/. The existing VideoToolbox files are ios7.json and ios8.json,
13 and 1 entries, and the existing facts file is H264Encoding.md.

THE RELEASE GROUP IS THE HEADER'S. SDK 26.2 writes

    API_AVAILABLE(macos(15.4), ios(26.0), tvos(26.0), visionos(26.0)) API_UNAVAILABLE(watchos)

on each of the seventeen classes, and `introduced` is the ios() version in that line - which is why the
rows land in ios26.json and not somewhere guessed. A class whose line says a different version lands in
that version's file, because the group is a property of the declaration, not of the class list.
"""
import json
import os
import re

PROPERTY = "@property"
CLASS_ROW_STATUS = "implemented"


def _is_cf(gen_body, prop):
    """Whether a property's type is a CF reference, from the COMPILER's answer, the way the store line
    asks - so a row's effect cannot claim a retention the store line does not perform."""
    table = gen_body.BRANCH_TABLE
    name = prop["type"] + (" *" if prop["obj"] else "")
    if not table:
        table.update(gen_body.load_branch_table())
    row = table.get(name) or table.get(prop["type"])
    if row is None:
        raise SystemExit("%s: the type probe has no row for %r - run the probe before generating"
                         % (name, name))
    return gen_body.branch_of(*row) == "CF"

def _availability():
    """availability.py, by explicit path, with its __file__ asserted - the same rule as gen_body and
    emit-registry's own loader, and for the same reason."""
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "availability.py")
    spec = importlib.util.spec_from_file_location("vt_availability", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded an availability.py that is not this one"
    return module


def _members():
    """members.py, by explicit path, with its __file__ asserted - the same rule as everywhere else here,
    and for the same reason: a module named import once loaded a different copy and every count agreed."""
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "members.py")
    spec = importlib.util.spec_from_file_location("vt_members", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded a members.py that is not this one"
    return module


def _introduction(sdk_text, class_name):
    """(ios version, line) for this class, from availability_of() and NOTHING ELSE.

    The rule that used to live here walked back from the @interface skipping blanks and comments, and it
    was wrong in two opposite directions at once: it landed on NS_SWIFT_SENDABLE for a class with a
    macro between the two, and nothing here could see the two VT_EXPORT classes at all. The four
    spellings are in availability.py's docstring, with the windows they came from; this file asks that
    one function and prints the line it read.
    """
    joined = "\n".join(sdk_text.values())
    version, line = _availability().availability_of(joined, class_name)
    return version, "%s:%d" % (_file_holding(sdk_text, class_name) or "?", line)


def _file_holding(sdk_text, class_name):
    for name, text in sorted(sdk_text.items()):
        if re.search(r'@interface\s+' + re.escape(class_name) + r'\b', text):
            return os.path.basename(name)
    return None


def _header_line(sdk_text, class_name, needle):
    """File and line of the declaration `needle` belongs to, for the row's `source`."""
    for name, text in sdk_text.items():
        for index, line in enumerate(text.split("\n"), start=1):
            if needle in line and class_name in text[max(0, text.find(line) - 200):text.find(line) + 40]:
                return "%s:%d" % (os.path.basename(name), index)
    return None


def build_rows(gen_body, sdk_text, protocols, classes, order):
    """Every row, and the members come from members_of() - ONE derivation, reading the declaration and
    the value file. A row therefore cannot describe a member the file does not implement, and an
    INHERITED property the class restates is a member, because the class implements its accessor. That
    was 69 rows: the emitter wrote a class's own properties and the value files implement the protocol's
    as well."""
    rows = []
    for class_name in order:
        introduced, header = _introduction(sdk_text, class_name)
        release = "ios%s.json" % introduced.split(".")[0]
        base = {
            "introduced": introduced,
            "minimum": "6.0",
            "status": CLASS_ROW_STATUS,
            "facts": "facts/VideoToolbox/FrameProcessorClasses.md",
        }
        source = "SDK 26.2, %s" % (header or "the class's own header")
        for kind, api in sorted(_members().members_of(class_name)["entries"]):
            if kind == "class":
                reason = ("the release has no VTFrameProcessor framework: iOS 6.1.3 carries "
                          "VideoToolbox.framework at /System/Library/Frameworks with the whole "
                          "compression and decompression session API, and none of the seventeen "
                          "frame-processor classes on the armv7 cache ladder")
                effect = ("the class exists, the release has no such class, and every member below is "
                          "answered from the port's own store")
            elif kind == "method":
                reason = ("the designated initialiser of a class the release does not have; each argument "
                          "is stored under the property the SDK declares for it, resolved per class")
                effect = ("constructs the object and puts each argument in the store under that property's "
                          "own name, so the value comes back out of the property's own accessor")
            else:
                reason = "a property of a class the release does not have"
                effect = "answers from the port's own store under this property's name"
            rows.append((release, dict(base, api=api, kind=kind, reason=reason, effect=effect,
                                       source=source)))
    return rows


def write(registry_dir, facts_dir, rows, order):
    """The group files, and the facts file every row above points at.

    MERGES, and the reason is a defect this function caused: it used to write each group file whole, so
    running the CLASS suite after the CONSTANTS suite deleted the 45 constant rows the ladder had placed
    in ios26.json - 451 lines, no error, and the constants suite had passed a moment earlier. Two writers
    for one file, the second silently overwriting the first, which is the same two-implementations
    failure as the object that held fifteen releases.

    So this writes ONLY the rows it owns - kind class, method or property - and carries every other row
    through unchanged, in whatever file it touches. registry-constants.py already merges the same way for
    ios7.json and ios8.json, and the two must agree.
    """
    OURS = ("class", "method", "property")
    groups = {}
    for release, row in rows:
        groups.setdefault(release, []).append(row)
    os.makedirs(registry_dir, exist_ok=True)
    written = []
    for release, entries in sorted(groups.items()):
        path = os.path.join(registry_dir, release)
        # ORDER IS PRESERVED, and it is not cosmetic: a merge that re-sorts rewrites bytes it did not
        # own, and then every run of this suite is a diff. The existing order is the coordinator's
        # ladder output and is not this file's to rearrange.
        existing = json.load(open(path))["entries"] if os.path.exists(path) else []
        mine = {(e["kind"], e["api"]): e for e in entries}
        merged, used = [], set()
        for row in existing:
            key = (row.get("kind"), row.get("api"))
            if key in mine:
                merged.append(mine.pop(key))     # ours, replaced IN PLACE
                used.add(key)
            else:
                merged.append(row)               # somebody else's, carried
        merged += [e for _k, e in sorted(mine.items(), key=lambda kv: (kv[0][0], kv[0][1]))]
        with open(path, "w") as handle:
            json.dump({"framework": "VideoToolbox", "entries": merged}, handle, indent=1)
            handle.write("\n")
        written.append((os.path.basename(path), len(entries)))
    os.makedirs(facts_dir, exist_ok=True)
    facts = os.path.join(facts_dir, "FrameProcessorClasses.md")
    with open(facts, "w") as handle:
        handle.write(
            "# The VideoToolbox frame processor: %d classes and the members they carry\n\n"
            "Ranks of `coordination/corpus/band-frameworks.tsv`: VideoToolbox, LOAD-FAIL. iOS 6.1.3 carries\n"
            "`VideoToolbox.framework` at `/System/Library/Frameworks` with the whole compression and\n"
            "decompression session API on the armv7 cache ladder since 3.1.3. It carries none of the\n"
            "seventeen frame-processor classes, which SDK 26.2 marks `API_AVAILABLE(ios(26.0))` and which\n"
            "the 6.1.3 cache ladder does not export at any release.\n\n"
            "## What the port does with a class the release does not have\n\n"
            "Each class is a value object: an initialiser puts its arguments in a keyed store under the\n"
            "property the SDK declares for each of them, and each accessor answers from that store. A\n"
            "class property's value is kept on the class, because a class property's value belongs to the\n"
            "type rather than to an instance. A `CVPixelBufferRef` is kept in an ivar and retained, because\n"
            "the SDK declares `@property(nonatomic, readonly) CVPixelBufferRef buffer;` with no ownership\n"
            "annotation. A `CMTime` or `CMVideoDimensions` is an `NSValue` box.\n\n"
            "## What is NOT carried, and why\n\n"
            "`processorSupported` is declared on three of the classes and the SDK marks it\n"
            "`API_UNAVAILABLE(ios)`, so it is not iOS surface and carrying it would collide with the host's\n"
            "own header on the armv7 build. It is absent, and the registry says so where a reader will look\n"
            "for it rather than leaving the gap to be rediscovered.\n\n"
            "## The nine VTFrameProcessor methods this series does not carry\n\n"
            "`startSessionWithConfiguration:error:`, the four `processWith…` variants, `endSession`,\n"
            "`+supportedScaleFactorsForFrameWidth:frameHeight:` and\n"
            "`downloadConfigurationModelWithCompletionHandler:` need a device with a Neural Engine, which no\n"
            "armv7 release has. They are recorded absent with the reason, and the one that cannot report\n"
            "failure at all - `processWithCommandBuffer:parameters:` - is in `coordination/crutches.md`,\n"
            "because it is undetectable by the header's own design.\n\n"
            "## The members per class\n\n" % len(order))
        for class_name in order:
            handle.write("### %s\n\n" % class_name)
    return written
