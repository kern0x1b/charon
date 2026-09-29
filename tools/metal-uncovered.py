#!/usr/bin/env python3
"""Metal, MetalKit and MetalFX declarations the 26.2 headers make that no registry row covers.

Modelled on the media band's `tools/media-uncovered.py` (commit 858c79ee0, in that worktree, read
here and not edited): the count comes from clang's AST and from nothing else, so it does not depend on
this script reading a header, and it carries three controls because a count with no control is a
number with no meaning.

What it counts, per framework and per header, each unioned BY NAME so a member declared twice counts
once: every `@interface` member, every `@protocol` member, every member a category adds, and every
file-scope function, constant and enumeration constant the headers declare. Then it says how many of
those a registry row covers - implemented, absent or inert - and how many have no row at all. What is
left is what the next pieces take.

    python3 tools/metal-uncovered.py [--framework Metal] [--no-ast] [--verbose]

The AST comes from clang and from the shared store's 26.2 SDK:

    xcrun clang -x objective-c -fsyntax-only -target arm64-apple-ios \
        -isysroot <SDK> -Xclang -ast-dump=json <include.m>

Three controls:
  - a member known to be in a Metal header is found;
  - a name that is in no Metal header is found zero times;
  - removing one declaration from a scratch copy of the headers moves the count by exactly one.

Each of the first two names a member TOGETHER WITH the header that declares it, and takes one from
each of two headers, because the first version named newBufferWithLength:options: as an MTLBuffer member
when it is an MTLDevice method declared in MTLDevice.h - a control that names the wrong header fails for
a reason of its own making, which is what it did. The controls have already caught two real bugs in this
tool: an interface's OWN members being skipped (a count of 5203 matching no row), and that wrong header.
The third control works on a scratch copy under this repository's own .agent-work and NEVER on the shared
SDK.

**THE MATCH WAS WRONG, and both causes were measured rather than guessed.**

`clang's JSON AST has no ObjCInstanceMethodDecl kind at all: every method, in an interface, a
protocol or a category, is an ObjCMethodDecl, and the histogram over the direct `inner` nodes of
MTLDevice.h's top-level declarations is 4555 ObjCMethodDecl, 1597 ObjCPropertyDecl, 127 ObjCIvarDecl
and none of the kind this tool was filtering on - so no method in the framework ever entered the
count, and 6959 declared was properties and ivars alone against 119 implemented METHOD rows.

The keys were never the problem. For -[MTLDevice newHeapWithDescriptor:] the registry row's api and
the AST's mangledName are the SAME STRING, and from_mangled() returns the owner and the whole
selector from it. MTLDevice is a PROTOCOL and it is visited as an ObjCProtocolDecl.

**The history of this defect, which the controls did not catch.** `rows_for` keeps a row's member exactly as
the registry writes it and `declarations()` builds a member from the AST's name, and the two never meet:

    registry  -[MTLDevice newHeapWithDescriptor:]      -> key MTLDevice, member "newHeapWithDescriptor:"
    AST       ObjCMethodDecl for the same method      -> name   "newHeapWithDescriptor"   (no colon)

**clang's JSON AST gives a method's name as a SELECTOR PIECE, not as the whole selector**, so a
zero-selector method and a one-selector method both come back as a bare name, and the registry's rows
carry whole selectors. Assembling the selector needs the method's `type` and its parameters, not its
name; that is the fix, and it is not written. Until it is, the count is plausible and the match is not,
and nothing should be written down from this tool's output.
"""
import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

FRAMEWORKS = ("Metal", "MetalKit", "MetalFX")
REGISTRY = os.path.join("packages", "a", "apple-backports", "registry")
HEADER_LIST = os.path.join("tools", "metal-headers.txt")
# The control names a member TOGETHER WITH the header that declares it, and takes one from each of two
# headers, because the first version of this control named newBufferWithLength:options: as an MTLBuffer
# member when it is an MTLDevice method declared in MTLDevice.h, and a control that names the wrong
# header is a control that fails for a reason of its own making.
CONTROLS = (("MTLDevice.h", "MTLDevice", "newBufferWithLength:options:"),
            ("MTLBuffer.h", "MTLBuffer", "getBytes:"))
