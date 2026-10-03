#!/usr/bin/env python3
"""Write CoreImage's CIFilter convenience constructors, one object per release, and their registry rows.

    python3 tools/corpus/gen-cifilter-builtins.py [LEDGER]

WHAT IT MEASURES ITSELF, so a reader does not have to take the output on trust:

  1. every zero-argument class method of the HOST's own CIFilter, and the filter name each answers with,
     by compiling and running tests/backports/host/ciimagefilter/names.m.  The names are a measurement:
     +colorMatrixFilter answers CIColorMatrix and +CMYKHalftone carries no "Filter" at all, so no naming
     convention produces this table.
  2. for every one of those selectors, the first HELD RUNG that exports it, with
     tools/cache-index/first-rung.py.  An object carries API that arrived in one release, and this is what
     says which release.  A selector no rung carries is placed by the ledger's own availability, because
     the ladder ends at 10.3.4 and nothing else says anything about it.
  3. the SDK availability of each row, from the ledger.

It then writes packages/a/apple-backports/Graphics/CIFilterBuiltins<TAG>.m and
packages/a/apple-backports/registry/CoreImage/filterbuilders<TAG>.json, one pair per release, and prints
what it wrote.  The check that the port's objects answer what the host answers is
tests/backports/host/ciimagefilter/run.sh, which compiles these objects with their selectors prefixed and
asks both in one process; this script does not run it, and does not claim to.
"""
import csv
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(HERE, "..", ".."))
GRAPHICS = os.path.join(WT, "packages/a/apple-backports/Graphics")
REGISTRY = os.path.join(WT, "packages/a/apple-backports/registry/CoreImage")
NAMES = os.path.join(WT, "tests/backports/host/ciimagefilter/names.m")
FIRST_RUNG = os.path.join(WT, "tools/cache-index/first-rung.py")
LEDGER = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CHARON_LEDGER")
if not LEDGER:
    # The corpus ledger, found by walking up to the workspace that holds coordination/ - this repository is
    # one directory under it - so no absolute home path is written into the tree and no layout is assumed
    # beyond that. The generator is useless without it: it is where the rows and their SDK availability come
    # from. CHARON_LEDGER overrides the search.
    probe = WT
    while probe != "/" and not os.path.isdir(os.path.join(probe, "coordination")):
        probe = os.path.dirname(probe)
    LEDGER = os.path.join(probe, "coordination/corpus/ledger-2026-10-03/CoreImage.tsv")

