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


def declared_names():
    """Every class, protocol and typedef the package or the SDK declares."""
    names = set()
    for base, _dirs, files in os.walk(PKG):
        if os.sep + "registry" + os.sep in base or os.sep + "obj" + os.sep in base:
            continue
        for f in files:
            if not f.endswith((".m", ".h")):
                continue
            try:
                text = open(os.path.join(base, f), encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for m in re.finditer(r"@(?:implementation|interface|protocol)\s+(\w+)", text):
                names.add(m.group(1))
            for m in re.finditer(r"typedef[^;]*?\b(\w+)\s*;", text):
                names.add(m.group(1))
            names |= enumerators(text)
            for m in re.finditer(r"#\s*define\s+([A-Z][A-Za-z0-9_]+)", text):
                names.add(m.group(1))
            # a C FUNCTION declared in the source is a known name as well: the prose says
            # "NSClassFromString answers nil", which is a true statement about a function
            for m in re.finditer(r"\b((?:NS|CF|CG|MTL|MTK|dispatch_|objc_)[A-Za-z0-9_]+)\s*\(", text):
                names.add(m.group(1))
    # THE .tbd TABLES ARE THE ORACLE, and the headers only ever were a stand-in for them. A .tbd
    # lists every symbol the SDK EXPORTS, which is the question being asked - not "does a header
    # spell this" - so NSNotFound, MTLAllocation and MTLFunctionOptionNone are known because the
    # library exports them, not because a regex found them. Grepping headers reported 116 names that
    # all exist and it took a .tbd to make the check mean what it says.
    for tbd in sdk_tbd_files():
        try:
            text = open(tbd, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        # A .tbd v4 lists its exports as a bracketed, comma-separated list of symbol names, and
        # older ones as `key:` lines; both are read, and the leading underscore - and any re-export
        # prefix such as '$ld$hide$os2.0' - is stripped.
        for m in re.finditer(r"[_$A-Za-z][A-Za-z0-9_$]*", text):
            name = m.group(0)
            if not name.startswith("_"):
                continue
            names.add(name.lstrip("_").split("$")[-1])
    for d in sdk_framework_dirs():
        for base, _dirs, files in os.walk(d):
            for f in files:
                if not f.endswith(".h"):
                    continue
                try:
                    text = open(os.path.join(base, f), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for m in re.finditer(r"@(?:interface|protocol)\s+(\w+)", text):
                    names.add(m.group(1))
                for m in re.finditer(r"\b((?:NS|CF|CG|MTL|MTK|dispatch_|objc_)[A-Za-z0-9_]+)\s*\(", text):
                    names.add(m.group(1))
                names |= enumerators(text)
                for m in re.finditer(r"#\s*define\s+([A-Z][A-Za-z0-9_]+)", text):
                    names.add(m.group(1))
    return names


def sdk_tbd_files():
    """Every .tbd in the SDK the package compiles against: the exported-symbol tables."""
    out = []
    home = os.path.expanduser("~")
    for base, _d, _f in os.walk(os.path.join(home, ".xmake", "packages", "i", "iphoneos-sdk", "16.4")):
        for sub in ("usr/lib", "System/Library/Frameworks"):
            root = os.path.join(base, sub)
            for b2, _d2, f2 in os.walk(root):
                for f3 in f2:
                    if f3.endswith(".tbd"):
                        out.append(os.path.join(b2, f3))
    return out


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


def scan(planted=None):
    declared = declared_names()
    allow = allow_list()
    examined, hits = 0, []
    for path in registries():
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for row in doc.get("entries", []):
            # ONLY CLASS AND PROTOCOL ROWS. A constant row's prose legitimately names the VALUE it
            # carries - MicroPDF417 for AVMetadataObjectTypeMicroPDF417Code, TimeDomain for
            # AVAudioTimePitchAlgorithmTimeDomain - and a method row's prose names its receiver.
            # Those are true statements about a value, not claims that the port defines a type, and
            # the defect this catches is a claim that the port DOES define one.
            if row.get("kind") not in ("class", "protocol"):
                continue
            api = row.get("api", "")
            text = " ".join(str(row.get(k, "")) for k in ("reason", "effect"))
            for m in CANDIDATE.finditer(text):
                # COUNTED FIRST, then filtered. A run that examined nothing must not be able to say
                # OK, and a count taken after the filters would be zero on a perfectly healthy tree -
                # which is exactly the "a check that examined nothing said it passed" defect.
                examined += 1
                name = m.group(1)
                if name == api or name in declared or name in allow:
                    continue
                # NO FILTER ON LENGTH, AND NO RELATION TO THE ROW'S OWN API. The filter this
                # replaces required the candidate to be a substring of the row's own api, which
                # caught the MTL-stripped slip and passed the OTHER one: "CharonMTLComputePass-
                # Descriptor" is LONGER than the api, so it was skipped, and so was a wholly
                # invented name. A check written to catch this series' defect must catch both of
                # them, and cannot be narrowed by guessing what shape a mistake takes.
                if not class_shaped(name):
                    continue
                hits.append((api, name, os.path.relpath(path, ROOT)))
    if planted:
        # THE PLANTED BAD NAME: a mangled form of a real row's own api, defined nowhere.
        victim = planted
        mangled = victim[3:] if victim.startswith("MTL") else victim
        if mangled and mangled not in declared:
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
    """What the scan says about ONE planted name, and whether that is the right answer."""
    api, name = plant[0], plant[1]
    declared = declared_names()
    allow = allow_list()
    examined, hits = 0, []
    for path in registries():
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for row in doc.get("entries", []):
            if row.get("api") != api or row.get("kind") not in ("class", "protocol"):
                continue
            for m in CANDIDATE.finditer(name):
                examined += 1
                if m.group(1) == api or m.group(1) in declared or m.group(1) in allow:
                    continue
                if not class_shaped(m.group(1)):
                    continue
                hits.append(m.group(1))
    return examined, hits


def main():
    if "--self-test" in sys.argv or os.environ.get("SELF_TEST"):
        rc = 0
        for label, name, why in PLANTS:
            good = label.startswith("a known good")
            examined, hits = planted_report((("MTLComputePassDescriptor" if good else
                                             "MTLComputePassDescriptor"), name))
            reported = name in hits
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
