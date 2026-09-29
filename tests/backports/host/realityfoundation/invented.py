#!/usr/bin/env python3
"""Every public name this series adds, against the SDKs' own arm64e interfaces.

The brief's rule is that a name is public when a `.swiftinterface` declares it - not when a surface
TSV lists it, because those are ledgers of what the corpus wanted, and they name things the SDK never
declared. So the oracle here is the interface, and it is the *arm64e* slice: the SDKs ship one
interface per architecture and the arm64 one is a different file with a different set of declarations.

Three outcomes, and only the third is a finding:

  in 16.4 and 26.2   the name is Apple's, and both releases declare it
  in 26.2 only       the name arrived after the older SDK - fidelity, and the release that has it
  in 16.4 only       the name was taken away - a finding, and one to read about
  in neither         either the port's own name, which the code says it is, or an invented one

A name the port adds on purpose - everything under the `Charon` prefix, and the handful of members the
series says in its own comments are the port's - is listed with `port` and is not a defect. Everything
else in neither is: a name the port speaks that the SDKs do not, which is what this check exists to
find.

    usage: invented.py <series-base> > invented-names.txt
"""
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SOURCES = ("packages/s/swift-runtime/files/RealityFoundation",
           "packages/s/swift-runtime/files/RealityKit",
           "packages/s/swift-runtime/files")
# the port's own naming, and the members the series documents as its own
PORT_PREFIX = ("Charon", "P2P", "MESH")
PORT_MEMBERS = {"entity(in:)", "projectPoint(_:)", "unprojectPoint(_:)",
                "CharonSCNProjectionMatrix", "PixelCastHit", "ConfigurationCatalogError"}


def interfaces():
    """Every arm64e Reality interface in the store, keyed by the release its SDK directory names.

    The store's layout varies between installs - some have Developer.app/.../SDKs and some have the
    SDK directory beside the manifest - so this asks `find` for the files rather than walking a
    layout it would have to guess twice, which is the same shape the host suites already use for
    otool and strings.
    """
    out = {}
    home = os.path.expanduser("~")
    found = subprocess.run(
        ["find", os.path.join(home, ".xmake/packages/i/iphoneos-sdk"), "-name",
         "arm64e-apple-ios.swiftinterface", "-path", "*Reality*"],
        capture_output=True, text=True).stdout.split("\n")
    for module in sorted(m for m in found if m):
        release = ""
        for part in module.split("/"):
            if part.startswith("iPhoneOS") and part.endswith(".sdk"):
                release = part.replace("iPhoneOS", "").replace(".sdk", "")
        if not release or release in out:
            continue
        text = open(module, encoding="utf-8", errors="replace").read()
        out[release] = (module, set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", text)))
    return out


def declared_names(base):
    """The public names the series' own sources declare."""
    added = set()
    diff = subprocess.run(["git", "diff", "--unified=0", base + "..HEAD", "--"] +
                          [os.path.join(REPO, s) for s in SOURCES],
                          capture_output=True, text=True, check=True).stdout
    for line in diff.split("\n"):
        if not line.startswith("+") or line.startswith("+++"):
            continue
        for name in re.findall(r"\b(?:public|open)\s+(?:final\s+)?(?:class|struct|enum|protocol|func|var|let|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)", line):
            added.add(name)
        for name in re.findall(r"\bpublic\s+init\((\w+)", line):
            added.add(name)
    return added


def main(argv):
    if len(argv) != 1:
        sys.exit("usage: invented.py <series-base>")
    base = argv[0]
    found = interfaces()
    versions = sorted(found)
    if not versions:
        sys.exit("invented.py: no arm64e Reality interface in the store - the oracle is the interface, "
                 "and without it this check has nothing to say")
    ours = declared_names(base)
    print("# public names this series adds, against the SDKs' arm64e interfaces")
    for version in versions:
        print("#   %s  %s" % (version, found[version][0]))
    names = {v: found[v][1] for v in versions}
    buckets = {"both": [], "newer": [], "older": [], "port": [], "invented": []}
    for name in sorted(ours):
        in_old = name in names[versions[0]] if len(versions) > 1 else False
        in_new = name in names[versions[-1]]
        if in_old and in_new:
            buckets["both"].append(name)
        elif in_new:
            buckets["newer"].append(name)
        elif in_old:
            buckets["older"].append(name)
        elif name.startswith(PORT_PREFIX) or name in PORT_MEMBERS:
            buckets["port"].append(name)
        else:
            buckets["invented"].append(name)
    for key, label in (("both", "in %s and %s" % (versions[0], versions[-1])),
                       ("newer", "in %s only" % versions[-1]),
                       ("older", "in %s only" % versions[0]),
                       ("port", "the port's own name, declared as such in the code"),
                       ("invented", "IN NEITHER - a name the port speaks that the SDKs do not")):
        print("\n## %s (%d)" % (label, len(buckets[key])))
        for name in buckets[key]:
            print("   %s" % name)
    print("\n# %d declared, %d Apple's, %d the port's own, %d invented"
          % (len(ours), len(buckets["both"]) + len(buckets["newer"]) + len(buckets["older"]),
             len(buckets["port"]), len(buckets["invented"])))
    return 1 if buckets["invented"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