CONTROL_ABSENT = "aNameNoHeaderDeclares:"          # in no Metal header
DECL = re.compile(r"[-+@]\[")
SCOPE = re.compile(r"^-")


def sdk_path():
    """The 26.2 SDK.

    NOT from the shared store: `charon@iphoneos-sdk` holds 16.4 and 16.4's Metal headers are not the
    26.2 surface this census is about. 26.2 is the one the lift and the corpus use, and it is looked
    for here so the tool says which SDK it measured rather than leaving it to be assumed.
    """
    candidates = [os.path.expanduser("~/.xmake/packages/i/iphoneos-sdk")]
    repo = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "..", "..")
    candidates.append(os.path.join(repo, ".agent-work", "sdk-26.2"))
    for base in candidates:
        for root, dirs, _ in os.walk(base):
            for name in dirs:
                if name == "iPhoneOS26.2.sdk":
                    return os.path.join(root, name)
    raise SystemExit("no iPhoneOS26.2.sdk found under %s" % ", ".join(candidates))


def include_paths_for(listing_path, root=None):
    """Where a listing's headers live: a scratch copy is rooted where the caller says, and the real
    ones at the SDK. The tool follows the listing, so a control points it at a copy by ROOTING the
    copy where the SDK is rooted - which is only honest if the copy keeps the SDK's relative layout,
    so the same lines are read against it with no change to the listing."""
    root = root or sdk_path()
    paths = []
    for line in open(listing_path or HEADER_LIST).read().split("\n"):
        if not line.strip():
            continue
        if os.path.isabs(line):
            paths.append(os.path.dirname(line))
        else:
            sdk = root
            # the listing holds paths RELATIVE to the SDK root, so the absolute directory is two
            # levels up from Headers/ - System/Library/Frameworks/<F>.framework/Headers -> the
            # framework's own directory
            relative = line.split("Frameworks/", 1)[-1]
            paths.append(os.path.join(sdk, "System", "Library", "Frameworks",
                                      relative.split(".framework/")[0] + ".framework", "Headers"))
    return paths


def framework_paths_for(listing_path, root=None):
    """Where a listing's FRAMEWORKS live, for `-F`.

    These headers include each other framework-qualified - `#import <Metal/MTLAccelerationStructure.h>`
    - and a qualified include is not an include path: clang resolves it against the sysroot's
    framework layout, so a copy placed on `-I` is simply not found that way and the header comes
    from the SDK instead. With only the Headers directory on `-I`, every header was therefore
    included TWICE - once from the copy by bare name, once from the SDK by its qualified name - and
    clang said so, 20 errors deep, on a property with a previous declaration.
    """
    root = root or sdk_path()
    frameworks = []
    for line in open(listing_path or HEADER_LIST).read().split("\n"):
        if not line.strip() or ".framework/" not in line:
            continue
        if not os.path.isabs(line):
            frameworks.append(os.path.join(root, "System", "Library", "Frameworks"))
            break
        # an absolute listing names the .framework itself, so its parent is the framework path
        frameworks.append(os.path.dirname(os.path.dirname(line)))
    return sorted(set(frameworks))


def frameworks_for(sdk):
    """The frameworks the listing names, which is where their header directories are."""
    seen = []
    for line in open(HEADER_LIST).read().split("\n"):
        if ".framework/" in line:
            name = line.split("Frameworks/", 1)[1].split(".framework/", 1)[0]
            if name not in seen:
                seen.append(name)
    return seen


