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
    """Every row: one per class, one per initialiser, one per property."""
    rows = []
    # _introduction() walks the headers per FILE so a row can name one; gen_body.initialisers() wants
    # them joined, because it matches a class across all of them at once.
    joined = "\n".join(sdk_text.values())
    for class_name in order:
        entry = classes[class_name]
        introduced, header = _introduction(sdk_text, class_name)
        release = "ios%s.json" % introduced.split(".")[0]
        base = {
            "introduced": introduced,
            "minimum": "6.0",
            "status": CLASS_ROW_STATUS,
            "facts": "facts/VideoToolbox/FrameProcessorClasses.md",
        }
        source_class = "SDK 26.2, %s, the class declaration's API_AVAILABLE line" % (header or "?")
        rows.append((release, dict(base, **{
            "api": class_name,
            "kind": "class",
            "reason": "the release has no VTFrameProcessor framework: iOS 6.1.3 carries "
                      "VideoToolbox.framework at /System/Library/Frameworks with the whole compression "
                      "and decompression session API, and none of the seventeen frame-processor classes "
                      "on the armv7 cache ladder",
            "effect": "the class exists, the release has no such class, and every member below is "
                      "answered from the port's own store",
            "source": source_class,
        })))
        for selector, arguments, _returns in gen_body.initialisers(joined, class_name):
            line = _header_line(sdk_text, class_name, selector.split(":")[0] + ":")
            rows.append((release, dict(base, **{
                "api": "-[%s %s]" % (class_name, selector),
                "kind": "method",
                "reason": "the designated initialiser of a class the release does not have; each argument "
                          "is stored under the property the SDK declares for it, resolved per class",
                "effect": "constructs the object and puts each argument in the store under that property's "
                          "own name, so the value comes back out of the property's own accessor",
                "source": "SDK 26.2, %s" % (line or "the class's own header"),
            })))
        for name, prop in entry["own"].items():
            line = _header_line(sdk_text, class_name, name)
            kinds = []
            if prop["class"]:
                kinds.append("class property")
            if prop["getter"] and prop["getter"] != name:
                kinds.append("getter=%s" % prop["getter"])
            rows.append((release, dict(base, **{
                "api": "%s.%s" % (class_name, name),
                "kind": "property",
                "reason": "a property of a class the release does not have%s"
                          % (", a " + " and a ".join(kinds) if kinds else ""),
                "effect": "answers from the port's own store under this property's name"
                          + (", retained, because the SDK declares no ownership annotation"
                             if _is_cf(gen_body, prop) else ""),
                "source": "SDK 26.2, %s" % (line or "the class's own header"),
            })))
    return rows


def write(registry_dir, facts_dir, rows, order):
    """The group files, and the facts file every row above points at."""
    groups = {}
    for release, row in rows:
        groups.setdefault(release, []).append(row)
    os.makedirs(registry_dir, exist_ok=True)
    written = []
    for release, entries in sorted(groups.items()):
        path = os.path.join(registry_dir, release)
        with open(path, "w") as handle:
            json.dump({"framework": "VideoToolbox",
                       "entries": sorted(entries, key=lambda e: (e["kind"], e["api"]))},
                      handle, indent=1)
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
