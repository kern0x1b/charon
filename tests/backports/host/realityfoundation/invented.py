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
import json
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
    modules = {}
    for module in sorted(m for m in found if m):
        release = ""
        for part in module.split("/"):
            if part.startswith("iPhoneOS") and part.endswith(".sdk"):
                release = part.replace("iPhoneOS", "").replace(".sdk", "")
        if not release:
            continue
        modules.setdefault(release, []).append(module)
    for release, paths in modules.items():
        # both frameworks, unioned: a release's Reality surface is what its two interfaces declare
        # between them, and taking one of the two made every RealityKit row read as invented
        words = set()
        for module in paths:
            text = open(module, encoding="utf-8", errors="replace").read()
            words |= set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", text))
        out[release] = (" and ".join(os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(p))))
                        for p in paths), words)
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


def row_names(registries):
    """Every implemented row's name, from the registries, with the row that carries it."""
    names = []
    for path in registries:
        for entry in json.load(open(path, encoding="utf-8"))["entries"]:
            if entry.get("status") == "implemented":
                names.append((entry["api"], os.path.basename(path)))
    return names


def main(argv):
    if argv and argv[0] == "--rows":
        registries = [a for a in argv[1:] if a.endswith(".json")]
        if not registries:
            sys.exit("usage: invented.py --rows <registry.json>...")
        found = interfaces()
        versions = sorted(found)
        if not versions:
            sys.exit("invented.py: no arm64e Reality interface in the store")
        words = {v: found[v][1] for v in versions}
        print("# every implemented row's name, against the SDKs' arm64e interfaces (%s)"
              % ", ".join(versions))
        buckets = {"both": [], "newer": [], "older": [], "neither": [], "operator": []}
        for api, registry in row_names(registries):
            leaf = re.sub(r"\(.*", "", api.split(".")[-1]).strip()
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", leaf):
                # a row whose name is an operator - ==, the synthesised ones - is not readable out
                # of a word set: the character class a word is drawn from excludes it
                buckets["operator"].append((api, registry))
                continue
            in_old = leaf in words[versions[0]]
            in_new = leaf in words[versions[-1]]
            key = ("both" if in_old and in_new else "newer" if in_new
                   else "older" if in_old else "neither")
            buckets[key].append((api, registry))
        for key, label in (("both", "in %s and %s" % (versions[0], versions[-1])),
                           ("newer", "in %s only" % versions[-1]),
                           ("older", "in %s only" % versions[0]),
                           ("neither", "IN NEITHER - read every one of these"),
                           ("operator", "a name that is an operator, which a word set cannot hold")):
            print("\n## %s (%d)" % (label, len(buckets[key])))
            for api, registry in buckets[key]:
                print("   %-72s %s" % (api[:72], registry))
        total = sum(len(v) for v in buckets.values())
        print("\n# %d implemented rows: %d in an interface, %d in neither, %d an operator"
              % (total, total - len(buckets["neither"]) - len(buckets["operator"]),
                 len(buckets["neither"]), len(buckets["operator"])))
        return 0
    if len(argv) != 1:
        sys.exit("usage: invented.py <series-base> | --rows <registry.json>...")
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