def headers(framework, listing_path=None):
    """The listing's header lines for one framework, whatever the listing's lines are rooted at.

    A line is matched by the framework it names, not by the SDK directory in front of it, because a
    control's copy is rooted elsewhere and the same listing has to read the same lines against it.
    That is what the third control measured and did not have: it wrote absolute paths, this filter
    dropped every one of them, and the count came back as zero - which reads exactly like a control
    that moved a number by 11379 because it moved a number, and is really a control that read
    nothing at all.
    """
    listing = open(listing_path or HEADER_LIST).read().split("\n")
    return [line for line in listing
            if ".framework/" in line
            and line.split("Frameworks/", 1)[1].split(".framework/", 1)[0] == framework]


def dump_ast(sdk, include, output=None, include_paths=(), framework_paths=()):
    command = ["xcrun", "clang", "-x", "objective-c", "-fsyntax-only", "-target", "arm64-apple-ios",
               "-isysroot", sdk, "-Xclang", "-ast-dump=json"]
    for directory in include_paths:
        command += ["-I", directory]
    for directory in framework_paths:
        command += ["-F", directory]
    command += ["-o", output] if output else []
    command.append(include)
    return subprocess.run(command, capture_output=True, text=True, check=False)


def walk(node):
    """Every node in clang's JSON AST, which is a tree of dicts with a `kind` and a `name`."""
    if isinstance(node, dict):
        yield node
        for child in node.get("inner", []):
            yield from walk(child)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def from_mangled(mangled):
    """(owner, selector) out of an ObjCMethodDecl's mangledName.

    clang's JSON AST gives a method's `name` as a SELECTOR PIECE - "newHeapWithDescriptor" with no
    colon - and a registry's rows carry the WHOLE selector, so the two never met and 6959 declared
    matched nothing. `mangledName` is "[-[MTLDevice newHeapWithDescriptor:]" - the owner and the whole
    selector - so this is where the member and its owner both come from, and the parameters are not
    assembled at all.
    """
    text = mangled or ""
    if not text.startswith(("[+[")) and " " not in text:
        return None, None
    sign = 1 if text.startswith("+[") else 0
    inner = text[2:] if sign else text[2:]
    space = inner.find(" ")
    if space < 0:
        return None, None
    owner, rest = inner[:space], inner[space + 1:]
    cut = rest.find("]")
    if cut < 0:
        return None, None
    return owner, rest[:cut]


def selector_of(name):
    """`newBufferWithLength:options:` — the member's name is the selector, or the property's setter."""
    if ":" in name or name.endswith(":"):
        return name
    if name.startswith("init") and name.endswith(":"):
        return name
    return "set" + name[:1].upper() + name[1:] + ":"


def parse_ast(sdk, imports, include_paths=(), framework_paths=()):
    """clang's AST for one translation unit, or None with clang's own error if it does not compile."""
    with tempfile.TemporaryDirectory() as work:
        include = os.path.join(work, "include.m")
        with open(include, "w") as handle:
            for name in imports:
                handle.write("#import <%s>\n" % name)
        result = dump_ast(sdk, include, None, include_paths, framework_paths)
    if result.returncode != 0:
        return None, result.stderr
    # -ast-dump=json writes to stdout, not to -o.
    return json.loads(result.stdout), None


def declarations(sdk, framework, verbose=False, listing=None, root=None):
    """{owner: {member, ...}} for one framework, from clang and from nothing else.

    `root` is where the listing's relative paths are resolved, and the sysroot is always the real
    SDK: a control's copy holds the framework under test and nothing else, so everything else the
    headers import still comes from the SDK. The copy is on the include path, and an include path is
    searched before the sysroot, so the copy's header is the one clang reads."""
    lines = headers(framework, listing)
    if not lines:
        return {}, []
    # The UMBRELLA first, and the individual headers after it, and not as a convenience: MetalFX's
    # headers are not order-independent. Listed alphabetically, MTLFXFrameInterpolator.h uses the
    # protocol MTLFXFrameInterpolatableScaler and MTLFXTemporalDenoisedScaler.h adopts a protocol it
    # cannot find, and clang stops at two errors. MetalFX.h is how a client consumes the framework
    # and it compiles clean on its own, so the umbrella goes first and the listing's headers follow
    # for the count of headers the framework really has.
    umbrella = [line for line in lines if os.path.basename(line) == framework + ".h"]
    document, error = parse_ast(sdk, ["Foundation/Foundation.h"] + [
        os.path.basename(relative) for relative in umbrella + [l for l in lines if l not in umbrella]],
        include_paths_for(listing, root), framework_paths_for(listing, root))
    if document is None:
        raise SystemExit("clang failed for %s:\n%s" % (framework, error[-2000:]))
    members, names = collect(document)
    return dict(members), names, lines


