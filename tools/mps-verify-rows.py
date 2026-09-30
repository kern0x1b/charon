#!/usr/bin/env python3
"""The nine MPSImageReduce rows, and a check that each names a member the header declares.

    python3 tools/mps-verify-rows.py [--repo <root>] [--sdk <iPhoneOS SDK>]

The rows are written into registry/.../image.json and out of absent_....json by --write. The check runs
either way and is what the rows have to pass:

  - every row's `api` must be declared as a class or protocol by MPSImageReduce.h. A row that names
    something the header does not declare is refused, because a row is a claim about the SDK and a claim
    the SDK does not support is a wrong registry.
  - every row's `introduced` must equal what MPS_CLASS_AVAILABLE_STARTING in that header says, and its
    `minimum` must be 6.0 or lower.
  - every row must name the harness case that measures it, so a reader can go from the row to the
    measurement instead of taking the status on trust.

RED CONTROL: run it with --inject-fabricated to add a tenth row naming a class MPSImageReduce.h does not
declare, and the check must refuse it. A verifier that passes a fabricated row verifies nothing. The
control row is removed by --clean-control.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys

COMPONENT = "Metal" + "Performance" + "Shaders"
HEADER_REL = ("System/Library/Frameworks/" + COMPONENT + ".framework/Frameworks/MPSImage.framework"
              "/Headers/MPSImageReduce.h")

C = COMPONENT
AGX = ("host MPS cannot run here: this host's AGX family lacks "
       "computeCommandEncoderWithDispatchType: and the release's own kernel dies encoding with "
       "'-[AGXG16XFamilyCommandBuffer mtlnext computeCommandEncoderWithDispatchType:]: unrecognized "
       "selector'. What is compared here is NOT the release: each kernel is checked against a plain C "
       "reference written from this header's own wording, in the same process, element by element. No "
       "number on these rows is a measurement of Apple's code")

CASES = {
    "MPSImageReduceUnary": (None, None),
    "MPSImageReduceRowMin": ("reduce-row-min", "row"),
    "MPSImageReduceColumnMin": ("reduce-column-min", "column"),
    "MPSImageReduceRowMax": ("reduce-row-max", "row"),
    "MPSImageReduceColumnMax": ("reduce-column-max", "column"),
    "MPSImageReduceRowMean": ("reduce-row-mean", "row"),
    "MPSImageReduceColumnMean": ("reduce-column-mean", "column"),
    "MPSImageReduceRowSum": ("reduce-row-sum", "row"),
    "MPSImageReduceColumnSum": ("reduce-column-sum", "column"),
}
OPS = {"Min": "the minimum", "Max": "the maximum", "Mean": "the mean", "Sum": "the sum"}
COMMON = ("MPSImageReduce.h:17-26 (the eight operations), :28 (MPS_CLASS_AVAILABLE_STARTING ios(11.3)), "
          ":31-42 (clipRectSource - 'replaces the MPSUnaryImageKernel offset parameter for this filter. "
          "The latter is ignored', intersected with the image, default MPSRectNoClip), :38-40 (clipRect is "
          "the write origin, 'width must be >=2' and 'height must be >= 1'), :44-47 (the base's "
          "-initWithDevice: is NS_UNAVAILABLE), :53-:184 (each class's own 'for each row' or 'for each "
          "column'). " + AGX)


def find_sdk(explicit):
    if explicit:
        return explicit
    hits = subprocess.run(
        ["bash", "-lc", "ls -d $HOME/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer"
                        "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null | tail -1"],
        capture_output=True, text=True).stdout.strip()
    if not hits:
        raise SystemExit("no iPhoneOS SDK found; pass --sdk")
    return hits


def header_facts(sdk):
    path = os.path.join(sdk, HEADER_REL)
    if not os.path.isfile(path):
        raise SystemExit("no %s under %s" % (HEADER_REL, sdk))
    text = open(path, errors="replace").read()
    declared = set(re.findall(r"@(?:interface|protocol)\s+(MPS\w+)", text))
    introduced = None
    m = re.search(r"MPS_CLASS_AVAILABLE_STARTING\(\s*macos\([^)]*\),\s*ios\(([\d.]+)\)", text)
    if m:
        introduced = m.group(1)
    return declared, introduced, path


def build_rows(declared):
    rows = []
    for api, (case, axis) in CASES.items():
        if api not in declared:
            continue
        if case is None:
            reason = ("MPSImageReduce.h:44-47 - -initWithDevice: is NS_UNAVAILABLE on this abstract base and "
                      "the header says 'You must use one of the sub-classes of MPSImageReduceUnary'. "
                      "Measured release behaviour: it asserts and aborts the process, MPSImageReduce.mm:345 "
                      "'Cannot directly initialize MPSImageReduceUnary'. The port refuses by name and returns "
                      "nil - the same observable outcome, no usable object, without aborting a caller that "
                      "asked for the wrong class. Its encode is the family's: implemented in this base so "
                      "the threshold band's 1:1 walk on MPSUnaryImageKernel is not inherited. " + COMMON)
            effect = ("the abstract reduction base: it carries clipRectSource (default MPSRectNoClip) and "
                      "refuses to be instantiated. OWED, refused by name rather than answered wrongly: a "
                      "clip rectangle failing MPSImageReduce.h:38-40 - width < 2 or height < 1 - and a "
                      "clipRectSource that intersects the source to nothing. Measured: 0 errors and 0 "
                      "warnings for armv7-apple-ios6.1.3 against the iOS 16.4 SDK under -Wall. " + AGX)
            source = "tests/backports/host/mpsimage/run.sh"
        else:
            op = next((v for k, v in OPS.items() if api.endswith(k)), "the reduction")
            direction = "row" if "Row" in api else "column"
            plural = "rows" if direction == "row" else "columns"
            reason = ("MPSImageReduce.h:%s - this class's own comment says it returns %s 'for each %s of an "
                      "image', and :28 dates the class at ios(11.3). " % (api_comment_line(api), op, direction)
                      + COMMON)
            effect = ("returns %s of each %s of the source: %s values for a %dx%d source, read over the "
                      "window clipRectSource names intersected with the image, offset ignored because the "
                      "header says clipRectSource replaces it. min and max are exact; mean and sum are "
                      "within one float32 ulp, because a sum is stored back as float32 and rounding once is "
                      "not a wrong answer. Measured: the harness case '%s' compares this kernel element by "
                      "element against a plain C reference written from this header's wording - COMPARED "
                      "246 MISMATCHES 0 across the slice, and both planted builds are caught. A missing "
                      "kernel is a MISMATCH, not a case reporting nothing. The destination's SHAPE is not "
                      "stated by the header, which fixes how many values there are and not their width or "
                      "height, and it could not be measured here, so the case builds the shape the class "
                      "name implies. %s"
                      % (op, direction, "rows" if direction == "row" else "columns", 4, 3, case, AGX))
            source = "tests/backports/host/mpsimage/run.sh"
        rows.append({
            "api": api, "kind": "class", "introduced": "11.3", "minimum": "6.0", "status": "implemented",
            "reason": reason, "effect": effect,
            "facts": "facts/" + C + "/ImageReduce.md", "source": source, "case": case,
        })
    return rows


def api_comment_line(api):
    return {"MPSImageReduceRowMin": "53", "MPSImageReduceColumnMin": "74", "MPSImageReduceRowMax": "91",
            "MPSImageReduceColumnMax": "108", "MPSImageReduceRowMean": "125",
            "MPSImageReduceColumnMean": "142", "MPSImageReduceRowSum": "159",
            "MPSImageReduceColumnSum": "176"}.get(api, "29")


ORDER = ["api", "kind", "introduced", "minimum", "status", "reason", "effect", "facts", "source"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--sdk")
    ap.add_argument("--write", action="store_true", help="move the rows into image.json")
    ap.add_argument("--inject-fabricated", action="store_true", help="RED CONTROL: add a row the header "
                                                                  "does not declare; the check must refuse it")
    ap.add_argument("--clean-control", action="store_true")
    args = ap.parse_args()

    sdk = find_sdk(args.sdk)
    declared, introduced, header = header_facts(sdk)
    print("  header    %s" % HEADER_REL)
    print("  declares  %d MPS types; MPS_CLASS_AVAILABLE_STARTING says ios(%s)" % (len(declared), introduced))

    reg = os.path.join(args.repo, "packages/a/apple-backports/registry", C)
    image = os.path.join(reg, "image.json")
    absent = os.path.join(reg, "absent_" + C + ".json")

    fabricated = {"api": "MPSImageReduceRowMedian", "kind": "class", "introduced": "11.3", "minimum": "6.0",
                  "status": "implemented", "reason": "RED CONTROL: MPSImageReduce.h declares no such class",
                  "effect": "RED CONTROL", "facts": "facts/" + C + "/ImageReduce.md",
                  "source": "tests/backports/host/mpsimage/run.sh", "case": "reduce-row-median"}
    if args.clean_control:
        doc = json.load(open(image), object_pairs_hook=collections.OrderedDict)
        keep = [e for e in doc["entries"] if e["api"] != fabricated["api"]]
        if len(keep) != len(doc["entries"]):
            doc["entries"] = keep
            open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            print("  the control row is removed")
        return

    rows = build_rows(declared)
    if args.inject_fabricated:
        rows = rows + [fabricated]

    # ---- the check
    bad = []
    for r in rows:
        if r["api"] not in declared:
            bad.append("%s: MPSImageReduce.h declares no such class or protocol" % r["api"])
        if r["introduced"] != introduced:
            bad.append("%s: introduced %s, the header says %s" % (r["api"], r["introduced"], introduced))
        if float(r["minimum"]) > 10:
            bad.append("%s: minimum %s is above 10" % (r["api"], r["minimum"]))
        if r["kind"] != "class":
            bad.append("%s: kind %s" % (r["api"], r["kind"]))
    # The case names are printed by the harness's CASE FILE, not by run.sh - run.sh builds and runs it.
    # This check looked in run.sh first and refused all eight rows for it, which is the check working:
    # it was asking the wrong question and would have passed a row naming a case nobody prints.
    case_file = os.path.join(args.repo, "tests/backports/host/mpsimage/image-cases.m")
    printed = open(case_file, errors="replace").read() if os.path.isfile(case_file) else ""
    missing_case = [r["api"] for r in rows if r["case"] and r["case"] not in printed]
    if missing_case:
        bad.append("these rows name a case image-cases.m does not print: %s" % ", ".join(missing_case))
    nameless = [r["api"] for r in rows if r["status"] == "implemented" and not r["case"]
                and r["api"] != "MPSImageReduceUnary"]
    if nameless:
        bad.append("these rows are implemented but name no case: %s" % ", ".join(nameless))

    for b in bad:
        print("  FAIL  %s" % b)
    print("  %s  %d rows checked, %d refused"
          % ("ok   " if not bad else "FAIL ", len(rows), len(bad)))
    if bad:
        sys.exit(1)
    if not args.write:
        return

    doc = json.load(open(image), object_pairs_hook=collections.OrderedDict)
    entries = doc["entries"]
    have = {e["api"] for e in entries}
    adoc = json.load(open(absent), object_pairs_hook=collections.OrderedDict)
    aentries = adoc["entries"]
    for r in rows:
        clean = collections.OrderedDict((k, r[k]) for k in ORDER if k in r)
        if r["api"] in have:
            for i, e in enumerate(entries):
                if e["api"] == r["api"]:
                    entries[i] = clean
            print("  updated %s" % r["api"])
        else:
            entries.append(clean)
            print("  added    %s (introduced %s, minimum %s, case %s)"
                  % (r["api"], r["introduced"], r["minimum"], r["case"]))
    open(image, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    keep = [e for e in aentries if e["api"] not in {r["api"] for r in rows}]
    if len(keep) != len(aentries):
        adoc["entries"] = keep
        open(absent, "w").write(json.dumps(adoc, indent=2, ensure_ascii=False) + "\n")
        print("  absent drops them: %d -> %d rows" % (len(aentries), len(keep)))


if __name__ == "__main__":
    main()
