"""One framework's headers, read through the clang AST: the classes, the protocols, and every
member each declares with the release macro that gates it.

INPUT   a framework's Headers directory inside an SDK, and the deployment target to check it
        against. The AST is dumped with `-Xclang -ast-dump=json` and parsed, so a class is a node
        the compiler built rather than a regex over the header text: `@interface`, the category
        that extends it, the methods it declares, the properties, and the availability macro each
        of those carries in the source.

OUTPUT  per class and per protocol: the kind, the name, and its members with the release they
        were introduced in and whether the deployment target reaches them. That is the census a
        port is planned from, because it says what the framework is made of and which of it the
        release has, without a single hand count.

    python3 tools/corpus/header-census.py --sdk <SDK> --framework FileProvider --minimum 6.1.3
    python3 tools/corpus/header-census.py --sdk <SDK> --framework FileProvider --json
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys

# The TEXT dump, not the JSON one. Measured on FileProvider: the JSON AST has 16563 nodes whose
# kind is AvailabilityAttr and NOT ONE carries a version - across all of them the keys are id,
# kind and range, 149 with `inherited` - so the release a declaration is gated at is not in the
# JSON at all. The text dump prints it on the Attr's own line, hanging UNDER the declaration in
# the dump's indentation, which is what pairs them:
#
#   | |-AvailabilityAttr 0x7a1d26f210 <col:43, col:84> ios 14.0 0 0 "" "" 0
#
# An availability guard is a conjunction of constraints and a release must satisfy ALL of them, so
# the one that binds is the HIGHEST iOS version among the Attrs under a declaration - not the
# first, which is what a naive scan reads.
DECL = re.compile(r"^([|` -]*)(ObjC[A-Za-z]+Decl|AvailabilityAttr)\b(.*)$")
# A location is <file:line:col> - NSObjCRuntime.h:19:27,
# .../FileProvider.framework/Headers/NSFileProviderItem.h:22:54 - so the file is followed by two
# COLONS and numbers. A pattern asking for ":line:" matches nothing at all, which is what the
# instrumented guard showed: the tracked path was None on every one of the dump's 70k lines and the
# scope test therefore never had a path to test.
HEADER = re.compile(r"(/\S+\.h):\d+:\d+")
IOS = re.compile(r"\bios\s+(\d+(?:\.\d+)?)\b")
ADDRESS = re.compile(r"^0x[0-9a-f]+$")
LOCATION = re.compile(r"^<<.*>>$|^<.*>$|^col:\d+$|^line:\d+.*$")
KINDS = ("ObjCInterfaceDecl", "ObjCProtocolDecl", "ObjCMethodDecl", "ObjCPropertyDecl",
         "ObjCClassDecl", "ObjCCategoryDecl")
MEMBER_KINDS = ("ObjCMethodDecl", "ObjCPropertyDecl")


def _target(args):
    return "%s-apple-ios%s" % (os.environ.get("CHARON_SWIFT_ARCH", "armv7"), args.minimum)


def identifier(kind, rest):
    """The name a declaration line carries.

    A line is the address, the location and then the name: `0x7a1cef97f0 <line:255:1, col:8>
    col:8 NSAttributedString` for an interface, and `... col:2 -isEqual: 'BOOL' [no]` for a
    method. For a type the name is the last token once the address and the location are out of
    the way; for a method it is the first token that begins with the ObjC sigil, because after it
    come the argument types and the attributes, not more of the name.
    """
    words = [w for w in rest.split()
             if w and not ADDRESS.match(w) and not LOCATION.match(w)]
    if not words:
        return ""
    if kind in MEMBER_KINDS:
        for w in words:
            if w[0] in "-+":
                return w
    return words[-1]


def dump_ast(framework, sdk, target, work):
    """The TEXT AST of a framework's UMBRELLA.

    A bare header does not compile: NS_OPTIONS and the rest of the Foundation macros arrive
    through the umbrella's include order, so a per-header dump reported every header as failed and
    found nothing. One line importing <Framework/Framework.h> compiles and the whole framework is
    one tree, which is also the only way a class, its categories and its methods arrive together.
    """
    source = os.path.join(work, "umbrella.m")
    with open(source, "w") as fh:
        fh.write("#import <%s/%s.h>\n" % (framework, framework))
    argv = ["clang", "-fsyntax-only", "-x", "objective-c", "-isysroot", sdk,
            "-target", target, "-Xclang", "-ast-dump", source]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None, proc.stderr.strip().splitlines()[:5]
    return proc.stdout, None


def _ver(text):
    return tuple(int(p) for p in text.split("."))


def _highest(attrs):
    versions = [v.group(1) for v in (IOS.search(a) for a in attrs) if v]
    return max(versions, key=_ver) if versions else None


def parse(text, framework=None):
    """One row per TYPE, with its members hanging off it.

    A row per member was the original shape and it printed "Interface NSArray" nine times: a type
    with nine members was nine types. The index is by (kind, identifier), which is also what a
    plan is written against - a class and what it declares, once.
    """
    order, attrs, pending = [], [], None
    # The scope comes from the DUMP: a declaration's location is <begin, end> and the end is the
    # header the declaration sits in - NSObjCRuntime.h:19:27,
    # .../FileProvider.framework/Headers/NSFileProviderItem.h:22:54 - and a line that carries only
    # `line:` has no path at all and means the file of the line above it, so the path is carried
    # forward. Keeping what is under the framework's own Headers is therefore a decision about
    # locations, not about names: Foundation's NSArray and FileProvider's NSFileProviderManager
    # are both named in the same dump and only one of them is in this framework.
    path = None
    marker = ("/%s.framework/Headers/" % framework) if framework else None
    types = {}

    def flush():
        if pending is None:
            return
        kind = pending[1]
        ident = identifier(kind, pending[2])
        key = (kind, ident)
        if key not in types:
            order.append(key)
            types[key] = {"members": [], "introduced": _highest(attrs)}
        elif kind in MEMBER_KINDS:
            types[key]["members"].append((identifier(kind, pending[2]), _highest(attrs)))
        else:
            current, later = types[key]["introduced"], _highest(attrs)
            if current and later and _ver(later) > _ver(current):
                types[key]["introduced"] = later

    for line in text.splitlines():
        found = HEADER.search(line)
        if found:
            path = found.group(1)
        m = DECL.match(line)
        if not m:
            continue
        prefix, kind, rest = m.group(1), m.group(2), m.group(3)
        if kind == "AvailabilityAttr":
            if pending is not None:
                attrs.append(rest)
            continue
        if pending is not None and len(prefix) <= len(pending[0]):
            flush()
            pending, attrs = None, []
        if marker and path and marker not in path:
            pending, attrs = None, []
            continue
        if kind in KINDS:
            pending, attrs = (prefix, kind, rest), []
    flush()
    return order, types


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sdk", required=True, help="an SDK root")
    ap.add_argument("--framework", required=True)
    ap.add_argument("--minimum", default="6.1.3", help="the release the port must carry to")
    ap.add_argument("--json", action="store_true", help="one object per type, members inside")
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()

    import tempfile
    with tempfile.TemporaryDirectory() as work:
        ast, err = dump_ast(args.framework, args.sdk, _target(args), work)
    if ast is None:
        print("FAILED: %s" % err)
        return
    headers = os.path.join(args.sdk, "System", "Library", "Frameworks",
                           args.framework + ".framework", "Headers")
    order, types = parse(ast, args.framework)

    floor = tuple(int(p) for p in args.minimum.split("."))
    by_intro = collections.Counter()
    reachable = 0
    total_members = 0
    for key in order:
        entry = types[key]
        total_members += len(entry["members"])
        by_intro[entry["introduced"] or "any"] += len(entry["members"])
        for _, intro in entry["members"]:
            if intro and tuple(int(p) for p in intro.split(".")) <= floor:
                reachable += 1

    if args.json:
        print(json.dumps([{"kind": k, "type": k, "introduced": types[k]["introduced"],
                           "members": [{"name": n, "introduced": i}
                                       for n, i in types[k]["members"]]}
                          for k in order], indent=2))
        return

    print("== %s headers under %s, checked at iOS %s" % (args.framework, args.sdk, args.minimum))
    print("   %d types, %d members"
          % (len(order), total_members))
    with_release = sum(len(types[k]["members"]) for k in order)
    print("   %d members carry a release; %d are reachable at %s"
          % (with_release, reachable, args.minimum))
    print()
    print("   members by the release they were introduced in:")
    for intro, n in sorted(by_intro.items(), key=lambda kv: (kv[0] == "any", kv[0])):
        got = intro == "any" or tuple(int(p) for p in intro.split(".")) <= floor
        print("     %-8s %5d  %s" % (intro, n, "reachable" if got else "NOT at this release"))
    print()
    print("== types, one row each")
    print("   %-8s %-9s %-44s %s" % ("kind", "release", "type", "members"))
    for key in order[:args.top]:
        entry = types[key]
        print("   %-8s %-9s %-44s %d"
              % (key[0].replace("ObjC", "").replace("Decl", ""), entry["introduced"] or "any",
                 key[1], len(entry["members"])))
    if len(order) > args.top:
        print("   ... and %d more types" % (len(order) - args.top))


if __name__ == "__main__":
    main()