def collect(document):
    """(members, names) from one AST: the members of every interface, protocol and category, and
    the names of every class, protocol, function, constant and enumeration constant."""
    members, names = collections.defaultdict(set), set()
    for node in walk(document):
        kind = node.get("kind")
        name = node.get("name") or ""
        if kind in ("ObjCInterfaceDecl", "ObjCProtocolDecl") and name:
            # the type's OWN members live in its `inner`, and a count that skipped them was caught by
            # the control that looks for a member known to be in a Metal header: newBufferWithLength:
            # options: is declared on MTLBuffer and was not found.
            names.add(name)
            for child in node.get("inner", []):
                # ObjCMethodDecl, and NOT ObjCInstanceMethodDecl: that kind does not exist in
                # clang's JSON AST. Measured over MTLDevice.h's top-level declarations: 4555
                # ObjCMethodDecl, 1597 ObjCPropertyDecl, 127 ObjCIvarDecl, and none of the kind
                # this tool was filtering on - so every method in the framework was being dropped.
                if child.get("kind") == "ObjCMethodDecl":
                    owner, selector = from_mangled(child.get("mangledName"))
                    if owner == name and selector:
                        members[name].add(selector)
                elif child.get("kind") in ("ObjCIvarDecl", "ObjCPropertyDecl") and child.get("name"):
                    members[name].add(selector_of(child["name"]))
        elif kind == "ObjCCategoryDecl":
            inner = [n for n in node.get("inner", []) if n.get("kind") in
                     ("ObjCInstanceMethodDecl", "ObjCClassMethodDecl", "ObjCIvarDecl", "ObjCPropertyDecl")]
            if not inner:
                continue
            owner = None
            for child in walk(node):
                if child is not node and child.get("kind") == "ObjCInterfaceDecl":
                    owner = child.get("name")
                    break
            if owner:
                names.add(owner)
                for child in inner:
                    if child.get("kind") == "ObjCMethodDecl":
                        _, selector = from_mangled(child.get("mangledName"))
                        if selector:
                            members[owner].add(selector)
                    elif child.get("name"):
                        members[owner].add(selector_of(child["name"]))
        elif kind == "EnumConstantDecl" and name:
            # an enumeration constant: MTLPurgeableStateKeepCurrent and its neighbours are what a
            # registry row names, and it is a name and not a selector
            names.add(name)
        elif kind in ("FunctionDecl", "VarDecl") and name:
            # A file-scope function or constant of a Metal header: only those the framework's own
            # headers declare, which the include list is what selects. These are NAMES -
            # MTKMetalVertexDescriptorFromModelIO() is a function, and run through selector_of() it
            # became setMTKMetalVertexDescriptorFromModelIO():, which is a member no header declares
            # and which no registry row can be asking about.
            names.add(name)
    return dict(members), names


