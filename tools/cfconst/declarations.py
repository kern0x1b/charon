#!/usr/bin/env python3
"""hk26-decl.py: for each member the built library carries and no registry row names, what the iOS 26.2
SDK header says about it - declared with which availability, or not declared at all. The header is the
authority on whether a method exists; a release image only supplies the value a constant holds.
"""
import os, re, sys

import glob
SDK = os.environ.get("HK_SDK") or sorted(glob.glob(os.path.expanduser(
    "~/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer/Platforms/"
    "iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk")))[-1]
H = os.path.join(SDK, "System/Library/Frameworks/HealthKit.framework/Headers")
ALL = " ".join(re.sub(r"\s+", " ", re.sub(r"//[^\n]*", "", open(os.path.join(H, n)).read()))
              for n in sorted(os.listdir(H)) if n.endswith(".h"))


def look(cls, member):
    method = re.search(r"([-+])\s*\(\s*[^)]*\)\s*" + re.escape(cls) + r"\s+" + re.escape(member) +
                       r"\b.{0,300}?(API_AVAILABLE\([^)]*\))?\s*[;{]", ALL)
    prop = re.search(r"@property\s*(?:\([^)]*\))?\s*[\w \*\[\]<>,]*?\b" + re.escape(member) +
                     r"\b.{0,300}?(API_AVAILABLE\([^)]*\))?\s*;", ALL)
    hit = method or prop
    name = "-[%s %s]" % (cls, member)
    if not hit:
        return name, "NOT DECLARED", ""
    avail = re.search(r"API_AVAILABLE\([^)]*ios\(([0-9.]+)\)", hit.group(0))
    kind = "property" if prop and (not method or prop.start() < method.start()) else "method"
    return name, kind, ("ios " + avail.group(1)) if avail else "unannotated (takes its container's version)"


if __name__ == "__main__":
    # declarations.py Class.member...: what the SDK's HealthKit headers say about each member - which
    # of them it declares, and with which iOS version. The header is the authority on whether a method
    # exists; a release image only supplies the value a constant holds.
    pairs = [tuple(a.split(".")) for a in sys.argv[1:]]
    for cls, member in pairs:
        name, kind, avail = look(cls, member)
        print("%-52s %-9s %s" % (name, kind, avail))
