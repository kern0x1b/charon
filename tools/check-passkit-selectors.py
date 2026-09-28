#!/usr/bin/env python3
"""Every method row's selector in registry/PassKit, grep'd in the SDK 26.2's own PassKit headers.

A dotted name like `PKPassLibrary.addPassesWithCompletionHandler` is not a selector and a name no
header declares is not real API. This script is the check that says so, over every method row of the
PassKit registry, and it is the check that found eight of them.

The selector is checked the way a header actually spells one, which is not how a grep for the dotted
name works:

  * a selector is not contiguous text, because each keyword is followed by its parameter's type and
    name -- `- (void)addPasses:(NSArray<PKPass *> *)passes withCompletionHandler:(nullable
    void(^)(...))completion` -- so the joined string never appears;
  * and the class is named once, at its `@interface`, not on each method's line.

So for every header the enclosing `@interface <Class> ... @end` is taken out, and the selector must be
spelled INSIDE that block **on one line**, with at least as many colons as the selector has. One line
is the whole point: a multi-keyword selector whose keywords merely occur somewhere in the same
interface would pass a name that no header spells, because each keyword belongs to a different method
there. `-addPasses:withCompletionHandler:` is real and `addPasses:` and `withCompletionHandler:` are
both in `@interface PKPassLibrary` -- but only together on one line do they make that selector.

    python3 tools/check-passkit-selectors.py [--sdk <iPhoneOS26.2.sdk>]

Exits non-zero and prints every miss. 0 misses is the only green.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
REGISTRY = os.path.join(REPO, "packages", "a", "apple-backports", "registry", "PassKit")


def default_sdk():
    """The 26.2 SDK this repository builds against: the iphoneos-sdk 26.2 package, whose layout is a
    developer folder, so the SDK root is several levels under the package root rather than in it."""
    store = os.path.join(os.environ["HOME"], ".xmake", "packages", "i", "iphoneos-sdk", "26.2")
    if not os.path.isdir(store):
        return None
    for root in sorted(os.listdir(store)):
        sdk = os.path.join(
            store, root, "Developer.app", "Contents", "Developer", "Platforms",
            "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS26.2.sdk")
        if os.path.isdir(sdk):
            return sdk
    return None


def spelled(words, colons, line):
    """Whether one header line spells this selector's keywords.

    With colons, every keyword appears as `keyword:`. Without, the single keyword appears bare: a
    method taking no argument is written `- (void)openPaymentSetup API_AVAILABLE(ios(8.3))`, with
    no colon after the name at all.
    """
    if not colons:
        return words[0] in line
    return all((w + ":") in line for w in words)


def keywords(selector):
    """`-[PKPassLibrary addPasses:withCompletionHandler:]` -> the selector's own keywords.

    The class is the token before the first space, the keywords are the colon-terminated pieces after
    it, and a zero-colon selector is the single token.
    """
    body = selector[selector.index(" ") + 1:].rstrip("]")
    if ":" not in body:
        return [body], 0
    parts = [p for p in body.split(":") if p]
    return parts, body.count(":")


def interfaces(path):
    """Each @interface <Class> ... @end block of a header, as (body, class name).

    A header declares the class once and lists its members under it, so "is this selector in the
    header" means "is it in the block that belongs to that class" -- which is the only reading that
    holds for a real one, and the one an invented name fails.
    """
    owner = None
    body = []
    for line in open(path, errors="ignore"):
        m = re.search(r"@interface\s+([A-Za-z_][A-Za-z0-9_]*)", line)
        if m:
            if owner is not None:
                yield "".join(body), owner
            owner = m.group(1)
            body = [line]
            continue
        if owner is not None:
            if re.search(r"@end", line):
                # the class body ends here, but a CATEGORY on the same class -- which is where Apple
                # puts a class method added later, e.g. +[PKAddPassesViewController canAddPasses] --
                # opens a new @interface and belongs to the same class
                if not re.search(r"\(\s*\w*\s*\)", line) and not re.search(
                        r"@interface\s+[A-Za-z_][A-Za-z0-9_]*\s*\(", line):
                    yield "".join(body), owner
                    owner = None
                    body = []
                    continue
            body.append(line)
    if owner is not None:
        yield "".join(body), owner


def main():
    sdk = None
    if len(sys.argv) > 2 and sys.argv[1] == "--sdk":
        sdk = sys.argv[2]
    if sdk is None:
        sdk = default_sdk()
    if sdk is None or not os.path.isdir(sdk):
        print("FAIL no iPhoneOS26.2.sdk under the iphoneos-sdk 26.2 package; pass --sdk")
        return 2
    headers = os.path.join(sdk, "System", "Library", "Frameworks", "PassKit.framework", "Headers")
    if not os.path.isdir(headers):
        print("FAIL no PassKit.framework/Headers in " + sdk)
        return 2

    total = 0
    misses = []
    for name in sorted(os.listdir(REGISTRY)):
        if not name.endswith(".json"):
            continue
        entries = json.load(open(os.path.join(REGISTRY, name)))["entries"]
        for entry in entries:
            if entry["kind"] != "method":
                continue
            api = entry["api"]
            total += 1
            if not (api.startswith("-[") or api.startswith("+[")) or " " not in api:
                misses.append((name, api, "not written as a selector"))
                continue
            cls = api[2:api.index(" ")]
            words, colons = keywords(api)
            where = None
            why = None
            for path in sorted(os.listdir(headers)):
                if not path.endswith(".h"):
                    continue
                lines = open(os.path.join(headers, path), errors="ignore").read().splitlines()
                owner = None
                for line in lines:
                    m = re.search(r"@interface\s+([A-Za-z_][A-Za-z0-9_]*)", line)
                    if m:
                        owner = m.group(1)
                        continue
                    if owner is None:
                        continue
                    if not spelled(words, colons, line):
                        continue
                    if line.count(":") < colons:
                        continue
                    # inside @interface <cls>, for a method; and Apple's headers also name the class
                    # on the method's own line for a CLASS method, so both spellings are accepted
                    if owner != cls and cls not in line:
                        continue
                    where = path
                    break
                if where:
                    break
                if why is None and any(
                        re.search(r"@interface\s+%s\b" % re.escape(cls), l) for l in lines):
                    # the class IS here: report which keywords the header does and does not spell
                    found = [w for w in words
                             if any(spelled([w], colons if len(words) == 1 else 1, l) and cls in l
                                    for l in lines)]
                    why = ("@interface %s is in %s but no line of it spells all of %s%s"
                           % (cls, path, ":".join(words) + (":" if colons else ""),
                              "" if len(found) == len(words)
                              else "; the header spells " + (", ".join(found) or "none of them")))
                elif why is None:
                    why = "@interface %s is in no header" % cls
            if not where:
                misses.append((name, api, why or ("no header spells it")))

    for name, api, why in misses:
        print("MISS %s  %s  (%s)" % (name, api, why))
    print("checked %d method row(s) against %s: %d miss(es)" % (total, headers, len(misses)))
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