def rows_for(framework, registry=None):
    """The registry's rows as (owner, member, is_a_name).

    A row's api is one of three spellings and they mean three different things, which is a thing to
    keep rather than to flatten: `-[Class sel]` and `Class.sel` are a MEMBER, and a bare `api` is a
    NAME - the class MTKMesh, or the function MTKMetalVertexDescriptorFromModelIO(). A bare api
    mapped to (api, api) matched no selector ever, so all 29 MetalKit rows read as uncovered: they
    are not uncovered, they are not members, and the count that said they were was asking the wrong
    question of them.
    """
    directory = os.path.join(registry or REGISTRY, framework)
    rows = collections.defaultdict(set)
    kinds = collections.defaultdict(set)
    if not os.path.isdir(directory):
        return rows, kinds
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json"):
            continue
        document = json.load(open(os.path.join(directory, name)))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            api = entry["api"]
            match = re.match(r"^[-+]\[([A-Za-z0-9_]+)\s", api)
            if match:
                owner, member = match.group(1), api.split(None, 1)[1].rstrip("]")
                rows[owner].add(member.strip())
            else:
                parts = api.split(".", 1)
                if len(parts) == 2:
                    rows[parts[0]].add(parts[1])
                else:
                    kinds[api].add(entry.get("kind", "name"))
    return rows, kinds


def header_ast(sdk, header):
    """The AST of ONE header, so a control can say which header a member was found in."""
    directory = os.path.join(sdk, "System", "Library", "Frameworks", "Metal.framework", "Headers")
    with tempfile.TemporaryDirectory() as work:
        include = os.path.join(work, "one.m")
        with open(include, "w") as handle:
            handle.write("#import <Foundation/Foundation.h>\n#import <%s>\n" % header)
        result = dump_ast(sdk, include, None, [directory])
    if result.returncode != 0:
        return set()
    names = set()
    for node in walk(json.loads(result.stdout)):
        if node.get("name"):
            names.add(node["name"])
    return names


def controls(sdk, members):
    """The three controls, run and reported. A count with no control is a number with no meaning."""
    everything = {name for per_owner in members.values() for name in per_owner}
    ok = True
    print("controls:")
    for header, owner, member in CONTROLS:
        found = member in header_ast(sdk, header)
        ok = ok and found
        print("  %-16s %-11s %-28s %s" % ("member in a header", owner, member, "found" if found else "NOT FOUND"))
    absent = CONTROL_ABSENT not in everything
    ok = ok and absent
    print("  a name in no Metal header is found zero times          %s  (%r)" % (absent, CONTROL_ABSENT))
    return ok


