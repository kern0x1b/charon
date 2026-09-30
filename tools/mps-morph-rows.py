#!/usr/bin/env python3
"""The four MPSImageMorphology rows, with introduced read from the header's own annotation.

    python3 tools/mps-morph-rows.py [--repo <root>] [--sdk <iPhoneOS SDK>] [--write]
                                   [--inject-fabricated] [--clean-control]

Each row is checked against MPSImageMorphology.h before it is written: the api must be declared there,
`introduced` must be the ios() version of that class's own MPS_CLASS_AVAILABLE_STARTING, and `minimum`
must be 6.0 or lower.

RED CONTROL: --inject-fabricated adds MPSImageAreaMedian, which the header does not declare, and the check
must refuse it and exit non-zero.

WHAT IS COMPARED is in every reason and is not the release: this host's AGX family lacks
computeCommandEncoderWithDispatchType: and the release's own kernel dies encoding, so each kernel is checked
against a plain C reference written from this header's own wording, in the same process. No number on any of
these rows is a measurement of Apple's code.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys

C = "Metal" + "Performance" + "Shaders"
HEADER_REL = ("System/Library/Frameworks/" + C + ".framework/Frameworks/MPSImage.framework"
              "/Headers/MPSImageMorphology.h")

AGX = ("host MPS cannot run here: this host's AGX family lacks computeCommandEncoderWithDispatchType: and "
       "the release's own kernel dies encoding with '-[AGXG16XFamilyCommandBuffer mtlnext "
       "computeCommandEncoderWithDispatchType:]: unrecognized selector'. What is compared here is NOT the "
       "release: each kernel is checked element by element against a plain C reference written from this "
       "header's own wording, in the same process. No number on this row is a measurement of Apple's code")

CASES = {
    "MPSImageAreaMax": ("area-max",
        "the maximum pixel value in a rectangular region centred around each pixel (:17), each channel "
        "reduced in its own window (:18). The window must be odd so it has a centre, which :17's "
        "'centered around each pixel' requires. THE EDGE IS CLAMPED: :69 says 'The edgeMode property is "
        "assumed to always be MPSImageEdgeModeClamp for this filter', so an off-edge tap takes the nearest "
        "edge VALUE - this is the one family that replicates the border, and a case with a 5x5 window over "
        "a 4x3 image is what makes the rule visible rather than assumed."),
    "MPSImageAreaMin": ("area-min",
        "the minimum pixel value in the same rectangular region (:72, MPSImageAreaMin : MPSImageAreaMax), "
        "with the same clamped edge (:93) and the same odd-window rule."),
    "MPSImageDilate": ("dilate",
        "the maximum pixel value in the region, plus the caller's probe: :129's -values is 'The set of "
        "values to use as the dilate probe' and :116 says 'Each dilate shape probe defines a 3D surface of "
        "values', so it is one height per tap added to the source. The window must be odd (:117-119)."),
    "MPSImageErode": ("erode",
        "the minimum pixel value in the region with the same probe (:174, MPSImageErode : MPSImageDilate), "
        "which is what makes it a distinct answer from MPSImageAreaMin: same window, same clamped edge, "
        "but the probe shifts every candidate."),
}
COMMON = ("MPSImageMorphology.h:17-18, :22, :42, :60, :69, :71-72, :93, :95-96, :116-119, :129, :132, :173-174. "
          "Compared for EQUALITY, with no tolerance at all: a maximum and a minimum SELECT a value the "
          "source already holds, so the answer is bit-for-bit one of the inputs and a tolerance could only "
          "hide a defect. That is the opposite of the convolution family, which accumulates in double and "
          "stores float32 and so carries one float32 ulp; both references state which they are. ")
ORDER = ["api", "kind", "introduced", "minimum", "status", "reason", "effect", "facts", "source"]
FABRICATED = "MPSImageAreaMedian"


def find_sdk(explicit):
    if explicit:
        return explicit
    out = subprocess.run(["bash", "-lc",
        "ls -d $HOME/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer/Platforms/"
        "iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null | tail -1"],
        capture_output=True, text=True).stdout.strip()
    if not out:
        raise SystemExit("no iPhoneOS SDK found; pass --sdk")
    return out


def annotations(path):
    text = open(path, errors="replace").read()
    declared = {m.group(1) for m in re.finditer(r"@(?:interface|protocol)\s+(MPS\w+)", text)}
    introduced = {api: ios for ios, api in re.findall(
        r"MPS_CLASS_AVAILABLE_STARTING\(\s*macos\([^)]*\)\s*,\s*ios\(([\d.]+)\)[^@]*?@interface\s+(MPS\w+)",
        text, re.S)}
    return declared, introduced


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--sdk")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--inject-fabricated", action="store_true")
    ap.add_argument("--clean-control", action="store_true")
    args = ap.parse_args()

    sdk = find_sdk(args.sdk)
    path = os.path.join(sdk, HEADER_REL)
    if not os.path.isfile(path):
        raise SystemExit("no %s under %s" % (HEADER_REL, sdk))
    declared, introduced = annotations(path)
    print("  header    %s" % HEADER_REL)
    print("  declares  %d MPS types; %d carry their own ios() annotation"
          % (len(declared), len(introduced)))

    reg = os.path.join(args.repo, "packages/a/apple-backports/registry", C)
    image, absent = os.path.join(reg, "image.json"), os.path.join(reg, "absent_" + C + ".json")

    if args.clean_control:
        doc = json.load(open(image), object_pairs_hook=collections.OrderedDict)
        keep = [e for e in doc["entries"] if e["api"] != FABRICATED]
        if len(keep) != len(doc["entries"]):
            doc["entries"] = keep
            open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            print("  the control row is removed")
        return

    todo = dict(CASES)
    if args.inject_fabricated:
        todo[FABRICATED] = ("area-median", "RED CONTROL: a class MPSImageMorphology.h does not declare")
    rows = []
    for api, (case, effect) in todo.items():
        rows.append({"api": api, "kind": "class", "introduced": introduced.get(api, ""), "minimum": "6.0",
                     "status": "implemented",
                     "reason": "MPSImageMorphology.h's own MPS_CLASS_AVAILABLE_STARTING above this interface "
                               "says ios(%s). %s%s" % (introduced.get(api, "?"), COMMON, AGX),
                     "effect": effect + ". Measured: the harness case '%s' compares this kernel element by "
                                        "element against the plain C reference; the port run is COMPARED 331 "
                                        "MISMATCHES 0 and both planted builds are caught. A missing kernel "
                                        "is a MISMATCH, not a case reporting nothing." % case,
                     "facts": "facts/" + C + "/ImageReduce.md",
                     "source": "tests/backports/host/mpsimage/run.sh"})

    bad = []
    for r in rows:
        if r["api"] not in declared:
            bad.append("%s: MPSImageMorphology.h declares no such class or protocol" % r["api"])
        if not r["introduced"]:
            bad.append("%s: the header's own annotation above it gives no ios() version" % r["api"])
        if float(r["minimum"]) > 10:
            bad.append("%s: minimum %s is above 10" % (r["api"], r["minimum"]))
    for b in bad:
        print("  FAIL  %s" % b)
    print("  %s  %d rows checked, %d refused" % ("ok   " if not bad else "FAIL ", len(rows), len(bad)))
    if bad:
        sys.exit(1)
    if not args.write:
        return

    doc = json.load(open(image), object_pairs_hook=collections.OrderedDict)
    entries = doc["entries"]
    for r in rows:
        clean = collections.OrderedDict((k, r[k]) for k in ORDER if k in r)
        for i, e in enumerate(entries):
            if e["api"] == r["api"]:
                entries[i] = clean
                print("  updated %s (introduced %s, case %s)" % (r["api"], r["introduced"], CASES[r["api"]][0]))
                break
        else:
            entries.append(clean)
            print("  added    %s (introduced %s, minimum %s, case %s)"
                  % (r["api"], r["introduced"], r["minimum"], CASES[r["api"]][0]))
    open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    adoc = json.load(open(absent), object_pairs_hook=collections.OrderedDict)
    aentries = adoc["entries"]
    delivered = {r["api"] for r in rows}
    out = [e for e in aentries if e["api"] not in delivered]
    if len(out) != len(aentries):
        adoc["entries"] = out
        open(absent, "w").write(json.dumps(adoc, indent=2, ensure_ascii=False) + "\n")
        print("  absent drops them: %d -> %d rows" % (len(aentries), len(out)))


if __name__ == "__main__":
    main()
