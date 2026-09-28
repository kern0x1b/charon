#!/usr/bin/env python3
"""api-check.py: three questions over a built library and this framework's registry.

  1. Does every row registered `implemented` have a selector in the built library?
  2. Does every row registered `absent` have none?
  3. Is there a public-shaped selector in the built library that no SDK header declares and no
     registry row can name?

The third is the other direction, and it is the one the gate cannot see: `added_members` in
`modules/apple/backports.lua` opens `if not class.image and not ours[name]`, and `class.image` is set
for every class the library itself defines, so `found.members` is empty for all of them. A member of
Apple's that no header declares, or one of the port's own, sits on an exported class under a
public-looking name and the gate says nothing. This asks about it with the same set of names the
gate's own `check_registry` compares against, `backports.surface()` read out of a built dylib.

    python3 tools/cfconst/api-check.py . <checkout> [DYLIB]     the three questions, over a build
    python3 tools/cfconst/api-check.py . <checkout> --images     the weaker reading, over release images

The `--images` mode compares the rows with the ObjC metadata of the release images, and it is weaker on
purpose: `objc.binary_inventory` on an image extracted from a shared cache reads a class's *category*
method lists and not the class's own, so a public method of a release reads as absent. The SDK header is
the authority on what a release has; the image is the authority on the value a constant holds.
"""
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
IMAGES = {"8.0": "HK-8.0-armv7", "8.2": "HK-8.2-armv7", "9.0": "HK-9.0-armv7", "9.3": "HK-9.3-armv7"}
FILES = {"ios8": "8.0", "ios82": "8.2", "ios90": "9.0", "ios93": "9.3", "ios100": "10.0", "ios110": "11.0"}

# The contracts of NSObject, NSSecureCoding and NSCopying. A class of this framework answers these
# because its superclass and its protocols do; the registry covers them as its class rows and its
# property rows, not as members of their own.
# A public-shaped selector the library carries on purpose, and why. Each is printed, not counted, so
# that a new one is a difference and a known one is visible.
ALLOWED = {
    "-[HKActivitySummary dateComponents]":
        "the key path HKPredicateKeyPathDateComponents names, and the two activity-summary predicates "
        "are built over it; the release's own private member, and the property the key path needs",
}

CONTRACTS = {"init", "initWithCoder:", "encodeWithCoder:", "supportsSecureCoding", "copyWithZone:",
             "isEqual:", "hash", "description", "dealloc", "class", "self", "respondsToSelector:",
             "forwardInvocation:", "doesNotRecognizeSelector:", "conformsToProtocol:",
             "isKindOfClass:", "isMemberOfClass:", "isProxy", "superclass", "zone"}


def spellings(api, kind):
    """The names the gate's own set is searched under for one registry row."""
    if kind in ("class", "constant"):
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
        path = None
        for base in (os.getcwd(), os.path.expanduser("~/Git/projects/ios/charon")):
            candidate = os.path.join(base, ".agent-work", "runs", "api-kits", image + ".inventory")
            if os.path.isfile(candidate):
                path = candidate
                break
        if not path:
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


def headers_for(framework):
    """Every bare method name and every property name the SDK's headers of `framework` declare, for
    the classes of that framework and for the categories on them.

    It is a set over the whole framework rather than one per class, and that is a deliberate limit:
    a name that some header of the framework declares passes, so a public-shaped member of one class
    that another class declares would not be reported. The check's purpose is the one the review found
    it for - a member of Apple's that no header declares, or one of the port's own, sitting on an
    exported class under a public-looking name - and a whole-framework set catches every instance of
    that. The nine selectors the review named are all names no header of HealthKit writes, so a
    per-class reading would not have changed any of them.
    """
    root = os.environ.get("HK_SDK_ROOT") or os.path.expanduser("~/.xmake/packages/i/iphoneos-sdk")
    candidates = sorted(glob.glob(os.path.join(root, "*", "*", "Developer.app", "Contents", "Developer",
                                          "Platforms", "iPhoneOS.platform", "Developer", "SDKs",
                                          "iPhoneOS*.sdk")))
    if not candidates:
        return set()
    folder = os.path.join(candidates[-1], "System/Library/Frameworks", framework + ".framework", "Headers")
    if not os.path.isdir(folder):
        return set()
    names = set()
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".h"):
            continue
        raw = open(os.path.join(folder, name)).read()
        # a doc comment carries @property and @method of its own, so it goes before anything is read
        text = re.sub(r"/\*.*?\*/", " ", raw, flags=re.S)
        text = re.sub(r"//[^\n]*", "", text)
        for method in re.finditer(r"([-+])\s*\(\s*[^)]*\)\s*([^;{]*?);", text):
            # the selector is the run of bare words and labels before the first opening parenthesis of
            # the parameter list, so a declaration whose parameters carry types is still read
            head = re.match(r"\s*((?:\w+\s*:\s*)*\w+)", method.group(2))
            if not head:
                continue
            parts = head.group(1).split()
            for part in parts:
                if not part.startswith("NS_"):
                    names.add(part.rstrip(":"))
        for prop in re.finditer(r"@property\s*(\([^)]*\))?\s*([^;]+?);", text):
            # the name of a property is the last word of its type and name, whatever the type spells
            words = [w for w in re.split(r"[\s\[\]<>*,]+", prop.group(2).strip()) if w and w != "*"]
            if words and re.fullmatch(r"\w+", words[-1]) and not words[-1].startswith("NS_"):
                names.add(words[-1])
                names.add("set" + words[-1][0].upper() + words[-1][1:])
    return names