def match_control(members, rows, framework="Metal"):
    """THE MATCH, tested: a member with a known `implemented` row counts as covered, and the same
    member with that row REMOVED counts as no row. The first three controls say nothing about the
    match, which is how 6959 declared matched nothing and the number looked like a measurement."""
    # a BRACKET-form row, which is a METHOD: a class row is a dotted one, and testing it would be
    # testing something else - which is what the first version of this control did.
    implemented = []
    # rows of THE FRAMEWORK BEING COUNTED, not of every framework in the tree: the first version of
    # this control sorted the whole registry and picked a SceneKit row, and so tested a framework
    # this run says nothing about.
    for directory in [framework]:
        if not os.path.isdir(os.path.join(REGISTRY, directory)):
            continue
        for name in sorted(os.listdir(os.path.join(REGISTRY, directory))):
            if not name.endswith(".json"):
                continue
            document = json.load(open(os.path.join(REGISTRY, directory, name)))
            for entry in (document["entries"] if isinstance(document, dict) else document):
                if entry["status"] == "implemented" and DECL.search(entry["api"]):
                    match = re.match(r"^[-+]\[([A-Za-z0-9_]+)\s", entry["api"])
                    if match:
                        implemented.append((match.group(1),
                                           entry["api"].split(None, 1)[1].rstrip("]")))
    if not implemented:
        print("  a known implemented METHOD row is counted as covered   FOUND NONE - the control has"
              " nothing to test and says so")
        return False
    implemented.sort()
    owner, member = implemented[0]
    covered = member in rows.get(owner, ())
    print("  a known implemented row is counted as covered        %s  (%s.%s, %d row(s) for it)"
          % (covered, owner, member, len(rows[owner])))
    # and the same member with that row taken away, on a scratch copy of the registry under
    # .agent-work and NEVER on the checkout
    scratch = os.path.join(".agent-work", "runs", "uncovered", "scratch-registry")
    os.makedirs(scratch, exist_ok=True)
    os.makedirs(os.path.join(scratch, "Metal"), exist_ok=True)
    for name in os.listdir(os.path.join(REGISTRY, "Metal")):
        if name.endswith(".json"):
            with open(os.path.join(REGISTRY, "Metal", name)) as handle:
                text = handle.read()
            with open(os.path.join(scratch, "Metal", name), "w") as handle:
                handle.write(text)
    # EVERY file in the scratch copy is thinned, not one: the row lives in ios8blit.json, so a single
    # new "thinned.json" that dropped it left the original beside it and the union still had it - which
    # is what the control's own value showed, 17 rows before and 17 after, of 1160 entries kept.
    target = "-[%s %s]" % (owner, member)
    kept_total, thinned = 0, 0
    for name in sorted(os.listdir(os.path.join(scratch, "Metal"))):
        if not name.endswith(".json"):
            continue
        path = os.path.join(scratch, "Metal", name)
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        kept = [e for e in entries if e["api"] != target]
        thinned += len(entries) - len(kept)
        kept_total += len(kept)
        with open(path, "w") as handle:
            json.dump({"framework": "Metal", "entries": kept}, handle, indent=2)
    before = len(rows.get(owner, ()))
    after, _ = rows_for(framework, scratch)
    gone = member not in after.get(owner, ())
    print("  and with that row removed, it moves back               %s  (scratch %s: %d row(s) for %s, was %d; %d row(s) removed, %d kept)"
          % (gone, scratch, len(after.get(owner, ())), owner, before, thinned, kept_total))
    return covered and gone