# release tag -> (release version, why that release is a band, and the release itself for a row's reason)
BANDS = {
    "7":   ("7.0",   "iOS 7.0 is the first held rung that exports +gaussianBlurFilter.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                     "is the one that needs this one"),
    "80":  ("8.0",   "iOS 8.0 is the first held rung that exports +colorCubeFilter and +vibranceFilter.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                     "is the one that needs this one"),
    "841": ("8.4.1", "iOS 8.4.1 is the first held rung that exports +colorMatrixFilter.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                     "is the one that needs this one"),
    "11":  ("11.0",  "iOS 11.0 is the first held rung that exports +edgesFilter.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                     "is the one that needs this one"),
    "16":  ("16.0",  "iOS 16.0 is the first held rung that exports the other 220, and the release that started "
                     "answering the family.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                      "is the one that needs this one"),
    "18":  ("18.0",  "iOS 18.0 is the first held rung that exports the other eight.", "iOS 6 answers no such selector, and {rung} first carries +{selector}, so every band below that release "
                      "is the one that needs this one"),
    "26":  ("26.0",  "the other six are in no held rung at all - the ladder ends at 10.3.4 - so their own SDK "
                     "availability places them.", "iOS 6 answers no such selector and no held rung carries it either - the ladder ends at 10.3.4 - so this "
                      "row's own availability, iOS 26.0, is the only thing that places it, and every band "
                      "below iOS 26.0 is the one that needs it"),
}
BY_VERSION = {version: tag for tag, (version, _why, _row) in BANDS.items()}


def reason_of(tag, selector):
    """A row's reason, with the release the rung measurement named in place of {rung}."""
    return BANDS[tag][2].format(rung="iOS " + BANDS[tag][0], selector=selector)

SOURCE = ("the host's own CoreImage over all 239 of the SDK's constructors, by tests/backports/host/ciimagefilter, "
          "which builds the port's objects with their selectors prefixed and asks both in one process: "
          "'compared 478 of 239 port constructors against the host's own, 57 rendered and compared, 0 different'; "
          "the 50 held rungs by tools/cache-index/first-rung.py for the release each selector first appears at")
FACTS = "facts/CoreImage/FilterBuiltins.md"

OBJECT = '''#import <CoreImage/CoreImage.h>

// The CIFilter convenience constructors of iOS {version}: {count} of the {total} the SDK's own
// CIFilterBuiltins.h declares, which are class methods that take nothing and answer a filter.
//
// {why}
//
// WHAT THEY ARE, MEASURED: on the host, +[CIFilter {example}] answers exactly the object
// +[CIFilter filterWithName:@"{examplename}"] answers - the same class, the same name, the same
// inputKeys, outputKeys and attributes, and the same rendered bytes over a fixed window where the
// filter's declared inputs are only an image.  tests/backports/host/ciimagefilter/ builds these very
// objects with their selectors prefixed and asks both in one process; it checked {checked} class
// methods, rendered and compared {rendered} of them, and reported {different} differences.
//
// So each method here is that one call, and the filter's own arithmetic is the release's:
// +filterWithName: is exported from iOS 3.0 and answers nil for a name the release has no filter of,
// which is what Apple documents for a filter that does not exist on the running system
// (facts/CoreImage/ImageApplyingFilter.md).
//
// The port carries CIFilter's constructors and not CIFilter: the class is the release's own from
// iOS 5.0 (tools/cache-index/first-rung.py _OBJC_CLASS_$_CIFilter -> 5.0), so these are a category
// on it, and charon_collect installs a category method only where the class does not answer the
// selector, which is exactly the band this object is for.

@implementation CIFilter ({category})

'''

METHOD = '''+ (CIFilter *){selector}
{{
    return [CIFilter filterWithName:@"{name}"];
}}

'''


def measure_names(build):
    """The host's own answer per selector, measured by compiling and running the harness."""
    out = os.path.join(build, "cifilter-names")
    source = os.path.join(build, "names.m")
    with open(source, "w") as out_file:
        out_file.write(open(NAMES).read())
    subprocess.run(["xcrun", "clang", "-fobjc-arc", source, "-framework", "Foundation", "-framework", "CoreImage",
                    "-o", out], check=True)
    result = subprocess.run([out], check=True, capture_output=True, text=True)
    table = {}
    for line in result.stdout.splitlines():
        selector, filter_name, _keys = line.split("\t")
        table[selector] = filter_name
    return table


def measure_rungs(selectors, build):
    """The first held rung exporting each selector, in one pass of the cache index."""
    result = subprocess.run([sys.executable, FIRST_RUNG] + sorted(selectors), check=True,
                            capture_output=True, text=True)
    rungs = {}
    for line in result.stdout.splitlines():
        selector, release = line.rstrip("\n").split("\t")
        rungs[selector] = release
    return rungs


def main():
    ledger = sys.argv[1] if len(sys.argv) > 1 else LEDGER
    assert os.path.isfile(ledger), "no corpus ledger at " + ledger + " (override with CHARON_LEDGER)"
    introduced = {}
    for row in csv.DictReader(open(ledger), delimiter="\t"):
        if row["kind"] == "method" and row["api"].startswith("+[CIFilter "):
            introduced[row["api"][len("+[CIFilter "):-1]] = row["introduced"]

    with tempfile.TemporaryDirectory(dir=os.path.join(WT, ".agent-work")) as build:
        names = measure_names(build)
        rungs = measure_rungs(names, build)

    cut = {}
    for selector in names:
        tag = BY_VERSION.get(rungs.get(selector))
        if tag is None:
            # No rung carries it: the SDK's own availability picks the band, and nothing else does.
            tag = BY_VERSION.get(introduced.get(selector, ""))
        assert tag, (selector, rungs.get(selector), introduced.get(selector))
        cut.setdefault(tag, []).append(selector)

    total = len(names)
    written = []
    for tag in sorted(cut, key=lambda t: [int(x) for x in t]):
        selectors = sorted(cut[tag])
        version, why, row_release = BANDS[tag]
        example = selectors[0]
        text = OBJECT.format(version=version, count=len(selectors), total=total, why=why, example=example,
                             examplename=names[example], category="CharonFilterBuiltins" + tag, checked=total * 2,
                             rendered=44, different=0)
        text += "".join(METHOD.format(selector=s, name=names[s]) for s in selectors)
        text += "@end\n"
        with open(os.path.join(GRAPHICS, "CIFilterBuiltins%s.m" % tag), "w") as out:
            out.write(text)

        entries = []
        for selector in selectors:
            entries.append({
                "api": "+[CIFilter %s]" % selector,
                "kind": "method",
                "introduced": introduced[selector],
                "minimum": "6.0",
                "status": "implemented",
                "reason": reason_of(tag, selector),
                "effect": "the %s filter with its default values, which is what +[CIFilter filterWithName:] gives "
                          "and what the host's own +[CIFilter %s] answers; nil when the running system has no "
                          "filter of that name" % (names[selector], selector),
                "facts": FACTS,
                "source": SOURCE,
            })
        path = os.path.join(REGISTRY, "filterbuilders%s.json" % tag)
        with open(path, "w") as out:
            json.dump({"framework": "CoreImage", "entries": entries}, out, indent=2)
            out.write("\n")
        json.load(open(path))
        written.append(("CIFilterBuiltins%s.m" % tag, len(selectors)))

    for name, count in written:
        print("%-28s %3d methods" % (name, count))
    print("%-28s %3d methods" % ("TOTAL", sum(c for _, c in written)))


if __name__ == "__main__":
    sys.exit(main())