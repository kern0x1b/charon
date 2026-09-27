#!/usr/bin/env python3
"""api-check.py: does every row this framework's registry carries have an answer in the built library,
and does every row it registers `absent` have none?

The gate cannot ask this. `added_members` in `modules/apple/backports.lua` skips every class a
library itself defines, and this framework defines all of its own, so the gate sees neither an
`implemented` row that is not built nor a built selector no row names. This tool asks the same question
the gate's own `check_registry` asks, over the same set of names - `backports.surface()` read out of a
built dylib - and its exit status is the answer.

    python3 tools/cfconst/api-check.py . <checkout> [DYLIB]     the assertion, over a built library
    python3 tools/cfconst/api-check.py . <checkout> --images     the weaker reading, over release images

The second mode compares the rows with the ObjC metadata of the release images in
`.agent-work/runs/api-kits/`, and it is weaker on purpose: `objc.binary_inventory` on an image
extracted from a shared cache reads a class's *category* method lists and not the class's own, so a
public method of a release reads as absent. The SDK header is the authority on what a release has; the
image is the authority on the value a constant holds.
"""
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
IMAGES = {"8.0": "HK-8.0-armv7", "8.2": "HK-8.2-armv7", "9.0": "HK-9.0-armv7", "9.3": "HK-9.3-armv7"}
FILES = {"ios8": "8.0", "ios82": "8.2", "ios90": "9.0", "ios93": "9.3"}


def spellings(api, kind):
    """The names the gate's own set is searched under for one registry row."""
    if kind == "class":
        return [api]
    if kind == "constant":
        return [api]
    method = re.match(r"^([-+])\[(\w+) (.+)\]$", api)
    if method:
        return [method.group(1) + "[" + method.group(2) + " " + method.group(3) + "]"]
    if "." in api and not api.startswith(("-", "+")):
        owner, prop = api.split(".", 1)
        return ["-[%s %s]" % (owner, prop), "+[%s %s]" % (owner, prop),
                "-[%s set%s:%s]" % (owner, prop[0].upper(), prop[1:])]
    return [api]


def from_dylib(root, dylib):
    """(kind, name) the gate's own set holds, read out of a built dylib."""
    out = subprocess.run(["xmake", "l", os.path.join(HERE, "surface.lua"), os.path.abspath(dylib)],
                         capture_output=True, text=True, cwd=root)
    found = set()
    for line in out.stdout.splitlines():
        kind, _, name = line.partition("\t")
        if kind in ("class", "answered", "symbol"):
            found.add((kind, name))
    return found


def from_images():
    """{class: {selector}} of the release images, private members left out."""
    per_release, accumulated = {}, {}
    for release, image in IMAGES.items():
        path = os.path.join(os.path.expanduser("~"), "Git/projects/ios/charon/.agent-work/runs/api-kits",
                            image + ".inventory")
        if not os.path.isfile(path):
            path = os.path.join(os.getcwd(), ".agent-work/runs/api-kits", image + ".inventory")
        if not os.path.isfile(path):
            continue
        classes, current = {}, None
        for line in open(path):
            line = line.rstrip("\n")
            match = re.match(r"^CLASS (\w+)", line)
            if match:
                current = match.group(1)
                classes[current] = set()
                continue
            if line.startswith("PROTOCOL "):
                current = None
                continue
            if current and line.startswith("  "):
                sel = line.strip()
                if sel[1:2] != "_":
                    classes[current].add(sel[0] + "[" + current + " " + sel[1:] + "]")
        accumulated.update(classes)
        per_release[release] = dict(accumulated)
    return per_release


def main(root, dylib=None, images=False):
    if dylib:
        built, classes = from_dylib(root, dylib), None
    else:
        built, classes = None, from_images()
    problems = 0
    for name, release in FILES.items():
        path = os.path.join(root, "packages", "a", "apple-backports", "registry", "HealthKit", name + ".json")
        if not os.path.isfile(path):
            continue
        have = classes.get(release, {}) if classes else {}
        for entry in json.load(open(path))["entries"]:
            api, kind, status = entry["api"], entry["kind"], entry["status"]
            if built is not None:
                if kind == "class":
                    answer = ("class", api) in built
                elif kind == "constant":
                    answer = ("symbol", api) in built
                else:
                    answer = any(("answered", s) in built for s in spellings(api, kind))
            else:
                answer = all(s in have.get(s.split(" ")[0][2:], set()) for s in spellings(api, kind)) \
                    if kind != "constant" else True
            if status == "implemented" and not answer:
                print("  %-5s %-9s %s  IMPLEMENTED AND NOT BUILT" % (release, kind, api))
                problems += 1
            elif status == "absent" and answer:
                print("  %-5s %-9s %s  ABSENT AND BUILT" % (release, kind, api))
                problems += 1
    if built is not None:
        print("registered rows the built library does not answer, and rows registered absent it does: %d" % problems)
    else:
        print("registered rows the release's own image does not carry (the weaker measurement, see the "
              "facts; the image's reader skips a class's own method list): %d" % problems)
    return problems


if __name__ == "__main__":
    arguments = [a for a in sys.argv[1:] if a != "--images"]
    images = "--images" in sys.argv
    root = arguments[0] if arguments else "."
    dylib = None if images else (arguments[1] if len(arguments) > 1 else None)
    sys.exit(0 if main(root, dylib=dylib, images=images) == 0 else 1)