def third_control(framework, members, verbose, listing=None):
    """One declaration removed from a scratch COPY of the headers: the count must move by exactly one.

    The copy is this repository's own, under .agent-work: reading the shared SDK to make a copy is
    what the rule allows, and writing into it is what it forbids. Nothing here touches the SDK.

    The copy is laid out exactly as the SDK is - System/Library/Frameworks/<F>.framework/Headers -
    so the listing needs no change at all: the tool is told where the copy is ROOTED and reads the
    same lines against it, which is what makes this a control on the counting rather than a second
    code path that might count differently. It is re-copied on every run, because a copy left over
    from a run whose line was already removed would be one declaration short before the removal.
    """
    scratch = os.path.join(".agent-work", "runs", "uncovered", "scratch-sdk")
    sdk = sdk_path()
    source = os.path.join(sdk, "System", "Library", "Frameworks", framework + ".framework", "Headers")
    if not os.path.isdir(source):
        print("  one declaration removed from a scratch copy            NO HEADERS FOR %s" % framework)
        return False
    copy_headers = os.path.join(scratch, "System", "Library", "Frameworks",
                                framework + ".framework", "Headers")
    if os.path.isdir(scratch):
        shutil.rmtree(scratch)
    os.makedirs(os.path.dirname(copy_headers), exist_ok=True)
    shutil.copytree(source, copy_headers)
    # the ONE declaration removed: named here with its selector, so the removal is not a guess
    target_header, target_selector = "MTLDevice.h", "newSharedEventWithHandle:"
    path = os.path.join(copy_headers, target_header)
    if not os.path.isfile(path):
        print("  one declaration removed from a scratch copy            NO %s IN THE COPY" % target_header)
        return False
    with open(path) as handle:
        text = handle.read()
    at = text.find(target_selector)
    if at < 0:
        print("  one declaration removed from a scratch copy            %s NOT IN %s" % (target_selector, target_header))
        return False
    line_start = text.rfind("\n", 0, at) + 1
    line_end = text.find("\n", at) + 1
    with open(path, "w") as handle:
        handle.write(text[:line_start] + text[line_end:])
    # the SAME listing, with the copy named as the root it is read against
    before = sum(len(v) for v in members.values())
    with_copy, _, _ = declarations(sdk, framework, False, listing, scratch)
    after = sum(len(v) for v in with_copy.values())
    moved = before - after
    print("  one declaration removed from a scratch copy            %s  (%s %s: %d declared -> %d, moved by %d)"
          % (moved == 1, target_header, target_selector, before, after, moved))
    print("      the copy is rooted at %s, laid out as the SDK, and the SDK is untouched" % scratch)
    return moved == 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--framework", default=None, choices=FRAMEWORKS)
    parser.add_argument("--no-ast", action="store_true", help="skip the third control, which compiles twice")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--registry", default=None,
                        help="a scratch copy of the registry to read, for a control; never the checkout's")
    parser.add_argument("--headers", default=None, help="a scratch header list, for a control")
    parser.add_argument("--sdk-root", default=None,
                        help="root the listing's relative paths resolve against, for a control that "
                             "copies the headers; the sysroot is still the real SDK")
    options = parser.parse_args()
    frameworks = [options.framework] if options.framework else list(FRAMEWORKS)
    sdk = sdk_path()
    registry = os.path.abspath(options.registry) if options.registry else REGISTRY
    print("SDK       %s" % sdk)
    print("registry   %s%s" % (registry, "  (SCRATCH)" if options.registry else ""))
    print("headers    %s%s" % (options.headers or HEADER_LIST, "  (SCRATCH)" if options.headers else ""))
    print("root      %s%s" % (options.sdk_root or sdk, "  (SCRATCH)" if options.sdk_root else ""))
    for framework in frameworks:
        members, names, lines = declarations(sdk, framework, options.verbose, options.headers,
                                           options.sdk_root)
        if not members:
            print("\n%-12s no declarations" % framework)
            continue
        rows, name_rows = rows_for(framework, registry)
        # The declared side is the UNION the spec asks for: every interface, protocol and category
        # member, and every class, protocol, function, constant and enumeration constant, by name.
        # A member row is covered by its owner's members; a NAME row - a bare api, the class MTKMesh
        # or the function MTKMetalVertexDescriptorFromModelIO() - is covered by the declared NAMES.
        #
        # WHAT THIS IS NOT: a per-header table. One translation unit of the umbrella pulls in every
        # header the framework's own headers import - MetalKit's five headers drag QuartzCore, and
        # UIKit - so these counts include declarations the framework does not own. Measured over
        # MTKView.h: 2941 interfaces and protocols in the AST, 1995 of them with no loc.file at all
        # and MTKView among them, so clang's JSON AST does not attribute a definition to the header
        # that declares it, and a file filter drops the framework's own classes along with the rest.
        # Per-header numbers need the header's own contribution measured as a DIFFERENCE against a
        # Foundation-only translation unit, one compile per header, and that is not done here.
        total_members = sum(len(v) for v in members.values())
        covered_members = sum(1 for owner, v in members.items() for m in v if m in rows.get(owner, ()))
        covered_names = len(names & set(name_rows))
        print("\n%-12s %2d headers  %6d member(s) declared  %4d with a row  %4d with no row"
              % (framework, len(lines), total_members, covered_members, total_members - covered_members))
        print("            %6d name(s) declared    %4d with a row  %4d with no row  (%d member row(s), %d name row(s))"
              % (len(names), covered_names, len(names) - covered_names,
                 sum(len(v) for v in rows.values()), len(name_rows)))
        if framework == "Metal":
            controls(sdk, members)
            match_control(members, rows, framework)
            if not options.no_ast:
                print("  one declaration removed from a scratch copy: %s"
                      % ("the count moved by exactly one"
                         if third_control(framework, members, options.verbose, options.headers)
                         else "NOT SATISFIED"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
