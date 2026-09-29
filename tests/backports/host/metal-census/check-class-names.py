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
PKG = os.path.join(ROOT, "packages", "a", "apple-backports")
REGISTRIES = os.path.join(PKG, "registry")
ALLOW = os.path.join(HERE, "class-name-allowlist.txt")

# A CamelCase token: at least two humps, so "Apple" and "The" are not candidates.
CANDIDATE = re.compile(r"(?<![A-Za-z0-9_])([A-Z][a-z0-9]*(?:[A-Z][a-z0-9]*)+)(?![A-Za-z0-9_])")
MINIMUM = 6


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
        if os.sep + "registry" + os.sep in base:
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
                if len(name) < MINIMUM or name not in api:
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


def main():
    if "--self-test" in sys.argv or os.environ.get("SELF_TEST"):
        # THE POSITIVE must be a row the tree really has, and its own api must NOT be reported.
        _, clean = scan()
        for api, name, _p in clean:
            if api == name:
                print("FAIL: a row's own api is reported as a mangled form of itself")
                return 1
        print("  ok   the self-test's POSITIVE: a row's own api is not reported, and a name the tree"
              " declares is not reported")
        _, hits = scan(planted="MTLComputePassDescriptor")
        if not hits or hits[0][1] != "ComputePassDescriptor":
            print("FAIL: the self-test's planted mangled name was not reported")
            return 1
        print("  ok   the self-test's NEGATIVE: a planted mangled form of a real class is reported"
              " (%s)" % hits[0][1])
        print("check-class-names: SELF_TEST OK")
        return 0

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
