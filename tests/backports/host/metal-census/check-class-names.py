#!/usr/bin/env python3
"""check-class-names.py - no registry text may name a MANGLED form of its own class.

    python3 tests/backports/host/metal-census/check-class-names.py
    SELF_TEST=1 python3 tests/backports/host/metal-census/check-class-names.py

A row's `reason` and `effect` are prose a reader trusts, and they may name a class. The defect this
catches is a name that is the row's OWN api with a piece of it lost or gained - `CharonMTL<Name>`,
`CharonMetal<Name>`, or `<Name>` with its `MTL` stripped by a fix for the previous one - which reads
like a class and is defined in no file. Both of those shipped here, and each was caught by a
reviewer reading the prose rather than by anything in the tree.

The test is deliberately NARROW: a candidate is flagged only when it is a proper substring of the
row's own api, at least six characters, and CamelCase. Ordinary prose is not flagged, a name the
package or the SDK declares is never flagged, and a name in the allow-list is not flagged - the
allow-list naming each exception and why, so the check can be green AND honest rather than widened
into something that reads a thousand English sentences.

It reads the registries themselves, so a row cannot be written without being scanned, and it prints
how many names it examined so a run that examined nothing cannot say OK.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PKG = os.path.join(ROOT, "packages")
REGISTRIES = os.path.join(PKG, "a", "apple-backports", "registry")
ALLOW = os.path.join(HERE, "class-name-allowlist.txt")

# A CamelCase token: at least two humps, so "Apple" and "The" are not candidates.
CANDIDATE = re.compile(r"(?<![A-Za-z0-9_])([A-Z][a-z0-9]*(?:[A-Z][a-z0-9]*)+)"
                       r"(?![A-Za-z0-9_]|\.(?:h|m|c|mm))")

# CLASS-SHAPED IS NOT THE SAME AS CAMEL-CASE, and the difference is the whole scan. A sentence says
# "mirrored to CloudKit" and "FileProvider arrived in iOS 11.0" - those are FRAMEWORK NAMES, not
# classes - and "the OpenID-shaped request" is an English compound. What a class name has, and a
# framework word in a sentence does not, is the SHAPE OF A TYPE: it begins with a framework
# initialism, or it ends in one of the nouns a type is named after. This gate is what makes removing
# the substring filter safe: that filter said WHICH names to look at by requiring a relation to the
# row's own api, and this says the same thing without guessing what shape a mistake takes - a
# Charon-prefixed name and an invented one are both caught, and English is not.
PREFIXES = ("MTL", "MTK", "Charon", "NS", "CF", "CG")
SUFFIXES = ("Descriptor", "Encoder", "Buffer", "Texture", "Heap", "Fence", "Library", "Pass",
            "Command", "Function", "State", "Table", "Acceleration", "Scope", "Array", "Pipeline",
            "Counter", "Log", "Container", "Constant", "Argument", "Binding", "Attachment",
            "Archive", "Structure", "Manager", "Expression", "Geometry", "Sample")


ENUM_BLOCK = re.compile(r"\{(?:[^{}]|//[^\n]*\n)*\}")


def enumerators(text):
    """Every case named inside an NS_ENUM / NS_OPTIONS block.

    A case is a declared name and is not a class - NSNotFound, NSEntity, MTLBindingTypeBuffer - and a
    line-anchored match for them found only the ones that sit alone on a line, which is why the
    registry prose about NSNotFound was being reported as naming an undefined class.
    """
    out = set()
    for m in re.finditer(r"NS_(?:ENUM|OPTIONS)[A-Z_]*\s*\([^)]*\)\s*", text):
        block = ENUM_BLOCK.search(text, m.end())
        if not block:
            continue
        for name in re.findall(r"\b([A-Z][A-Za-z0-9_]*)\b", block.group(0)):
            out.add(name)
    return out


def class_shaped(name):
    if name.startswith(PREFIXES) and len(name) >= 6:
        return True
    return name.endswith(SUFFIXES)


def sdk_framework_dirs():
    """EVERY framework's headers in the SDK the package compiles against, not just Metal's.

    Scanning only Metal found a hundred false alarms: a selector row's prose names its RECEIVER
    class - `-[AVAssetTrack associatedTracksOfType:]` says "the port's AVAssetTrack" - and that class
    is declared by AVFoundation, not by Metal. The whole SDK is 3,573 headers and 0.8 seconds, so
    there is no reason to be half-blind.
    """
    out = []
    home = os.path.expanduser("~")
    for base, _d, _f in os.walk(os.path.join(home, ".xmake", "packages", "i", "iphoneos-sdk", "16.4")):
        candidate = os.path.join(base, "System", "Library", "Frameworks")
        if os.path.isdir(candidate):
            out.append(candidate)
    return out


# THE EXPENSIVE HALF IS CACHED, AND ONLY IT. Reading the SDK's export tables cost 34.7 seconds and
# 1.5 GB on every run, and the answer changes only when the SDK does - while the in-repo sources are
# 1,177 files worth about half a second, and change with every commit, so caching them would
# invalidate on every edit to buy nothing. The index is a SORTED TEXT FILE, one name per line, and
# the steady-state process holds only the candidates, never the 359,305 names: a merge-join over a
# sorted file answers every lookup in one pass and no memory.
def sdk_root():
    """THE ONE SDK the package compiles against, found by its SDKSettings.json the way the other
    harnesses find it. The shared store holds sixteen copies of 16.4 and reading all of them was
    sixteen times the work for the same names."""
    store = os.path.join(os.path.expanduser("~"), ".xmake", "packages", "i", "iphoneos-sdk", "16.4")
    if not os.path.isdir(store):
        return None
    for entry in sorted(os.listdir(store)):
        sdk = os.path.join(store, entry, "Developer.app", "Contents", "Developer", "Platforms",
                           "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS16.4.sdk")
        if os.path.isfile(os.path.join(sdk, "SDKSettings.json")):
            return sdk
    return None


CACHE_ROOT = os.environ.get("CHARON_CACHE", os.path.join(os.path.expanduser("~"), ".charon", "cache"))
# BUMPED whenever the extraction below changes, so a stale index is never read as current.
SDK_INDEX_VERSION = 1


def _tbd_list(sdk):
    out = []
    for sub in ("usr/lib", "System/Library/Frameworks"):
        root = os.path.join(sdk, sub)
        for base, _d, files in os.walk(root):
            for f in files:
                if f.endswith(".tbd"):
                    out.append(os.path.join(base, f))
    return out


def sdk_index_key(sdk):
    """A hash of everything the index depends on: the SDK's own identity, and every table's path,
    size and mtime. A table that is added, removed, resized or touched changes the key, and the index
    is rebuilt under the new one - which is what the self-test changes to prove it."""
    import hashlib
    h = hashlib.sha256()
    h.update(b"class-names-sdk-index-v%d\n" % SDK_INDEX_VERSION)
    settings = os.path.join(sdk, "SDKSettings.json")
    try:
        with open(settings, "rb") as fh:
            h.update(fh.read())
    except OSError:
        h.update(b"no SDKSettings.json")
    entries = []
    for path in _tbd_list(sdk):
        try:
            st = os.stat(path)
        except OSError:
            continue
        entries.append("%s\t%d\t%d" % (os.path.relpath(path, sdk), st.st_size, st.st_mtime_ns))
    for line in sorted(entries):
        h.update(line.encode("utf-8", "replace") + b"\n")
    return h.hexdigest()[:32]


# The same tokens the uncached version found, read a LINE at a time. Reading a whole .tbd into a
# string and running finditer over it is what held a gigabyte; a line is bounded and the line
# carrying a framework's whole symbol list is the only large one.
_TOKEN = re.compile(r"[_$A-Za-z][A-Za-z0-9_$]*")
_DEFINE = re.compile(r"#\s*define\s+([A-Z][A-Za-z0-9_]+)")
_CONST = re.compile(r"\b(?:static\s+)?(?:extern\s+)?const\s+[A-Za-z_][A-Za-z0-9_ ]*?"
                    r"\s([A-Z][A-Za-z0-9_]*)\s*(?:[A-Za-z_][A-Za-z0-9_]*)?\s*=")
_ENUM_HEAD = re.compile(r"NS_(?:ENUM|OPTIONS)[A-Z_]*\s*\([^)]*\)\s*")
_IDENT = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")


def _names_in_text(path, out):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            for m in _TOKEN.finditer(line):
                name = m.group(0)
                if name.startswith("_"):
                    out.add(name.lstrip("_").split("$")[-1])
            for rx in (_DEFINE, _CONST):
                m = rx.search(line)
                if m:
                    out.add(m.group(1))


# A declaration can span lines - a typedef runs on - so the multi-line forms are matched over
# CHUNKS with a line of overlap rather than over the whole file, which is what held a gigabyte.
_CHUNK = 2000
_OBJC_DECL = re.compile(r"@(?:implementation|interface|protocol)\s+(\w+)")
_TYPEDEF = re.compile(r"typedef[^;]*?\b(\w+)\s*;")
_CALLABLE = re.compile(r"\b((?:NS|CF|CG|MTL|MTK|dispatch_|objc_)[A-Za-z0-9_]+)\s*\(")


def _header_forms(path, out):
    """The multi-line declarations in a HEADER: an @interface, a typedef, a C function, a category.

    A class the SDK declares as `@interface NSBlock` and a typedef'd name must both be known, or the
    scan reports real SDK types as undefined - which is what it did on the first cached run.
    """
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        prev = ""
        while True:
            block = []
            for _ in range(_CHUNK):
                line = fh.readline()
                if not line:
                    break
                block.append(line)
            if not block:
                break
            text = prev + "".join(block)
            for rx in (_OBJC_DECL, _TYPEDEF, _CALLABLE):
                for m in rx.finditer(text):
                    out.add(m.group(1))
            # a category names its class too
            for m in re.finditer(r"@interface\s+(\w+)\s*\(", text):
                out.add(m.group(1))
            prev = block[-1] if block else ""


def _enumerators(path, out):
    with open(path, encoding="utf-8", errors="replace") as fh:
        depth, collecting = 0, False
        for line in fh:
            for m in _ENUM_HEAD.finditer(line):
                collecting, depth = True, 0
            if not collecting:
                continue
            for m in _IDENT.finditer(line):
                out.add(m.group(1))
            depth += line.count("{") - line.count("}")
            if depth <= 0 and "{" in line:
                collecting = False


# THE HEADER, and it is what makes a CORRUPT index self-heal. A cache that is only rebuilt when it
# is MISSING will happily serve a truncated one: a half-written file from an interrupted run is read
# as current, and every name past the cut is reported undefined - which is about seventy false
# failures. The key cannot fix that on its own, because the key is computed BEFORE the index exists
# and putting the index's own size INTO the key would be circular. So the first line of the file
# states how many names it should hold, and a read that finds a different count rebuilds.
INDEX_HEADER = "# charon-class-names-index v%d names %d key %s\n"


def index_is_sane(path, key):
    """Does the cached index say it is complete, and is it?"""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
            if not first.startswith("# charon-class-names-index"):
                return False, "no header"
            #   # charon-class-names-index v1 names <n> key <key>
            parts = first.split()
            if len(parts) < 7 or parts[0] != "#" or parts[1] != "charon-class-names-index":
                return False, "no header"
            if parts[2] != "v%d" % SDK_INDEX_VERSION:
                return False, "written by another version of the extraction"
            if parts[6] != key:
                return False, "written under another key"
            declared = int(parts[4])
            counted = sum(1 for _ in fh)
            if counted != declared:
                return False, "truncated: %d names, the header says %d" % (counted, declared)
    except (OSError, ValueError) as exc:
        return False, "unreadable (%s)" % exc
    return True, ""


def build_sdk_index(sdk, dest):
    """Write every name the SDK declares to `dest`, sorted and deduplicated."""
    names = set()
    for path in _tbd_list(sdk):
        _names_in_text(path, names)
    for sub in ("System/Library/Frameworks",):
        root = os.path.join(sdk, sub)
        for base, _d, files in os.walk(root):
            for f in files:
                if f.endswith(".h"):
                    p = os.path.join(base, f)
                    _names_in_text(p, names)
                    _header_forms(p, names)
                    _enumerators(p, names)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".tmp%d" % os.getpid()
    key = sdk_index_key(sdk)
    with open(tmp, "w", encoding="utf-8") as out:
        out.write(INDEX_HEADER % (SDK_INDEX_VERSION, len(names), key))
        for name in sorted(names):
            out.write(name + "\n")
    os.replace(tmp, dest)
    return names


def sdk_index():
    """The path of the cached SDK index, building it if the key has moved."""
    sdk = sdk_root()
    if not sdk:
        return None
    key = sdk_index_key(sdk)
    path = os.path.join(CACHE_ROOT, "class-names", "sdk-%s-v%d.txt" % (key, SDK_INDEX_VERSION))
    if not os.path.isfile(path):
        build_sdk_index(sdk, path)
        return path
    sane, why = index_is_sane(path, key)
    if not sane:
        # A CORRUPT INDEX IS REBUILT, not served. The key has not moved and the key cannot move -
        # it is computed before the index exists - so completeness is stated in the file itself.
        print("  the cached index is incomplete (%s), so it is rebuilt" % why)
        build_sdk_index(sdk, path)
    return path


def index_lookup(index_path, wanted):
    """Which of `wanted` the sorted index contains, in ONE pass and without holding the index.

    Both sides are sorted, so this is a merge-join: advance the candidate pointer whenever the
    index's line reaches it. The whole 359,305-line file is read once and nothing is stored."""
    if not wanted or not index_path:
        return set()
    todo = sorted(wanted)
    found, i, n = set(), 0, len(todo)
    with open(index_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            name = line.rstrip("\n")
            while i < n and todo[i] < name:
                i += 1
            if i >= n:
                break
            if todo[i] == name:
                found.add(name)
                i += 1
                if i >= n:
                    break
    return found


def package_names():
    """The names the IN-REPO sources declare. Small, and they change with every commit, so they are
    read live rather than cached."""
    names = set()
    for base, _dirs, files in os.walk(PKG):
        if os.sep + "registry" + os.sep in base or os.sep + "obj" + os.sep in base:
            continue
        for f in files:
            if f.endswith((".m", ".h")):
                p = os.path.join(base, f)
                _names_in_text(p, names)
                _header_forms(p, names)
                _enumerators(p, names)
    return names


def allow_list():
    out = set()
    if os.path.isfile(ALLOW):
        for line in open(ALLOW, encoding="utf-8"):
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(line.split()[0])
    return out


def registries():
    for d in sorted(os.listdir(REGISTRIES)):
        full = os.path.join(REGISTRIES, d)
        if os.path.isdir(full):
            for f in sorted(os.listdir(full)):
                if f.endswith(".json"):
                    yield os.path.join(full, f)


def candidates_in_prose():
    """Every class-shaped name in a class or protocol row's prose, with the row it came from.

    These are the only names that are ever looked up, and there are a few thousand of them, so they
    are the only set the steady-state process holds."""
    found = []
    for path in registries():
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        # a registry is either {"entries": [...]} or a bare list, and the Accessibility stack
        # landed on the new base with the second shape
        rows = doc if isinstance(doc, list) else doc.get("entries", [])
        for row in rows:
            # ONLY CLASS AND PROTOCOL ROWS. A constant row's prose legitimately names the VALUE it
            # carries - MicroPDF417 for AVMetadataObjectTypeMicroPDF417Code - and a method row's
            # prose names its receiver; neither claims the port defines a type.
            if row.get("kind") not in ("class", "protocol"):
                continue
            api = row.get("api", "")
            text = " ".join(str(row.get(k, "")) for k in ("reason", "effect"))
            for m in CANDIDATE.finditer(text):
                # COUNTED FIRST, then filtered. A run that examined nothing must not be able to say
                # OK, and a count taken after the filters would be zero on a healthy tree - which is
                # the "a check that examined nothing said it passed" defect.
                found.append((api, m.group(1), os.path.relpath(path, ROOT)))
    return found


def scan(planted=None):
    """Every candidate, and the ones nothing declares.

    Two passes: collect the candidates, then answer every lookup at once - one merge-join over the
    sorted SDK index, and a membership test against the small in-repo set."""
    all_candidates = candidates_in_prose()
    examined = len(all_candidates)
    index = sdk_index()
    live = package_names()
    allow = allow_list()
    unresolved = set()
    for _api, name, _p in all_candidates:
        if not class_shaped(name):
            continue
        if name in live or name in allow:
            continue
        unresolved.add(name)
    declared = index_lookup(index, unresolved)
    hits = []
    for api, name, path in all_candidates:
        if name == api or name in declared or name in live or name in allow:
            continue
        if not class_shaped(name):
            continue
        hits.append((api, name, path))
    if planted:
        victim = planted
        mangled = victim[3:] if victim.startswith("MTL") else victim
        if mangled and mangled not in declared and mangled not in live:
            examined += 1
            hits.append((victim, mangled, "<planted>"))
    return examined, hits


PLANTS = (
    # (label, the name a row's prose would carry, why it must be reported)
    ("the MTL-stripped slip", "ComputePassDescriptor",
     "the n7 bug: the api with its MTL lost"),
    ("the Charon-prefixed slip", "CharonMTLComputePassDescriptor",
     "the n6 bug: the name LONGER than the api, which the old substring filter skipped"),
    ("a wholly invented name", "MTLNoSuchDescriptorAnywhere",
     "no relation at all to any api"),
    ("a known good name", "MTLComputePassDescriptor",
     "declared by the tree, and must NOT be reported"),
)


def planted_report(plant):
    """Put ONE name through the scan's own decision and say whether it would be reported.

    Not through the real tree, which is clean: the plants are names that no row carries, so looking
    for them in a clean tree proves nothing at all. This applies exactly the three tests scan() applies
    - is it class-shaped, is it declared, is it the row's own api - to the planted name, and no more
    than that, so a control that stops catching a slip is a control that has stopped testing."""
    api, name = plant
    index = sdk_index()
    live = package_names()
    allow = allow_list()
    declared = (name in live) or (name in allow) or bool(index_lookup(index, [name]))
    reported = (not declared) and class_shaped(name) and name != api
    return reported, declared


def cache_invalidation_self_test():
    """THE CACHE MUST BE REBUILT WHEN ITS KEY MOVES, and that is proven on a scratch SDK.

    A cached index that is never rebuilt is worse than no cache: it answers every lookup with what
    was true when it was written. So this builds the index for a scratch SDK, touches one of its
    tables, and requires the key - and with it the index - to move. Nothing here touches the real
    SDK, and the scratch lives under the run directory, not in /tmp.
    """
    scratch = os.path.join(os.path.dirname(ALLOW), "..", "..", "..", "..", ".agent-work", "runs",
                           "metal-census", "class-names-selftest")
    sdk = os.path.join(scratch, "sdk", "usr", "lib")
    os.makedirs(sdk, exist_ok=True)
    with open(os.path.join(scratch, "sdk", "SDKSettings.json"), "w", encoding="utf-8") as fh:
        fh.write('{"self-test": true}\n')
    tbd = os.path.join(sdk, "libself.tbd")
    with open(tbd, "w", encoding="utf-8") as fh:
        fh.write("!tapi-tbd\n  symbols: [ '_SelfTestOne' ]\n")
    before_key = sdk_index_key(os.path.join(scratch, "sdk"))
    before = os.path.join(scratch, "index-%s.txt" % before_key)
    build_sdk_index(os.path.join(scratch, "sdk"), before)
    if not os.path.isfile(before):
        return "the scratch index was not built"
    # TOUCH THE TABLE: the key is a hash of each table's size and mtime, so this must move it.
    os.utime(tbd, None)
    after_key = sdk_index_key(os.path.join(scratch, "sdk"))
    if after_key == before_key:
        return "touching a table did not move the key, so a stale index would be read as current"
    after = os.path.join(scratch, "index-%s.txt" % after_key)
    build_sdk_index(os.path.join(scratch, "sdk"), after)
    if not os.path.isfile(after):
        return "the rebuilt index was not written"
    if os.path.realpath(before) == os.path.realpath(after):
        return "the rebuild wrote the same path"
    os.remove(before)
    os.remove(after)
    return None


def main():
    if "--self-test" in sys.argv or os.environ.get("SELF_TEST"):
        rc = 0
        for label, name, why in PLANTS:
            good = label.startswith("a known good")
            reported, _known = planted_report(("MTLComputePassDescriptor", name))
            if good and reported:
                print("  FAIL  %-26s is reported and must not be" % label)
                rc = 1
            elif good:
                print("  ok    %-26s NOT reported, as it must not be (%s)" % (label, why))
            elif reported:
                print("  ok    %-26s reported as %r" % (label, name))
            else:
                print("  FAIL  %-26s is NOT reported and must be (%s)" % (label, why))
                rc = 1
        # and the real tree, which must be clean
        _, hits = scan()
        if hits:
            print("  FAIL  the real tree is not clean: %s" % hits[0])
            rc = 1
        else:
            print("  ok    the real tree is clean")
        # A TRUNCATED INDEX UNDER AN UNCHANGED KEY MUST BE REBUILT. This is the reviewer's case and
        # it is not the same as the key moving: the key cannot move, because it is computed before
        # the index exists. So the file is cut in half and the completeness header must catch it.
        index = sdk_index()
        if index:
            whole = os.path.getsize(index)
            keep = max(1, whole // 2)
            with open(index, "r+", encoding="utf-8") as fh:
                fh.truncate(keep)
            sane, why = index_is_sane(index, sdk_index_key(sdk_root()))
            if sane:
                print("  FAIL  a truncated index passed its own completeness check")
                rc = 1
            else:
                print("  ok    the CACHE: a truncated index is caught (%s) and rebuilt" % why)
            # and the rebuild puts it back
            sdk_index()
            sane, _why = index_is_sane(index, sdk_index_key(sdk_root()))
            if not sane:
                print("  FAIL  the rebuild did not restore a complete index")
                rc = 1
            else:
                print("  ok    the CACHE: the rebuild restored a complete index")
        problem = cache_invalidation_self_test()
        if problem:
            print("  FAIL  the cache self-test: %s" % problem)
            rc = 1
        else:
            print("  ok    the CACHE: touching a table moves the key, so the index is rebuilt")
        print("check-class-names: SELF_TEST %s" % ("FAILED" if rc else "OK"))
        return rc

    examined, hits = scan()
    print("  examined %d class-shaped name(s) in the class and protocol rows' prose" % examined)
    if examined == 0:
        print("FAIL: the scan examined nothing, so it cannot have found anything")
        return 1
    if hits:
        print("FAIL: these row texts name a class nothing defines:")
        for api, name, path in hits:
            print("    %-50s names %-42s %s" % (api, name, path))
        return 1
    print("  every candidate in the row texts is a declared name, the row's own api, or allow-listed")
    print("check-class-names: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
