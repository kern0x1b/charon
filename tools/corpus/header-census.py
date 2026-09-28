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

API_AVAILABLE = re.compile(r"API_(?:UN)?AVAILABLE\s*\(([^)]*)\)")


def dump_ast(framework, sdk, target, work):
    """The AST of a framework's UMBRELLA, as JSON.

    A bare header does not compile: NS_OPTIONS and the other Foundation macros arrive through
    the umbrella's include order, so a per-header dump reported every header as failed and found
    nothing. One line that imports <Framework/Framework.h> compiles and the AST filter gives the
    whole framework in one dump, which is also the only way the class, its categories and its
    methods arrive in one tree.
    """
    source = os.path.join(work, "umbrella.m")
    with open(source, "w") as fh:
        fh.write("#import <%s/%s.h>\n" % (framework, framework))
    argv = ["clang", "-fsyntax-only", "-x", "objective-c", "-isysroot", sdk,
            "-target", target, "-Xclang", "-ast-dump=json", source]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None, proc.stderr.strip().splitlines()[:5]
    return json.loads(proc.stdout), None


def walk(node, out):
    """Every declaration node in the dump, with its name and the release macro it carries."""
    kind = node.get("kind")
    if kind in ("ObjCInterfaceDecl", "ObjCProtocolDecl", "ObjCMethodDecl",
                "ObjCPropertyDecl", "ObjCClassDecl"):
        name = node.get("name") or ""
        if kind == "ObjCClassDecl" and node.get("name"):
            name = "implementation " + name
        loc = (node.get("loc") or {})
        spelling = loc.get("spelling") if isinstance(loc, dict) else None
        spelling = spelling if isinstance(spelling, str) else ""
        macro = API_AVAILABLE.search(spelling) or API_AVAILABLE.search(
            (node.get("attrs") or [{}])[0].get("value", "")
            if isinstance(node.get("attrs"), list) and node["attrs"] else "")
        out.append((kind, name, node.get("name") or "", macro, node))
    for child in node.get("inner", []) or []:
        walk(child, out)


def introduced(macro, target):
    """The lowest iOS release an API_AVAILABLE macro admits, or None when it admits any."""
    if not macro:
        return None
    versions = re.findall(r"ios\((\d+(?:\.\d+)?)\)", macro.group(1) if macro.groups() else "")
    if not versions:
        return None
    return min(versions, key=lambda s: [int(p) for p in s.split(".")])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sdk", required=True, help="an SDK root")
    ap.add_argument("--framework", required=True)
    ap.add_argument("--minimum", default="6.1.3", help="the release the port must carry to")
    ap.add_argument("--json", action="store_true", help="machine-readable, one object per member")
    args = ap.parse_args()

    headers = os.path.join(args.sdk, "System", "Library", "Frameworks",
                           args.framework + ".framework", "Headers")
    if not os.path.isdir(headers):
        raise SystemExit("no headers for %s under %s" % (args.framework, args.sdk))
    target = "armv7-apple-ios" + args.minimum

    import tempfile
    nodes = []
    failures = []
    with tempfile.TemporaryDirectory() as work:
        ast, err = dump_ast(args.framework, args.sdk, target, work)
        if ast is None:
            failures.append((args.framework + ".h", err))
        else:
            walk(ast, nodes)

    floor = tuple(int(p) for p in args.minimum.split("."))
    by_owner = collections.defaultdict(list)
    for kind, display, plain, macro, node in nodes:
        if kind not in ("ObjCInterfaceDecl", "ObjCProtocolDecl"):
            continue
        by_owner[(kind, display)].append((node.get("name"), introduced(macro, target)))

    rows = []
    for (kind, display), members in sorted(by_owner.items()):
        for mname, intro in members:
            reached = intro is None or tuple(int(p) for p in intro.split(".")) <= floor
            rows.append((kind, display, mname, intro, reached))

    if args.json:
        print(json.dumps([{"kind": k, "owner": d, "member": m, "introduced": i, "at_minimum": r}
                          for k, d, m, i, r in rows], indent=2))
        return

    want = tuple(int(p) for p in args.minimum.split("."))
    print("== %s headers under %s, checked at iOS %s" % (args.framework, args.sdk, args.minimum))
    print("   %d headers in the framework, %d dumps failed; %d types, %d members"
          % (len([n for n in os.listdir(headers) if n.endswith(".h")]),
             len(failures), len(by_owner), len(rows)))
    for name, err in failures:
        print("   FAILED %s: %s" % (name, err))
    print()
    by_intro = collections.Counter(i or "any" for _, _, _, i, _ in rows)
    print("   members by the release they were introduced in:")
    for intro, n in sorted(by_intro.items(), key=lambda kv: (kv[0] == "any", kv[0])):
        reached = intro == "any" or tuple(int(p) for p in intro.split(".")) <= want
        print("     %-8s %4d  %s" % (intro, n, "reachable" if reached else "NOT at this release"))
    print()
    print("== types")
    for kind, display, mname, intro, reached in rows:
        if kind in ("ObjCInterfaceDecl", "ObjCProtocolDecl"):
            print("   %-22s %-44s %s" % (kind.replace("ObjC", "").replace("Decl", ""),
                                            display, intro or "any"))
    unreachable = [(k, d, m, i) for k, d, m, i, r in rows if not r and m]
    print()
    print("== %d members this release does not have" % len(unreachable))
    for k, d, m, i in unreachable[:40]:
        print("   %-40s %-30s %s" % (d, m, i))
    if len(unreachable) > 40:
        print("   ... and %d more" % (len(unreachable) - 40))


if __name__ == "__main__":
    main()