def setter_of_a_registered_property(selector, registered):
    """True when the selector is the setter of a property some row already names: the registry carries a
    property, and its setter is the other half of it rather than a member of its own."""
    if not selector.startswith("-["):
        return False
    tail = selector.rsplit(" ", 1)[-1]
    if not (tail.startswith("set") and tail.endswith(":")) or len(tail) <= 4:
        return False
    owner = selector[2:].split(" ")[0]
    prop = tail[3:-1]
    return any(r.startswith(owner + "." + prop[0].lower() + prop[1:]) for r in registered)


def main(root, dylib=None, images=False, framework="HealthKit"):
    if dylib:
        built, classes = from_dylib(root, dylib), None
    else:
        built, classes = None, from_images()
    registered, per_file = set(), []
    problems = 0
    for name in FILES:
        path = os.path.join(root, "packages", "a", "apple-backports", "registry", framework, name + ".json")
        if not os.path.isfile(path):
            continue
        held = json.load(open(path))
        entries = held["entries"] if isinstance(held, dict) else held
        per_file.append((name, entries))
        for entry in entries:
            registered.add(entry["api"])
    for name, entries in per_file:
        release = FILES[name]
        have = classes.get(release, {}) if classes else {}
        for entry in entries:
            api, kind, status = entry["api"], entry["kind"], entry["status"]
            if built is not None:
                if kind == "class":
                    answer = ("class", api) in built
                elif kind == "constant":
                    answer = ("symbol", api) in built
                else:
                    answer = any(("answered", s) in built for s in spellings(api, kind))
            else:
                answer = kind == "constant" or all(s in have.get(s.split(" ")[0][2:], set())
                                                  for s in spellings(api, kind))
            if status == "implemented" and not answer:
                print("  %-5s %-9s %s  IMPLEMENTED AND NOT BUILT" % (release, kind, api))
                problems += 1
            elif status == "absent" and answer:
                print("  %-5s %-9s %s  ABSENT AND BUILT" % (release, kind, api))
                problems += 1
    if built is not None:
        declared = headers_for(framework)
        # the property each row names, per owner: the registry carries `Class.property`, and the built
        # library carries the getter and the setter of that property under their own spellings
        named_properties = set()
        for api in registered:
            if "." in api and not api.startswith(("-", "+")):
                owner, prop = api.split(".", 1)
                named_properties.add((owner, prop))
                named_properties.add((owner, "set" + prop[0].upper() + prop[1:]))
        for selector in sorted(name for kind, name in built if kind == "answered"):
            if selector in registered or "cxx_destruct" in selector or "charon_" in selector.lower():
                continue
            # the built name is written "[Class selector]", so the selector is the last space-separated
            # piece without its closing bracket
            tail = selector.rsplit(" ", 1)[-1].rstrip("]")
            if tail in CONTRACTS or tail.split(":")[0] in CONTRACTS:
                continue
            if setter_of_a_registered_property(selector, registered):
                continue
            if tail.split(":")[0] in declared:
                continue
            owner = selector[2:].split(" ")[0]
            if (owner, tail) in named_properties or (owner, tail.split(":")[0]) in named_properties:
                continue
            note = ALLOWED.get(selector)
            if note:
                print("  %-5s %-9s %s  ALLOWED: %s" % ("", "member", selector, note))
                continue
            print("  %-5s %-9s %s  BUILT AND NO HEADER DECLARES IT" % ("", "member", selector))
            problems += 1
        print("implemented rows not built, absent rows built, and public-shaped selectors no header "
              "declares: %d" % problems)
    else:
        print("registered rows the release's own image does not carry (the weaker measurement, see the "
              "facts; the image's reader skips a class's own method list): %d" % problems)
    return problems


def _entry():
    arguments = [a for a in sys.argv[1:] if a != "--images"]
    images = "--images" in sys.argv
    root = arguments[0] if arguments else "."
    dylib = None if images else (arguments[1] if len(arguments) > 1 else None)
    # A dylib that is not a file is a mistake, not a run with nothing to check: without it every row
    # would read as not built and the tool would report the whole registry as missing, which is worse
    # than saying so and stopping.
    if dylib is not None and not os.path.isfile(dylib):
        sys.stderr.write("api-check: %s is not a file; pass the built libHealthKitBackports.dylib of a gate run\n" % dylib)
        return 2
    if dylib is None and not images:
        sys.stderr.write("api-check: pass a built dylib, or --images for the weaker reading over the release images\n")
        return 2
    return 0 if main(root, dylib=dylib, images=images) == 0 else 1


if __name__ == "__main__":
    sys.exit(_entry())
