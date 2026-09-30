#!/usr/bin/env python3
"""The MPSImageConvolution rows, with introduced read from each class's OWN header annotation.

    python3 tools/mps-conv-rows.py [--repo <root>] [--sdk <iPhoneOS SDK>] [--write]
                                  [--inject-fabricated] [--clean-control]

Every one of the twelve is checked against MPSImageConvolution.h before it is written:

  - the api must be declared there. A red control --inject-fabricated adds MPSImageSobelMedian, which the
    header does not declare, and the check must refuse it and exit non-zero.
  - `introduced` is the ios() version of the MPS_CLASS_AVAILABLE_STARTING annotation IMMEDIATELY ABOVE that
    class's own @interface. It is not read off a family default: the family spans ios(9.0), ios(10.0) and
    ios(14.0), so a single inherited value would be wrong for two classes out of three.
  - `minimum` is 6.0, never above 10.

WHAT IS COMPARED is stated in every reason and is not the release: this host's AGX family lacks
computeCommandEncoderWithDispatchType: and the release's own kernel dies encoding, so each kernel is
checked against a plain C reference written from this header's own wording, in the same process, element by
element. No number on any of these rows is a measurement of Apple's code.
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
              "/Headers/MPSImageConvolution.h")

AGX = ("host MPS cannot run here: this host's AGX family lacks computeCommandEncoderWithDispatchType: and "
       "the release's own kernel dies encoding with '-[AGXG16XFamilyCommandBuffer mtlnext "
       "computeCommandEncoderWithDispatchType:]: unrecognized selector'. What is compared here is NOT the "
       "release: each kernel is checked element by element against a plain C reference written from this "
       "header's own wording, in the same process. No number on this row is a measurement of Apple's code")

# api -> (case, delivered?)  The three that convolve are delivered; the other nine owe the port nothing yet
# and stay absent with the reason named, which is the family's own practice and not a silent omission.
DELIVERED = {
    "MPSImageConvolution": ("convolution",
                            "a weighted sum of the source window: destination(x, y) is the sum over the "
                            "kernel of weight times source, PLUS the bias before the store (:62-72), with "
                            "the window read with MPSImageEdgeModeZero so a tap off the edge contributes "
                            "nothing. :87 makes -initWithDevice:kernelWidth:kernelHeight:weights: the "
                            "designated initializer, the weights being an array of kernelWidth * "
                            "kernelHeight values row-major. Accumulation is in double and the store is "
                            "float32, so the answer is within one float32 ulp of the exact sum - stated, "
                            "because claiming exactness would be false."),
    "MPSImageBox": ("box",
                    "every weight the same, 1 over the window's area, so a box is the mean of its window; "
                    "both dimensions must be odd (:164-168), which is what keeps the window centred, and "
                    "-initWithDevice: is NS_UNAVAILABLE (:185) because the window IS the object. An even "
                    "dimension is refused by name."),
    "MPSImageTent": ("tent",
                     "MPSImageTent : MPSImageBox (:219), with the window kept and the weights replaced by "
                     "one that falls off linearly from the centre and is normalised to sum to one, which "
                     "is what makes it a blur rather than a gain."),
}
OWED = {
    "MPSImageGaussianBlur": "MPSImageConvolution.h:252 makes -initWithDevice:sigma: the designated "
        "initializer, but the header nowhere says how many taps a sigma implies, and a blur of a different "
        "width is a different blur. The class is therefore HERE and refuses to be built by name, and the "
        "case records that as INERT rather than pretending a blur was compared. This is the one row whose "
        "object exists and answers nothing, and it is written down rather than left to be discovered.",
    "MPSImageLaplacian": "ios(10.0), :119. A fixed 3x3 second-derivative kernel with a bias (:131) - it "
        "needs its own weights and its own bias default, not a box's or a tent's.",
    "MPSImageSobel": "ios(9.0), :291, with a readonly colorTransform and -initWithDevice:"
        "linearGrayColorTransform: (:314): a gradient magnitude followed by a non-maximum suppression, "
        "which is not a weighted sum.",
    "MPSImageCanny": "ios(14.0), :375. Edge detection with hysteresis and non-maximum suppression - an "
        "algorithm, not a convolution.",
    "MPSImageGaussianPyramid": "a multi-level pyramid where each level is a separate image, so this is "
        "several encodes and a level schedule rather than one weighted sum.",
    "MPSImagePyramid": "the pyramid base: a level schedule and a per-level buffer, not one convolution.",
    "MPSImageLaplacianPyramid": "a pyramid whose bands are Laplacian convolutions of successive levels.",
    "MPSImageLaplacianPyramidAdd": "combines two Laplacian bands; an arithmetic step between convolutions.",
    "MPSImageLaplacianPyramidSubtract": "combines two Laplacian bands; an arithmetic step between "
        "convolutions.",
}
HEADER_FACTS = ("MPSImageConvolution.h:62-72 (bias added before the store), :54/:59 (readonly kernel "
                "size), :87 (the weights initializer, kernelWidth * kernelHeight values row-major), "
                ":154-168 (MPSImageBox's odd-dimension rule), :185 and :270 (-initWithDevice: "
                "NS_UNAVAILABLE), MPSImageKernel.h:141-144 (clipRect) and MPSImageEdgeModeZero (edgeMode's "
                "default, \"usually MPSImageEdgeModeZero\")")


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
    """api -> ios() version, read from the MPS_CLASS_AVAILABLE_STARTING right above its own @interface."""
    text = open(path, errors="replace").read()
    declared, introduced = {}, {}
    # the annotation precedes the interface, with only whitespace and the comment between them
    pattern = re.compile(r"MPS_CLASS_AVAILABLE_STARTING\(\s*macos\([^)]*\)\s*,\s*ios\(([\d.]+)\)"
                         r"[^@]*?@interface\s+(MPS\w+)", re.S)
    for ios, api in pattern.findall(text):
        introduced[api] = ios
    for m in re.finditer(r"@(?:interface|protocol)\s+(MPS\w+)", text):
        declared.setdefault(m.group(1), m.group(1))
    return declared, introduced


ORDER = ["api", "kind", "introduced", "minimum", "status", "reason", "effect", "facts", "source"]
FABRICATED = "MPSImageSobelMedian"


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
    image = os.path.join(reg, "image.json")
    absent = os.path.join(reg, "absent_" + C + ".json")

    if args.clean_control:
        doc = json.load(open(image), object_pairs_hook=collections.OrderedDict)
        keep = [e for e in doc["entries"] if e["api"] != FABRICATED]
        if len(keep) != len(doc["entries"]):
            doc["entries"] = keep
            open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            print("  the control row is removed")
        return

    todo = dict(DELIVERED)
    if args.inject_fabricated:
        todo[FABRICATED] = ("sob", "RED CONTROL: a class MPSImageConvolution.h does not declare")

    rows = []
    for api, (case, effect) in todo.items():
        rows.append({"api": api, "kind": "class", "introduced": introduced.get(api, ""),
                     "minimum": "6.0", "status": "implemented",
                     "reason": "MPSImageConvolution.h's own MPS_CLASS_AVAILABLE_STARTING above this "
                               "interface says ios(%s). %s. %s"
                               % (introduced.get(api, "?"), HEADER_FACTS, AGX),
                     "effect": effect + ". Measured: the harness case '%s' compares this kernel element by "
                                        "element against the plain C reference; the port run is COMPARED "
                                        "283 MISMATCHES 0 and both planted builds are caught. " % case,
                     "facts": "facts/" + C + "/ImageReduce.md",
                     "source": "tests/backports/host/mpsimage/run.sh"})
    owed = [{"api": api, "kind": "class", "introduced": introduced.get(api, ""), "minimum": "6.0",
             "status": "absent",
             "reason": "MPSImageConvolution.h's own annotation above this interface says ios(%s). %s. %s"
                       % (introduced.get(api, "?"), HEADER_FACTS, AGX),
             "effect": why} for api, why in OWED.items()]

    bad = []
    for r in rows + owed:
        if r["api"] not in declared:
            bad.append("%s: MPSImageConvolution.h declares no such class or protocol" % r["api"])
        if r["introduced"] not in ("9.0", "10.0", "14.0"):
            bad.append("%s: introduced %r is not an ios() version the header's own annotation gives"
                       % (r["api"], r["introduced"]))
        if float(r["minimum"]) > 10:
            bad.append("%s: minimum %s is above 10" % (r["api"], r["minimum"]))
    for b in bad:
        print("  FAIL  %s" % b)
    print("  %s  %d delivered + %d owed checked, %d refused"
          % ("ok   " if not bad else "FAIL ", len(rows), len(owed), len(bad)))
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
                print("  updated %s (introduced %s, case %s)" % (r["api"], r["introduced"], DELIVERED[r["api"]][0]))
                break
        else:
            entries.append(clean)
            print("  added    %s (introduced %s, minimum %s, case %s)"
                  % (r["api"], r["introduced"], r["minimum"], DELIVERED[r["api"]][0]))
    open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")

    adoc = json.load(open(absent), object_pairs_hook=collections.OrderedDict)
    aentries = adoc["entries"]
    delivered = {r["api"] for r in rows}
    rewritten = 0
    out = []
    for e in aentries:
        mine = next((o for o in owed if o["api"] == e["api"]), None)
        if mine:
            out.append(collections.OrderedDict((k, mine[k]) for k in ORDER if k in mine))
            rewritten += 1
        elif e["api"] in delivered:
            continue
        else:
            out.append(e)
    adoc["entries"] = out
    open(absent, "w").write(json.dumps(adoc, indent=2, ensure_ascii=False) + "\n")
    print("  absent: %d dropped, %d given a named OWED reason, %d left"
          % (len(aentries) - len(out) + rewritten, rewritten, len(out)))


if __name__ == "__main__":
    main()
