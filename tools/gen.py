#!/usr/bin/env python3
"""The reference implementation of the apple-backports generator for the commands tools/gen.lua does not reproduce yet.

Nothing in a build, a check or a gate runs this file: `xmake l tools/gen.lua gen|check|trace|diff|pin|members|sources` read the
declaration shards (tools/found) and need no Python. What stays here is what the Lua generator has not taken over, or has taken
over and not yet had re-verified byte for byte against this file (the v-gen2 band's work, after which the file is deleted):

    gen.py input  --tree T --framework F --ledger L --sdk S [--owned FILE]   the constants record: the 26.2 SDK headers and
                                                                             the values of the macOS framework (the host
                                                                             oracle, tools/gen-objc-constants-oracle.m)
    gen.py protocols | functions                                             not ported
    gen.py doc | scope | objc | swift | behaviour                            ported; the reference of the port's checks

The copies of gen, check, pin, trace, diff, sources, members and headers that this file once held were removed: the Lua commands had
replaced them (their output differs by design since the switch to the shards), so they could no longer serve as an oracle.
Design: coordination/wave-2026-10-03/design-spec-driven.md.
"""

import argparse
import csv
import glob
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import time

VERSION = "2"
SOURCES_ROOT = "packages/a/apple-backports"
# The committed snapshot of each framework (data only: the rows the generator reads, and the reviewed classification), and
# the build directory the generator writes into (gitignored; the xmake build and check_registry regenerate it first).
SNAP_ROOT = "packages/a/apple-backports/spec"
OUT_ROOT = "packages/a/apple-backports/.gen"
PINS_ROOT = "packages/a/apple-backports/overrides/hashes"
REGISTRY = "packages/a/apple-backports/registry"
HOST = "/System/Library/Frameworks"
SDK_ID = "sdk-26.2-headers"
SPEC_COLUMNS = ["kind", "api", "cls", "key", "introduced", "decl", "availability", "hash", "value_status", "value",
                "host_value", "value_source", "owned", "tbd", "shape", "measured"]
# v-cache26's table of the iOS 26.2 cache: the iOS value of every exported constant, the expectation wherever it exists.
IOS_CONSTANTS = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "coordination", "corpus", "cache-26.2",
                             "constants-26.2.tsv")
# The 26.2 SDK, the spec's input and the type resolver's source (a workspace path, not a literal one).
SDK26 = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "charon", ".agent-work", "sdk-26.2", "iPhoneOS26.2.sdk")
AVAIL = re.compile(r"\b\w*(?:AVAILABLE|DEPRECATED|OBSOLETED)\w*\s*\((?:[^()]|\([^()]*\))*\)")
STRING_TYPES = {"NSString", "CFStringRef"}


def digest(*parts):
    return hashlib.sha256("\x1f".join(parts).encode("ascii")).hexdigest()[:16]


def mangle(api):
    """A C identifier for a spec member. A class method is +[...]: its key carries the sign, so it never collides with
    the instance method of the same selector."""
    prefix = "class_" if api.startswith("+") else ""
    return prefix + re.sub(r"[^A-Za-z0-9]+", "_", api).strip("_")


def release_key(release):
    return [int(p) for p in release.split(".")]


def write(path, text):
    text.encode("ascii")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as handle:
        handle.write(text)


def read(path):
    with open(path, encoding="ascii") as handle:
        return handle.read()


def snap_dir(tree, fw):
    """The committed snapshot of a framework: spec, measured releases, classification, and the manifest of generated digests."""
    return os.path.join(tree, SNAP_ROOT, fw)


def gen_dir(tree, fw):
    """The build directory of a framework: what the generator emits. Never committed."""
    return os.path.join(tree, OUT_ROOT, fw)


def spec_path(tree, fw):
    return os.path.join(snap_dir(tree, fw), "spec.%s.tsv" % SDK_ID)


def pins_path(tree, fw):
    return os.path.join(tree, PINS_ROOT, fw + ".tsv")


# ---------------------------------------------------------------- SDK headers: declarations and members

def strip_macros(text):
    avail = " ".join(AVAIL.findall(text))
    text = AVAIL.sub(" ", text)
    # the SDK's own macros after a declaration (__TVOS_PROHIBITED, API_DEPRECATED_WITH_REPLACEMENT("..."), NS_REFINED_FOR_SWIFT):
    # none is a name, so none may be the last identifier
    text = re.sub(r"\b(?:API|NS|OS|CF|__)_?[A-Z][A-Z0-9_]*\s*\((?:[^()]|\([^()]*\))*\)", " ", text)
    text = re.sub(r"\b(?:API|NS|OS|CF)_[A-Z][A-Z0-9_]*\b|\b__[A-Z][A-Z0-9_]*\b", " ", text)
    text = re.sub(r"\b__attribute__\s*\(\((?:[^()]|\([^()]*\))*\)\)", " ", text)
    text = re.sub(r"\bNS_[A-Z_]+\b(?:\s*\((?:[^()]|\([^()]*\))*\))?", " ", text)
    return " ".join(text.split()), " ".join(avail.split())


TRAILING_MACRO = re.compile(r"(?:\s+[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+(?:\s*\((?:[^()]|\([^()]*\))*\))?)+\s*$")


def without_trailing_macros(text):
    """The declaration without the project macros after it (CS_TVOS_UNAVAILABLE, UI_APPEARANCE_SELECTOR, FILEPROVIDER_API_
    AVAILABILITY_DESKTOP): a name or a selector is the last identifier that is not one of them. The declaration text keeps them."""
    return TRAILING_MACRO.sub("", " " + text.rstrip(" ;") + " ").strip()


def selector_of(stmt):
    s = stmt.lstrip("-+ ").strip()
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\([^()]*\)", " ", s)
    if ":" not in s:
        words = re.findall(r"[A-Za-z_]\w*", s)
        return words[-1] if words else None
    return "".join(k + ":" for k in re.findall(r"([A-Za-z_]\w*)\s*:", s))


def members_of(text):
    """(class, statement kind, api, statement) for each property and method of each @interface in the header text."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    text = re.sub(r"(?m)^\s*#[^\n]*", " ", text)
    events = [(m.start(), "open", m) for m in re.finditer(r"@interface\s+(\w+)\s*(?:\(\s*\w*\s*\))?", text)]
    events += [(m.start(), "close", m) for m in re.finditer(r"@protocol\s+\w+\s*(?!;)|@end\b", text)]
    events.sort(key=lambda e: e[0])
    out = []
    for index, (pos, kind, match) in enumerate(events):
        if kind != "open":
            continue
        end = next((e[0] for e in events[index + 1:] if e[1] == "close"), len(text))
        body = text[match.end():end]
        # a superclass (`: Base <Proto>`) or a category's protocol list (`(Cat) <Proto>`) comes before the members
        body = re.sub(r"^\s*(?::\s*\w+\s*)?(?:<[^>]*>)?\s*", "", body, count=1)
        if body.startswith("{"):
            depth = 0
            for i, ch in enumerate(body):
                depth += ch == "{"
                depth -= ch == "}"
                if depth == 0:
                    body = body[i + 1:]
                    break
        cls = match.group(1)
        for stmt in split_statements(body):
            stmt = re.sub(r"^\s*@(?:optional|required)\s*", "", stmt)
            # a macro with no semicolon before a declaration (AV_INIT_UNAVAILABLE, then the next @property) joins that statement:
            # it is not part of the declaration, and it would hide the property or selector from the dispatch below
            stmt = re.sub(r"^(?:\s*[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\s+)+(?=@property\b|[-+]\s*\()", "", stmt)
            if stmt.startswith("@property"):
                clean, avail = strip_macros(stmt)
                core = without_trailing_macros(clean)
                # a block or function-pointer property names itself inside its parentheses: (^completionHandler)
                named = re.search(r"\(\s*\^\s*(\w+)\s*\)", core)
                name = [named.group(1)] if named else re.findall(r"([A-Za-z_]\w*)\s*$", core)
                if name:
                    out.append((cls, "property", "-[%s %s]" % (cls, name[-1]), "%s.%s" % (cls, name[-1]), clean, avail))
            elif stmt[:1] in "-+":
                clean, avail = strip_macros(stmt)
                sel = selector_of(without_trailing_macros(clean))
                if sel:
                    api = "%s[%s %s]" % (stmt[0], cls, sel)
                    out.append((cls, "method", api, api, clean, avail))
    return out


def split_statements(body):
    out, buf, paren, brace = [], [], 0, 0
    for ch in body:
        if ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        elif ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        if brace == 0 and paren == 0 and ch == ";":
            out.append("".join(buf).strip())
            buf = []
        elif brace == 0:
            buf.append(ch)
    return [s for s in out if s]


def header_text(sdk, fw):
    base = os.path.join(sdk, "System", "Library", "Frameworks", fw + ".framework", "Headers")
    return "\n".join(read_any(p) for p in sorted(glob.glob(os.path.join(base, "*.h"))))


def read_any(path):
    with open(path, errors="ignore") as handle:
        return handle.read()


def string_typedefs(sdk, fw):
    names = set()
    for f in (fw, "Foundation", "CoreFoundation"):
        base = os.path.join(sdk, "System", "Library", "Frameworks", f + ".framework", "Headers", "*.h")
        for path in glob.glob(base):
            for match in re.finditer(r"typedef\s+(?:const\s+)?(?:NSString\s*\*?|CFStringRef)\s*\*?\s*(?!const\b)(\w+)\b[^;]*;",
                                     read_any(path)):
                names.add(match.group(1))
    return names


def constant_decls(sdk, fw, names, typedefs):
    wanted, found = set(names), {}
    for path in sorted(glob.glob(os.path.join(sdk, "System", "Library", "Frameworks", fw + ".framework", "Headers", "*.h"))):
        # a comment on a declaration's line can name another constant: the comment is not part of any declaration
        for line in re.sub(r"/\*.*?\*/", " ", read_any(path), flags=re.S).splitlines():
            line = re.sub(r"//.*", "", line)
            marked = "extern" in line or "EXTERN" in line or "EXPORT" in line
            for token in set(re.findall(r"\b[A-Za-z_]\w*\b", line)) & wanted:
                if token in found:
                    continue
                typed = re.match(r"^\s*(?:const\s+)?(\w+)\s+" + re.escape(token) + r"\b", line)
                if typed and typed.group(1) not in typedefs | STRING_TYPES:
                    typed = None
                # a CF header declares a constant with no marker of its own: `const CFStringRef kName API_AVAILABLE(...)`
                if not marked and not typed:
                    continue
                before = re.sub(r"\b" + re.escape(token) + r"\b.*", "", line)
                before = re.sub(r"^\s*(\w*EXTERN\w*|\w*EXPORT\w*|extern)\s*", "", before)
                clean, avail = strip_macros(line)
                decl = " ".join(w for w in before.split() if w not in ("_Nonnull", "__nonnull", "_Nullable", "__nullable"))
                found[token] = (decl.strip(), avail)
    return found


def cf_typedefs(sdk, fw):
    """Typedef names of a CFStringRef (not an NSString): SecKeyAlgorithm and the like, which a definition must bridge."""
    names = set()
    for f in (fw, "Foundation", "CoreFoundation", "Security"):
        for path in glob.glob(os.path.join(sdk, "System", "Library", "Frameworks", f + ".framework", "Headers", "*.h")):
            for match in re.finditer(r"typedef\s+(?:const\s+)?CFStringRef\s+(?!const\b)(\w+)\b[^;]*;", read_any(path)):
                names.add(match.group(1))
    return names


def object_shape(decl, typedefs):
    words = set(re.findall(r"\b[A-Za-z_]\w*\b", decl)) - {"const", "volatile"}
    return "string" if words & (STRING_TYPES | typedefs) else "numeric"


def tbd_exports(sdk, fw):
    """Symbols and classes the framework's .tbd exports on arm64 (the device slice), as two sets.

    A .tbd file holds several documents (the framework, then the private frameworks it re-exports), so every document is
    read. Version 3 writes `archs:` with arm64; version 4 writes `targets:` with arm64-ios; both are read.
    """
    path = os.path.join(sdk, "System", "Library", "Frameworks", fw + ".framework", fw + ".tbd")
    if not os.path.exists(path):
        return set(), set()
    symbols, classes = set(), set()
    for document in read_any(path).split("--- !tapi-tbd")[1:]:
        for block in re.split(r"\n\s*-\s+(?=archs:|targets:)", document)[1:]:
            head = re.match(r"(?:archs|targets):\s*\[([^\]]*)\]", block)
            if not head:
                continue
            names = [a.strip() for a in head.group(1).split(",")]
            if not any(n == "arm64" or n.startswith("arm64-") for n in names):
                continue
            for key, into in (("symbols", symbols), ("objc-classes", classes)):
                found = re.search(r"\n\s*" + key + r":\s*\[(.*?)\]", block, re.S)
                if found:
                    into.update(t.strip() for t in found.group(1).replace("\n", " ").split(",") if t.strip())
    return set(s[1:] if s.startswith("_") else s for s in symbols), classes


# ---------------------------------------------------------------- input (builds the spec table)

def probe(tree, fw, names):
    run = os.path.join(tree, ".agent-work", "runs", "gen", fw)
    os.makedirs(run, exist_ok=True)
    binary = os.path.join(run, "oracle")
    subprocess.run(["clang", "-fobjc-arc", "-w", "-framework", "Foundation",
                    os.path.join(tree, "tools", "gen-objc-constants-oracle.m"), "-o", binary], check=True)
    library = os.path.join(HOST, fw + ".framework", fw)
    values = {}

    def read(batch):
        # The oracle takes the names as arguments after the library (it reads no file): one run for the batch.
        result = subprocess.run([binary, library] + batch, capture_output=True, text=True)
        if result.returncode != 0:
            return False
        for line in result.stdout.splitlines():
            found, status, cls, value = line.split("\t")
            values[found] = (status, value)
        return True

    # One run over every name; when it fails, each name runs alone, so a crash is named for the name that caused it.
    if not read(names):
        for name in names:
            if not read([name]):
                values[name] = ("probe-crashed", "-")
    return values


def objc_escape(text):
    """The text as the body of an ObjC string literal, ASCII only, escaped the way tools/gen-objc-constants-oracle.m escapes it."""
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\n":
            out.append("\\n")
        elif 0x20 <= ord(ch) < 0x7f:
            out.append(ch)
        else:
            out.append("\\u%04X" % ord(ch) if ord(ch) < 0x10000 else "?")
    return "".join(out)


def ios_constants(path):
    """symbol -> the string the iOS 26.2 cache holds for it (cfstring kind), from v-cache26's constants table."""
    csv.field_size_limit(10 ** 8)
    values, conflicts = {}, set()
    if not os.path.exists(path) and os.path.exists(path + ".gz"):
        path = path + ".gz"
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", newline="", encoding="ascii", errors="replace") as handle:
        # QUOTE_NONE: the table holds quote characters inside values, and the default quoting drops such rows
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            if row["value_kind"] != "cfstring":
                continue
            name = row["symbol"][1:] if row["symbol"].startswith("_") else row["symbol"]
            if name in values and values[name] != row["value"]:
                conflicts.add(name)
            values.setdefault(name, row["value"])
    return values, conflicts


def measured_releases(path):
    """symbol -> first release the held caches export it in, from the gate's release-split output (object, symbol, release).

    A symbol the held caches do not export is `none`; a summary line (MIXED-RELEASES) is not a symbol and is skipped.
    """
    out = {}
    for line in read_any(path).splitlines():
        cols = line.split("\t")
        if len(cols) == 3 and cols[1].startswith("_") and cols[1] != "MIXED-RELEASES":
            out[cols[1][1:]] = cols[2]
    return out


def registry_constants(tree, fw):
    """name -> registry file, for every constant the framework's registry rows name (any status)."""
    out = {}
    for path in sorted(glob.glob(os.path.join(tree, REGISTRY, fw, "*.json")) + glob.glob(os.path.join(tree, REGISTRY, fw + ".json"))):
        with open(path) as handle:
            data = json.load(handle)
        for entry in (data.get("entries", []) if isinstance(data, dict) else data):
            if entry.get("kind") == "constant":
                out.setdefault(entry["api"], os.path.relpath(path, tree))
    return out


def surface_frameworks():
    """Every framework the 26.2 surface table names, in the table's order (the surface is the corpus every band works from)."""
    seen = []
    with open(os.path.join(LEDGER_DIR, "sdk-26.2-surface.tsv"), newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            if row["framework"] not in seen:
                seen.append(row["framework"])
    return seen


def cmd_input_all(args):
    """The spec snapshot of every surface framework that has a ledger; the rest (C header sets) are listed as skipped."""
    done, skipped, kept = [], [], []
    for fw in surface_frameworks():
        if not os.path.exists(os.path.join(LEDGER_DIR, "ledger-w45", fw + ".tsv")):
            skipped.append(fw)
            continue
        if os.path.exists(spec_path(args.tree, fw)):
            # a snapshot that exists was built with its own inputs (owned names, measured releases) and reviewed: it is kept
            kept.append(fw)
            continue
        sub = argparse.Namespace(tree=args.tree, framework=fw, ledger=os.path.join(LEDGER_DIR, "ledger-w45"), sdk=args.sdk,
                                 owned=None, measured=None, ios_constants=None)
        try:
            cmd_input(sub)
            done.append(fw)
        except (Exception, SystemExit) as error:  # a framework the inputs cannot read is named in the scope, not hidden
            skipped.append("%s (%s)" % (fw, str(error).splitlines()[0][:80] if str(error) else type(error).__name__))
    write(os.path.join(args.tree, GEN_INPUT_LOG), "input --all: %d built, %d kept (existing snapshots), %d skipped\nkept: %s\nskipped: %s\n"
          % (len(done), len(kept), len(skipped), ", ".join(kept), ", ".join(skipped)))
    print("input --all: %d built, %d kept, %d skipped (see %s)" % (len(done), len(kept), len(skipped), GEN_INPUT_LOG))
    return 0


def member_rows(sdk, fw, classes):
    """The method and property rows of the framework's 26.2 header: one per declared member, from the header parse alone."""
    rows, seen = [], set()
    for cls, kind, api, alias, decl, avail in members_of(ios_text(header_text(sdk, fw))[0]):
        if api in seen:
            continue
        seen.add(api)
        rows.append({"kind": kind, "api": api, "cls": cls, "key": mangle(api), "introduced": "-", "decl": decl,
                     "availability": avail or "-", "hash": digest(kind, api, decl, avail or "-"),
                     "value_status": "-", "value": "-", "host_value": "-", "value_source": "-", "owned": "-",
                     "tbd": "class-exported" if cls in classes else "class-not-exported", "shape": "-", "measured": "-",
                     "source": "26.2 SDK header of %s" % fw})
    return rows


def cmd_input(args):
    fw = args.framework
    typedefs = string_typedefs(args.sdk, fw)
    rows = []
    owned = {}
    if args.owned:
        for line in read_any(args.owned).splitlines():
            if line.strip():
                name, branch = line.split("\t")
                owned[name] = branch
    with open(os.path.join(args.ledger, fw + ".tsv"), newline="") as handle:
        ledger = [r for r in csv.DictReader(handle, delimiter="\t") if r["status"] == "missing"
                  and r["kind"] == "constant" and r["lang"] == "objc" and r["needs"] == "code+lift"]
    decls = constant_decls(args.sdk, fw, [r["api"] for r in ledger], typedefs)
    undeclared = [r["api"] for r in ledger if r["api"] not in decls]
    if undeclared and fw != "Foundation":
        # Foundation declares NSCalendarIdentifier and friends; a CoreFoundation row the ledger lists may be one of them
        decls.update(constant_decls(args.sdk, "Foundation", undeclared, typedefs))
    # A name the registry already holds, in any status (implemented, absent, ...), is a decision a person took: the generator
    # leaves it alone, so it is not generated and not read by the oracle.
    for name, path in registry_constants(args.tree, fw).items():
        owned.setdefault(name, "registry:" + path)
    strings = [r["api"] for r in ledger if r["api"] not in owned and r["api"] in decls
               and object_shape(decls[r["api"]][0], typedefs) == "string"]
    values = probe(args.tree, fw, strings) if strings else {}
    symbols, classes = tbd_exports(args.sdk, fw)
    if fw != "Foundation":
        foundation_symbols, _ = tbd_exports(args.sdk, "Foundation")
        symbols = symbols | foundation_symbols
    cf = cf_typedefs(args.sdk, fw)
    measured = measured_releases(args.measured) if args.measured else {}
    ios_path = args.ios_constants or IOS_CONSTANTS
    if not (os.path.exists(ios_path) or os.path.exists(ios_path + ".gz")):
        raise SystemExit("no iOS 26.2 constants table at %s (.gz)" % ios_path)
    ios, ios_conflicts = ios_constants(ios_path)
    ios_sha = hashlib.sha256(open(ios_path if os.path.exists(ios_path) else ios_path + ".gz", "rb").read()).hexdigest()[:16]
    differences = []
    if args.measured:
        keep = [(api, rel) for api, rel in sorted(measured.items())]
        write(os.path.join(snap_dir(args.tree, fw), "measured.held-caches.tsv"),
              "symbol\trelease\n" + "".join("%s\t%s\n" % (api, rel) for api, rel in keep))
    for r in ledger:
        decl, avail = decls.get(r["api"], ("", ""))
        if r["api"] in owned:
            status, value = "owned:" + owned[r["api"]], "-"
        elif not decl:
            status, value = "undeclared", "-"
        elif object_shape(decl, typedefs) != "string":
            status, value = "numeric", "-"
        else:
            status, value = values[r["api"]]
        host_value, source = value, "host-macos"
        if status == "found" and r["api"] in ios:
            value, source = objc_escape(ios[r["api"]]), "ios-26.2-cache"
            if value != host_value:
                differences.append((r["api"], host_value, value))
        elif status != "found" and r["api"] not in owned and r["api"] in ios and decl and object_shape(decl, typedefs) == "string":
            # The host does not carry the framework (AddressBookUI is iOS-only), so no host value exists: the iOS cache is the
            # only oracle, and it is the expectation.
            status, value, host_value, source = "found", objc_escape(ios[r["api"]]), "-", "ios-26.2-cache (no host value)"
        if status != "found":
            value = "-"
            host_value = "-"
        rows.append({"kind": "constant", "api": r["api"], "cls": "-", "key": mangle(r["api"]),
                     "introduced": r["introduced"], "decl": decl or "-", "availability": avail or "-",
                     "hash": digest("constant", r["api"], decl, avail), "value_status": status, "value": value,
                     "host_value": host_value, "value_source": source,
                     "owned": owned.get(r["api"], "-"),
                     "tbd": "exported" if r["api"] in symbols else "not-exported",
                     "shape": "cf" if constant_base(decl) in cf | {"CFStringRef"} else "ns",
                     "measured": measured.get(r["api"], "-"),
                     "source": "macOS %s framework, dlsym (tools/gen-objc-constants-oracle.m)" % fw})
    rows += member_rows(args.sdk, fw, classes)
    # Two members can mangle to one identifier (a selector with and without its colon); both then carry a digest of their
    # full name, so each key is one identifier and no member is dropped.
    keys = [r["key"] for r in rows]
    for r in rows:
        if keys.count(r["key"]) > 1:
            r["key"] = r["key"] + "_" + digest("key", r["api"])[:8]
    path = spec_path(args.tree, fw)
    lines = ["\t".join(SPEC_COLUMNS)]
    for r in rows:
        lines.append("\t".join(str(r[c]) for c in SPEC_COLUMNS))
    write(path, "\n".join(lines) + "\n")
    counts = {}
    for r in rows:
        counts[r["kind"]] = counts.get(r["kind"], 0) + 1
    print("spec %s: %s" % (os.path.relpath(path, args.tree), ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts))))
    write(os.path.join(gen_dir(args.tree, fw), "value-differences.tsv"),
          "api\thost_macos\tios_26_2\n" + "".join("%s\t%s\t%s\n" % d for d in sorted(differences)))
    print("values: %d constants read from the iOS 26.2 cache (table sha256 %s), %d differ from macOS (iOS wins); %d cache symbols with conflicting values"
          % (sum(1 for r in rows if r["value_source"].startswith("ios")), ios_sha, len(differences), len(ios_conflicts)))
    return 0


# ---------------------------------------------------------------- spec, overrides, pins

def load_spec(tree, fw):
    with open(spec_path(tree, fw), newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def load_pins(tree, fw):
    path = pins_path(tree, fw)
    if not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


# ---------------------------------------------------------------- constants and snapshots


def constant_base(decl):
    words = [w for w in re.findall(r"[A-Za-z_]\w*", decl) if w not in ("const", "volatile")]
    return words[0] if words else "NSString"


def frameworks_with_snapshot(tree):
    return sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(tree, SNAP_ROOT, "*", "spec.%s.tsv" % SDK_ID)))


# ---------------------------------------------------------------- trace layer: generated-but-unimplemented members

# The trace layer is the DEFAULTS of the design: a stub for every declared member of a framework that has no override and no
# hand implementation, compiled only with CHARON_TRACE_DEFAULTS. A stub logs `unimplemented: <framework> <selector>` once per
# member, then returns the zero of its return type (nil for an object, 0 for a scalar or enum, a zeroed struct), and sets the
# NSError an `NSError **` parameter names to an error in the framework's own domain. Block parameters are not invoked.
SCALAR_TYPES = {"BOOL", "bool", "char", "unsigned char", "short", "unsigned short", "int", "unsigned", "unsigned int", "long",
                "unsigned long", "long long", "unsigned long long", "float", "double", "NSInteger", "NSUInteger", "CGFloat",
                "NSTimeInterval", "size_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t"}
TYPE_INDEX_FRAMEWORKS = ("Foundation", "CoreFoundation", "CoreAudio", "CoreAudioTypes", "AudioToolbox", "AudioUnit", "CoreMedia",
                         "CoreGraphics", "CoreMIDI", "CoreVideo")


def strip_platform_blocks(text):
    """The text the iOS build sees: #if TARGET_OS_VISION (and its #else-less forms) blocks are removed, nested ones included."""
    out, depth = [], 0
    for line in text.split("\n"):
        stripped = line.strip()
        if depth == 0 and re.match(r"#\s*if\s+TARGET_OS_VISION\b", stripped):
            depth = 1
            continue
        if depth > 0:
            if re.match(r"#\s*if", stripped):
                depth += 1
            elif re.match(r"#\s*endif", stripped):
                depth -= 1
            continue
        out.append(line)
    return "\n".join(out)


# The TARGET_OS_ values the iOS build sees. A condition over these is decided; one over any other name is not, and both of its
# branches are kept as they were before (ios_text reports how many).
PLATFORM_VALUES = {"TARGET_OS_IPHONE": 1, "TARGET_OS_IOS": 1, "TARGET_OS_EMBEDDED": 1, "TARGET_OS_MAC": 0, "TARGET_OS_OSX": 0,
                   "TARGET_OS_VISION": 0, "TARGET_OS_WATCH": 0, "TARGET_OS_TV": 0, "TARGET_OS_SIMULATOR": 0,
                   "TARGET_OS_MACCATALYST": 0, "TARGET_OS_DRIVERKIT": 0, "TARGET_OS_BRIDGE": 0, "TARGET_OS_UIKITFORMAC": 0,
                   "TARGET_IPHONE_SIMULATOR": 0}


def platform_value(expr):
    """True, False, or None when the condition names something that is not a TARGET_OS_ value."""
    if not all(n in PLATFORM_VALUES for n in re.findall(r"\bdefined\s*\(\s*(\w+)\s*\)", expr)):
        return None
    names = set(re.findall(r"[A-Za-z_]\w*", re.sub(r"\bdefined\s*\(\s*\w+\s*\)", " ", expr)))
    if not all(n in PLATFORM_VALUES for n in names):
        return None
    py = re.sub(r"\bdefined\s*\(\s*\w+\s*\)", "1", expr)
    py = re.sub(r"\b([A-Za-z_]\w*)\b", lambda m: str(PLATFORM_VALUES[m.group(1)]), py)
    py = py.replace("&&", " and ").replace("||", " or ")
    py = re.sub(r"!(?!=)", " not ", py)
    if re.search(r"[^\d\s()a-z=!<>]", py):
        return None
    try:
        return bool(eval(py, {"__builtins__": {}}, {}))
    except (SyntaxError, TypeError, NameError):
        return None


def ios_text(text):
    """The header text as the iOS build reads it: each #if over TARGET_OS_ values keeps the branch that holds for iOS and drops
    the rest; a condition this cannot decide keeps every branch. Returns (text, count of undecided conditions)."""
    out, stack, undecided = [], [], 0

    def active():
        return all(frame["active"] for frame in stack)

    # a directive named inside a comment is not one: comments become spaces, and every line stays where it was
    text = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    for line in text.split("\n"):
        stripped = line.strip()
        found = re.match(r"#\s*(if|ifdef|ifndef|elif|else|endif)\b\s*(.*)$", stripped)
        if not found:
            if active():
                out.append(line)
            continue
        directive, rest = found.group(1), found.group(2)
        parent = active()
        if directive in ("if", "ifdef", "ifndef"):
            expr = rest if directive == "if" else ("defined(%s)" % rest.strip() if directive == "ifdef" else "!defined(%s)" % rest.strip())
            value = platform_value(expr)
            if value is None:
                undecided += 1
                stack.append({"parent": parent, "known": False, "taken": False, "active": parent})
            else:
                stack.append({"parent": parent, "known": True, "taken": value, "active": parent and value})
        elif directive == "elif":
            frame = stack[-1]
            if frame["known"]:
                value = False if frame["taken"] else platform_value(rest)
                if value is None:
                    undecided += 1
                    frame.update(known=False, active=frame["parent"])
                else:
                    frame.update(taken=frame["taken"] or value, active=frame["parent"] and value and not frame["taken"])
            else:
                frame["active"] = frame["parent"]
        elif directive == "else":
            frame = stack[-1]
            frame["active"] = frame["parent"] and (not frame["taken"] if frame["known"] else True)
        elif directive == "endif" and stack:
            stack.pop()
    return "\n".join(out), undecided


def declared_names(sdk, fw):
    """Every typedef, class and protocol name the iOS build sees in the framework and the frameworks its types come from."""
    names, unavailable_on_ios = set(), set()
    for f in (fw,) + TYPE_INDEX_FRAMEWORKS + ("AVFAudio",):
        for path in glob.glob(os.path.join(sdk, "System", "Library", "Frameworks", f + ".framework", "Headers", "*.h")):
            text = strip_platform_blocks(re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", read_any(path), flags=re.S)))
            names.update(re.findall(r"typedef\s[^;]*?\b(\w+)\s*(?:NS_\w+|API_\w+|OS_\w+|CF_\w+)?[^;]*;", text))
            names.update(re.findall(r"@(?:interface|protocol)\s+(\w+)", text))
            names.update(re.findall(r"typedef\s+(?:NS_ENUM|NS_OPTIONS|NS_TYPED_ENUM|NS_TYPED_EXTENSIBLE_ENUM|CF_ENUM|enum)[^;]*?\b(\w+)\s*;", text, re.S))
            # a class the iOS SDK marks unavailable is not a type the iOS build can name (CASpatialAudioExperience, visionOS only)
            for found in re.finditer(r"@interface\s+(\w+)\s*(?=[:<{\n])", text):
                # a class, not a category: its availability macros are on the line after the previous declaration, or on its own line
                before = re.split(r"[;}]|@end", text[:found.start()])[-1]
                after = text[found.end():].split("\n", 1)[0]
                if re.search(r"API_UNAVAILABLE\s*\([^)]*\bios\b", before + " " + after):
                    unavailable_on_ios.add(found.group(1))
    return names - unavailable_on_ios


def type_index(sdk, fw):
    """typedef name -> the text it is defined as, from the framework and the frameworks its types come from."""
    index = {}
    for f in (fw,) + TYPE_INDEX_FRAMEWORKS:
        for path in glob.glob(os.path.join(sdk, "System", "Library", "Frameworks", f + ".framework", "Headers", "*.h")):
            # comments first: a doc comment that mentions `typedef` would otherwise start a match that runs into the real one
            text = re.sub(r"/\*.*?\*/", " ", read_any(path), flags=re.S)
            text = strip_platform_blocks(re.sub(r"//[^\n]*", " ", text))
            for match in re.finditer(r"typedef\s+([^;{}]*?)\s*\b(\w+)\s*(?:API_\w+\([^;]*?\)\s*)*;", text):
                index.setdefault(match.group(2), " ".join(match.group(1).split()))
            for match in re.finditer(r"typedef\s+(?:struct|enum)\b[^{;]*\{[^}]*\}\s*(\w+)\s*;", text, re.S):
                index.setdefault(match.group(1), "struct")
    return index


NULLABILITY_WORDS = re.compile(r"\b(_Nullable|_Nonnull|__nullable|__nonnull|_Null_unspecified|nullable|nonnull|null_resettable|null_unspecified)\b")


PLATFORM_MACROS = re.compile(r"\b__[A-Z][A-Z0-9_]*(?:\([^()]*\))?")


def strip_nullability(decl):
    """A declaration without its nullability words and the platform macros the SDK puts after it (__TVOS_PROHIBITED and the
    like): the stub compiles whether or not the header's audit and availability macros are in scope."""
    return " ".join(PLATFORM_MACROS.sub(" ", NULLABILITY_WORDS.sub(" ", decl)).split())


def resolve_kind(type_text, index, depth=0):
    """'void', 'object', 'scalar' or 'struct' for a declared type, through its typedefs."""
    text = " ".join(type_text.replace("*", " * ").split())
    if text in ("void",):
        return "void"
    if "*" in text or text in ("id", "instancetype") or re.search(r"<.*>", text):
        return "object"
    name = text.split()[-1] if text.split() else text
    if text in SCALAR_TYPES or name in SCALAR_TYPES:
        return "scalar"
    if name in index and depth < 6:
        target = index[name]
        if target == "struct" or target.startswith("struct"):
            return "struct"
        kind = resolve_kind(target, index, depth + 1)
        return kind
    if re.match(r"^(NS_ENUM|NS_OPTIONS|enum)\b", text) or name.startswith("NS") and name.endswith("Options"):
        return "scalar"
    return "struct"


HAND_MEMO = {}


def hand_implementations(tree):
    """(class, selector) for every method a hand-written source of the package defines, and (class, name) for every
    @synthesize or @dynamic, so no stub replaces a hand implementation. A signature spans lines until its brace."""
    if tree in HAND_MEMO:
        return HAND_MEMO[tree]
    found = set()
    root = os.path.join(tree, SOURCES_ROOT)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".gen", "spec", "registry", "facts", "overrides", "gen")]
        for name in filenames:
            if not name.endswith((".m", ".mm")):
                continue
            current, signature = None, None
            for line in read_any(os.path.join(dirpath, name)).splitlines():
                if signature is not None:
                    signature += " " + line.strip()
                    if "{" in line or ";" in line:
                        sel = selector_of(signature.split("{")[0].split(";")[0])
                        if sel:
                            found.add((current, sel))
                        signature = None
                    continue
                impl = re.match(r"^\s*@implementation\s+(\w+)", line)
                if impl:
                    current = impl.group(1)
                    continue
                if re.match(r"^\s*@end\b", line):
                    current = None
                    continue
                if current is None:
                    continue
                synth = re.match(r"^\s*@(?:synthesize|dynamic)\s+(\w+)", line)
                if synth:
                    found.add((current, synth.group(1)))
                if re.match(r"^\s*[-+]\s*\(", line):
                    if "{" in line or ";" in line:
                        sel = selector_of(line.split("{")[0].split(";")[0])
                        if sel:
                            found.add((current, sel))
                    else:
                        signature = line.strip()
    HAND_MEMO[tree] = found
    return found


UNDECLARED_CHECK = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")
BUILTIN_TYPES = {"BOOL", "NSInteger", "NSUInteger", "CGFloat", "NSTimeInterval", "NSError", "NSString", "NSNumber", "NSArray",
                 "NSDictionary", "NSSet", "NSData", "NSURL", "NSDate", "NSUUID", "NSLocale", "NSMapTable", "NSPointerArray",
                 "NSMeasurement", "NSIndexPath", "NSProgress", "NSOperationQueue", "NSNotificationName", "NSNotificationCenter",
                 "NSOrderedSet", "NSCountedSet", "NSFileHandle", "NSBundle", "NSLayoutConstraint", "NSRange", "UInt32", "SInt32",
                 "OSStatus", "Float32", "Float64", "Boolean", "AudioObjectID", "AudioStreamBasicDescription", "AudioBufferList",
                 "AudioChannelLayout", "AudioComponentDescription", "AudioUnit", "AudioBuffer", "AudioUnitParameterID",
                 "AudioUnitParameterValue", "AudioTimeStamp", "CFStringRef", "CFTypeRef", "CFURLRef", "CMTime", "CGPoint", "CGSize",
                 "CGRect", "CFTimeInterval", "MIDIEndpointRef", "MIDIClientRef"}


def stub_members(spec, fw, sdk, overridden, hand, release_missing=None):
    """The stubs for one framework, one per member it does not implement, grouped by class; and the members left out with the reason.

    release_missing: the (kind, api) rows the 6.1.3 ledger lists. A member the release already has is answered by the release,
    so it gets no stub; with no ledger every declared member is considered (the pilot's first form)."""
    index = type_index(sdk, fw)
    declared = declared_names(sdk, fw)
    seen = set()
    by_class, skipped = {}, []
    for r in spec:
        if r["kind"] not in ("method", "property"):
            continue
        cls = r["cls"]
        decl = r["decl"].rstrip(";").strip()
        if release_missing is not None:
            ledger_api = r["api"] if r["kind"] == "method" else "%s.%s" % (cls, r["api"].rstrip("]").split()[-1])
            if (r["kind"], ledger_api) not in release_missing:
                skipped.append((r["api"], "implemented at 6.1.3: the release answers"))
                continue
        undeclared = sorted(set(t for t in UNDECLARED_CHECK.findall(strip_nullability(decl))
                                if t not in declared and t not in BUILTIN_TYPES and not t.startswith(("NS_", "API_", "CF_"))))
        if undeclared:
            skipped.append((r["api"], "type not declared for iOS: " + ",".join(undeclared)))
            continue
        if r["kind"] == "property":
            name = r["api"].rstrip("]").split()[-1]
            selector = getter_of(decl, name)
            if r["api"] in overridden or (cls, name) in hand or (cls, selector) in hand:
                skipped.append((r["api"], "override or hand implementation"))
                continue
            decl = strip_nullability(decl)
            type_text = property_type_text(decl, name)
            kind = resolve_kind(type_text, index)
            readwrite = "readonly" not in decl
            if (cls, selector) in seen:
                skipped.append((r["api"], "same selector declared twice in the class"))
                continue
            seen.add((cls, selector))
            by_class.setdefault(cls, []).append(("-[%s %s]" % (cls, selector), "property-get", selector, type_text, kind, decl))
            setter = "set%s%s:" % (name[:1].upper(), name[1:])
            if readwrite and (cls, setter) not in hand and "-[%s %s]" % (cls, setter) not in overridden:
                by_class[cls].append(("-[%s %s]" % (cls, setter), "property-set", setter, type_text, "void", decl))
            continue
        selector = r["api"].rstrip("]").split(" ", 1)[1]
        if r["api"] in overridden or (cls, selector) in hand:
            skipped.append((r["api"], "override or hand implementation"))
            continue
        decl = strip_nullability(decl)
        ret = re.match(r"^[-+]\s*\(\s*([^)]*?)\s*\)", decl)
        if not ret:
            skipped.append((r["api"], "no return type parsed"))
            continue
        if (cls, selector) in seen:
            skipped.append((r["api"], "same selector declared twice in the class"))
            continue
        seen.add((cls, selector))
        kind = resolve_kind(ret.group(1), index)
        by_class.setdefault(cls, []).append((r["api"], "method", selector, ret.group(1), kind, decl))
    return by_class, skipped


def property_type_text(decl, name):
    text = re.sub(r"\([^()]*\)", " ", decl.replace("@property", " "))
    text = re.sub(r"\b(_Nullable|_Nonnull|__nullable|__nonnull|_Null_unspecified|nullable|nonnull|null_resettable)\b", " ", text)
    text = " ".join(text.rstrip(";").split())
    return " ".join(text[:text.rfind(name)].split()) if name in text else text



def getter_of(decl, name):
    found = re.search(r"getter\s*=\s*(\w+)", decl)
    return found.group(1) if found else name


# ---------------------------------------------------------------- doc: the worker's page set (untracked, regenerated)

LEDGER_DIR = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "coordination", "corpus")
DOC_OUT = ".agent-work/spec-docs"
GEN_INPUT_LOG = ".agent-work/gen-input-all.txt"


def ledger_status(fw, release_dir):
    """(kind, api) -> status for the framework's rows the ledger lists; a row it does not list is implemented in that release."""
    path = os.path.join(LEDGER_DIR, release_dir, fw + ".tsv")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if row.get("kind") and row.get("api"):
                out[(row["kind"], row["api"])] = row["status"]
    return out


SURFACE_MEMO = {}


def surface_rows(fw):
    """(kind, api) -> the surface row (demand, impl-lead, deprecation) for one framework. The table is read once per process."""
    if "rows" not in SURFACE_MEMO:
        rows = {}
        with open(os.path.join(LEDGER_DIR, "sdk-26.2-surface.tsv"), newline="") as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                rows.setdefault(row["framework"], {})[(row["kind"], row["api"])] = row
        SURFACE_MEMO["rows"] = rows
    return SURFACE_MEMO["rows"].get(fw, {})


def oracle_defaults(fw):
    """class -> [(item, value_kind, value, build)] from the host oracle capture in v-cache26's table."""
    path = os.path.join(LEDGER_DIR, "cache-26.2", "oracle-defaults.tsv")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, newline="", errors="replace") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            if row.get("framework") == fw:
                out.setdefault(row["class"], []).append((row["item"], row["value_kind"], row["value"], row["build"]))
    return out


def registry_entries(tree, fw):
    """api -> (registry file, entry) for every registry row of the framework, whatever its status."""
    out = {}
    for path in sorted(glob.glob(os.path.join(tree, REGISTRY, fw, "*.json")) + glob.glob(os.path.join(tree, REGISTRY, fw + ".json"))):
        with open(path) as handle:
            data = json.load(handle)
        for entry in (data.get("entries", []) if isinstance(data, dict) else data):
            # keyed as the spec and the surface key a member: a property written 'Class.name' is '-[Class name]'
            out.setdefault(canonical_member(entry["api"], entry.get("kind", "method")), (os.path.relpath(path, tree), entry))
    return out


def header_comment(header, cls, decl, kind, selector_or_name):
    """The comment the header writes above a member of one class, or '' when it writes none."""
    block = re.search(r"@interface\s+" + re.escape(cls) + r"\b(.*?)@end", header, re.S)
    if not block:
        return ""
    body = block.group(1)
    key = selector_or_name.split(":")[0] if kind == "method" else selector_or_name
    found = re.search(r"(?m)^[^\n]*\b" + re.escape(key) + r"\b[^\n]*$", body)
    if not found:
        return ""
    before = body[:found.start()].rstrip().split("\n")
    lines = []
    for line in reversed(before):
        stripped = line.strip()
        if re.match(r"^(///|/\*\*|/\*!|\*|//|\*/)", stripped) or stripped.endswith("*/"):
            lines.insert(0, stripped)
        else:
            break
    text = " ".join(re.sub(r"^(///|/\*\*|/\*!|\*/|\*|//)\s?", "", l).rstrip("*/").strip() for l in lines)
    return " ".join(text.split())[:600].encode("ascii", "replace").decode("ascii")


def md_cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")[:400]


def cmd_doc(args):
    fws = frameworks_with_snapshot(args.tree) if args.all else [args.framework]
    out_root = args.out or os.path.join(args.tree, DOC_OUT)
    sdk = args.sdk or SDK26
    for fw in fws:
        spec = load_spec(args.tree, fw)
        header = strip_platform_blocks(header_text(sdk, fw))
        supers = dict(re.findall(r"@interface\s+(\w+)\s*:\s*(\w+)", header))
        led = ledger_status(fw, "ledger-w45")
        led43 = ledger_status(fw, "ledger-w45-4.3")
        surf = surface_rows(fw)
        regs = registry_entries(args.tree, fw)
        pins = {p["api"]: p for p in load_pins(args.tree, fw)}
        oracle = oracle_defaults(fw)
        facts = objc_facts(args.tree, fw)
        classes_meta = {row["owner"]: row for key, row in facts.items() if key[0] == "class"}
        stubs_skipped = {}
        if os.path.exists(os.path.join(gen_dir(args.tree, fw), "trace", "skipped.tsv")):
            for row in csv.DictReader(open(os.path.join(gen_dir(args.tree, fw), "trace", "skipped.tsv")), delimiter="\t"):
                stubs_skipped[row["api"]] = row["reason"]
        out = os.path.join(out_root, fw)
        os.makedirs(out, exist_ok=True)
        classes = {}
        for r in spec:
            if r["kind"] in ("method", "property"):
                classes.setdefault(r["cls"], []).append(r)
        index = [
            "# %s: worker page set" % fw, "",
            "Regenerated by `tools/gen.py doc %s` from the committed snapshot, the ledgers and the surface table. Do not edit: regenerate." % fw, "",
            "- Spec: the 26.2 header of %s, as recorded in `spec/%s/` (%d method and property rows, %d constant rows)." % (
                fw, fw, sum(1 for r in spec if r["kind"] in ("method", "property")), sum(1 for r in spec if r["kind"] == "constant")),
            "- Status at 6.1.3: ledger-w45. A member the ledger does not list is implemented in that release. Status at 4.3: ledger-w45-4.3.",
            "- Demand and impl-lead: sdk-26.2-surface.tsv. Overrides and pins: `registry/%s/` and `overrides/hashes/%s.tsv`." % (fw, fw),
            "- Behaviour summaries (what a method calls, its strings, constants and error domains): not produced in this run; see the report.",
            "- REFERENCE ONLY: nothing here is Apple binary, disassembly or pseudocode, and none of it is sent to an external service.", "",
            "## Classes (%d)" % len(classes), "",
            "| class | superclass | members | overridden | stub | page |", "| --- | --- | --- | --- | --- | --- |",
        ]
        constant_rows = [r for r in spec if r["kind"] == "constant"]
        for cls in sorted(classes):
            members = classes[cls]
            overridden = sum(1 for r in members if r["api"] in regs)
            stubbed = sum(1 for r in members if r["api"] not in regs and r["api"] not in stubs_skipped)
            index.append("| %s | %s | %d | %d | %d | [%s.md](%s.md) |" % (cls, supers.get(cls, "-"), len(members), overridden, stubbed, cls, cls))
        protocols = load_protocols(args.tree, fw)
        if protocols:
            index += ["", "## Protocols (%d)" % len(protocols), "", "| protocol | status | members | page |", "| --- | --- | --- | --- |"]
            for name in sorted(protocols):
                index.append("| %s | %s | %d | [%s.md](%s.md) |" % (name, protocols[name]["status"], len(protocols[name]["members"]), name, name))
        index += ["", "Constants: [Constants.md](Constants.md) (%d rows)." % len(constant_rows), ""]
        write(os.path.join(out, "index.md"), "\n".join(index) + "\n")
        for cls in sorted(classes):
            page = ["# %s (%s)" % (cls, fw), "",
                    "Superclass: %s. Status at 6.1.3 and 4.3 is per member below." % supers.get(cls, "-"), "",
                    "| kind | declaration (26.2 header, normalised) | availability | 6.1.3 | 4.3 | demand | impl-lead | ours (registry, pin) | stub |",
                    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
            notes = []
            for r in sorted(classes[cls], key=lambda x: (x["kind"], x["api"])):
                key_kind = "method" if r["kind"] == "method" else "property"
                ledger_key = (key_kind, r["api"])
                s6 = led.get(ledger_key, "implemented")
                s43 = led43.get(ledger_key, "implemented")
                srow = surf.get(ledger_key, {})
                demand = ("rank %s, %s, %s apps" % (srow.get("demand-rank") or "-", srow.get("demand-severity") or "-",
                                                    srow.get("demand-apps") or "-")) if srow.get("demand-rank") else "-"
                ours = "-"
                if r["api"] in regs:
                    path, entry = regs[r["api"]]
                    pin = pins.get(r["api"])
                    ours = "%s: %s%s" % (entry.get("status", "?"), path, (", pin %s" % pin["pinned-by"]) if pin else "")
                stub = "hand/override" if r["api"] in regs else ("not stubbed: " + stubs_skipped[r["api"]] if r["api"] in stubs_skipped else "stub")
                page.append("| %s | `%s` | %s | %s | %s | %s | %s | %s | %s |" % (
                    r["kind"], md_cell(r["decl"]), md_cell(r["availability"] if r["availability"] != "-" else "-"), s6, s43, demand,
                    md_cell(srow.get("impl-lead") or "-"), md_cell(ours), md_cell(stub)))
                comment = header_comment(header, cls, r["decl"], r["kind"], (r["api"].rstrip("]").split(" ", 1)[1] if r["kind"] == "method" else r["api"].split(".")[-1]))
                if comment:
                    notes.append("- `%s`: %s" % (r["api"], comment))
            page += ["", "## Header comments", ""] + (notes or ["- none in the header"])
            if cls in oracle:
                page += ["", "## Host oracle (macOS, class state and defaults; v-cache26 capture)", "", "| item | kind | value | build |", "| --- | --- | --- | --- |"]
                page += ["| %s | %s | %s | %s |" % tuple(md_cell(x) for x in row) for row in oracle[cls][:60]]
            meta = classes_meta.get(cls)
            page += ["", "## Runtime metadata (26.2 binary, v-cache26 ObjC table; REFERENCE ONLY: the encodings give the binary's argument",
                     "and return types, not what a method does)", ""]
            if meta:
                page.append("Superclass in the binary: %s. Protocols: %s." % (meta["superclass"] or "-", meta["protocols"] or "-"))
            else:
                page.append("No class row for this class in the binary's ObjC table.")
            page += ["", "| member | binary type encoding | binary address |", "| --- | --- | --- |"]
            for r in sorted(classes[cls], key=lambda x: (x["kind"], x["api"])):
                if r["kind"] == "method":
                    key = ("method", cls, "instance" if r["api"].startswith("-") else "class", r["api"].rstrip("]").split(" ", 1)[1])
                else:
                    key = ("property", cls, "instance", r["api"].rstrip("]").split(" ")[-1])
                row = facts.get(key)
                page.append("| `%s` | %s | %s |" % (md_cell(r["api"]), md_cell(row["types"]) if row else "not in the table",
                                                  row["address"] if row else "-"))
            page += ["", "## Behaviour summary", "", "The disassembly summary (calls in order, strings, constants, error domains) is not produced: "
                     "it needs a cache path the coordinator has not granted (see the report).", ""]
            write(os.path.join(out, cls + ".md"), "\n".join(page) + "\n")
        for name in sorted(protocols):
            record = protocols[name]
            members = sorted(record["members"], key=lambda m: (m["section"], m["kind"], m["selector"]))
            page = ["# %s (%s, protocol)" % (name, fw), "",
                    "Status in the transcriber's facts: %s. Introduced %s. Bases: %s." % (
                        record["status"], record["introduced"], record["bases"] or "NSObject"), "",
                    "Reasons from the transcriber: %s." % (record["reasons"] or "none"), "",
                    "A protocol member has no stub: its implementation is the conforming class's, and a class row of the surface is"
                    " stubbed where the release lacks it. The declaration is the transcriber's rendering of the 26.2 AST.", "",
                    "| section | kind | declaration (26.2 AST, transcriber rendering) | in 16.4 body | 6.1.3 | demand | ours |",
                    "| --- | --- | --- | --- | --- | --- | --- |"]
            notes = []
            for member in members:
                api = "-[%s %s]" % (name, member["selector"])
                key = (member["kind"], api)
                srow = surf.get(key, {})
                demand = ("rank %s, %s apps" % (srow.get("demand-rank"), srow.get("demand-apps") or "-")) if srow.get("demand-rank") else "-"
                ours = "hand/registry" if api in regs else "-"
                page.append("| %s | %s | `%s` | %s | %s | %s | %s |" % (
                    member["section"], member["kind"], md_cell(member["decl"]), member["in16"], led.get(key, "implemented"),
                    demand, ours))
                comment = header_comment(header, name, member["decl"], member["kind"], member["selector"])
                if comment:
                    notes.append("- `%s`: %s" % (api, comment))
            page += ["", "## Header comments", ""] + (notes or ["- none in the header"])
            page += ["", "## Behaviour summary", "", "not produced in this run (see the report)."]
            write(os.path.join(out, name + ".md"), "\n".join(page) + "\n")
        constants = ["# %s constants" % fw, "", "| name | declaration | iOS 26.2 value | host value | 6.1.3 | 4.3 | ours |", "| --- | --- | --- | --- | --- | --- | --- |"]
        for r in sorted(constant_rows, key=lambda x: x["api"]):
            s6 = led.get(("constant", r["api"]), "implemented")
            s43 = led43.get(("constant", r["api"]), "implemented")
            constants.append("| %s | `%s` | %s | %s | %s | %s | %s |" % (
                r["api"], md_cell(r["decl"]), md_cell(r["value"] if r["value_status"] == "found" else r["value_status"]),
                md_cell(r["host_value"] if r["host_value"] != "-" else "-"), s6, s43,
                md_cell(r["owned"] if r["owned"] != "-" else ("generated" if r["value_status"] == "found" else r["value_status"]))))
        write(os.path.join(out, "Constants.md"), "\n".join(constants) + "\n")
        swift_rows = swift_bucket(args.tree).get(fw, [])
        if swift_rows:
            page = ["# %s: Swift rows (%d)" % (fw, len(swift_rows)), "",
                    "Rows of the surface in Swift, which the ObjC headers do not describe. The table describes name, kind and availability;"
                    " it has no types, so no signature is shown. Overlay needs: see the list at the end.", "",
                    "| kind | Swift name | introduced | unavailable | table match | demand | impl-lead |", "| --- | --- | --- | --- | --- | --- | --- |"]
            for row in sorted(swift_rows, key=lambda r: (r["kind"], r["api"])):
                page.append("| %s | `%s` | %s | %s | %s | %s | %s |" % (
                    row["kind"], md_cell(row["api"]), row["introduced"], md_cell(row["unavailable"]), row["table_match"],
                    md_cell(row["demand_rank"]), md_cell(row["impl_lead"])))
            page += ["", "## What a Swift overlay build needs that the project does not have", ""] + ["- " + need for need in SWIFT_OVERLAY_NEEDS]
            write(os.path.join(out, "Swift.md"), "\n".join(page) + "\n")
        print("doc %s: %d class pages, constants page, index -> %s" % (fw, len(classes), os.path.relpath(out, args.tree)))
    return 0


# ---------------------------------------------------------------- scope: every surface row, counted from the tables

SCOPE_DIR = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "coordination", "wave-2026-10-03")
SCOPE_KINDS = ("class", "method", "property", "constant", "function", "enum", "struct", "typealias", "protocol")


def protocol_member_state(owner, api, proto):
    """The state of a member of an objc protocol, by the transcriber's facts for its protocol: in the 16.4 body the lifted
    protocol object is built from, in a transcribed header, declared by a hand header, or a gap (26.2 only, or no facts)."""
    record = (proto or {}).get(owner)
    if record is None:
        return "protocol member: protocol not in the transcriber's facts"
    canon = canonical_member(api, "property" if "." in api and not api.startswith(("-[", "+[")) else "method")
    selector = re.sub(r"^[-+]\[%s |\]$" % re.escape(owner), "", canon)
    member = next((m for m in record["members"] if m["selector"] == selector), None)
    if record["status"] == "sdk16 body":
        if member is None:
            return "protocol member: not in the 26.2 facts (gap)"
        return ("protocol member: 26.2 only, the 16.4 body the protocol object is built from lacks it (gap)" if member["in16"] == "no"
                else "protocol member: in the 16.4 body (lifted protocol object)")
    if record["status"] == "transcribed":
        return "protocol member: in the transcribed protocol header" if member else "protocol member: not in the 26.2 facts (gap)"
    if record["status"] == "hand header":
        return "protocol member: declared by a hand header (no generator)"
    return "protocol member: its protocol is " + ("refused by the transcriber" if record["status"] == "refused" else "not in the 26.2 AST")


def header_facts(sdk, fw, spec):
    """(platform_only, names): the members the framework's 26.2 header declares on a branch the iOS build does not read (the parse
    of ios_text does not carry them), and every identifier the headers spell, comments removed."""
    full = {api for _, _, api, _, _, _ in members_of(header_text(sdk, fw))}
    ios = {r["api"] for r in spec if r["kind"] in ("method", "property")}
    text = re.sub(r"//[^\n]*|/\*.*?\*/", " ", header_text(sdk, fw), flags=re.S)
    return full - ios, set(re.findall(r"[A-Za-z_]\w*", text))


def parse_gap_reason(api, platform_only, names):
    """Why the header parse does not carry a surface member row, in the order the answer is decided: declared only on another
    platform's branch; a bare init, new or copy the headers do not spell (implicit from NSObject, or unavailable by a macro); a
    selector no header of the framework spells (another framework's header, or the runtime only); or a spelling the parse should
    have read, which is the parse gap."""
    if api in platform_only:
        return "not declared for iOS: declared only in another platform's branch"
    sel = api[api.index(" ") + 1:-1] if api.startswith(("-[", "+[")) else api.split(".", 1)[-1]
    name = sel.split(":")[0]
    if name in ("init", "new", "copy", "mutableCopy", "dealloc", "description"):
        return "init/new: not spelled by the 26.2 headers (implicit, or unavailable by a macro)"
    if name not in names:
        return "not spelled by this framework's 26.2 headers (another framework's header, or runtime only)"
    return "spelled by the headers, not parsed (parse gap)"


def canonical_member(api, kind):
    """The key a member row has in the trace layer's stub list: a property written 'Class.name' is '-[Class name]'."""
    if kind == "property" and not api.startswith(("-[", "+[")) and "." in api:
        return "-[%s %s]" % tuple(api.split(".", 1))
    return api


def scope_row_state(kind, api, registry, spec_by_api, stub_reason, in_missing=True, protocols=frozenset(), lang="objc",
                    header_only=False, proto=None, gaps=None, functions=None, stubs=None, class_decisions=None):
    """The one state a surface row is in, by the tables. A row the 6.1.3 release has is answered by the release, so only a
    missing row is a work item; a missing row is overridden, a stub, a hand implementation, a type iOS does not declare, a
    protocol member (the spec does not cover protocols), or a kind with no generator yet."""
    if canonical_member(api, kind) in registry:
        return "overridden"
    if not in_missing:
        return "implemented at 6.1.3: the release answers"
    if header_only:
        # the ledger's header-ok rows (lift): declared in the lifted headers, no symbol to generate
        return "header-only (lift): no symbol to generate"
    if lang == "swift":
        # the spec is the ObjC headers; a Swift row of any kind needs the Swift interface, which v-cache26 publishes beside the ObjC tables
        return "swift: needs the Swift interface source"
    if kind == "class":
        if class_decisions is None or api not in class_decisions:
            return "class object: not a candidate (no missing member rows in the header parse)"
        generated, why = class_decisions[api]
        if generated:
            return "class object: generated (trace layer; every member a stub)"
        if "own sources" in why or "override" in why:
            return "class object: hand code covers it (not generated)"
        return "class object: not generated (a member uncovered, or the superclass is not in the release)"
    if kind == "function" and lang == "objc":
        record = (functions or {}).get(api)
        if record is None:
            return "C function: not in the functions snapshot"
        return "C function: generable stub (trace layer)" if record["status"] == "generable" else "C function: " + record["reasons"]
    if kind == "protocol" and lang == "objc":
        record = (proto or {}).get(api)
        return PROTOCOL_STATES[record["status"]] if record else "protocol object: not in the transcriber's list"
    if kind not in ("method", "property", "constant"):
        return "needs a generator: " + kind
    if lang == "swift":
        # the spec is the ObjC headers; a Swift row needs the Swift interface, which v-cache26 publishes beside the ObjC tables
        return "swift: needs the Swift interface source"
    if kind in ("method", "property"):
        owner = re.search(r"^[-+]\[(\w+)", api) or re.search(r"^(\w+)\.", api)
        if owner and owner.group(1) in protocols:
            return protocol_member_state(owner.group(1), api, proto)
    r = spec_by_api.get(api)
    if kind in ("method", "property"):
        if r is None:
            return gaps(api) if gaps else "not in the header parse (category or other)"
        # one definition of generable: a stub in the trace layer's list answers the row (trace/stubs.tsv); the skip reasons
        # are only the explanation of a row no stub answers
        key = canonical_member(api, kind)
        if stubs is not None:
            reason = None if key in stubs else (stub_reason.get(key) or "not stubbed by the trace layer")
        else:
            reason = stub_reason.get(key)
        if reason is None:
            return "generable stub"
        if reason.startswith("type not declared for iOS"):
            return "not declared for iOS"
        if reason.startswith("override or hand implementation"):
            return "hand implementation (no registry row)"
        return "not stubbed: " + reason
    if r is None:
        return "not in the header parse (category or other)"
    if r["owned"] != "-":
        return "owned by a live branch" if not r["owned"].startswith("registry:") else "registry decision"
    if r["value_status"] == "found" and r["tbd"] == "exported":
        return "generable constant"
    if r["value_status"] == "numeric":
        return "numeric (not a string object)"
    return "not generated: " + (r["value_status"] if r["value_status"] else "-")


GENERABLE_STATES = {"generable stub", "C function: generable stub (trace layer)"}

# The open states the work queue lists, each with its kind of work and the next step. A state not here is decided or generated.
QUEUE_NEXT = [
    ("protocol member: 26.2 only", "protocol member added after the 16.4 body", "a registry decision: the protocol object is the 16.4 body, so the member needs a transcribed or hand body for it"),
    ("protocol member: not in the 26.2 facts", "protocol member with no 26.2 fact", "read the header by hand; the member's owner is not the protocol the surface names"),
    ("spelled by the headers, not parsed", "parse gap", "fix the parser for this declaration (see the scope reason)"),
    ("class object: not generated", "class object with uncovered members", "cover each listed member with a stub or a registry decision, or leave the class out"),
    ("C function: exported by the 26.2 .tbd", "C function exported without a declaration", "find its declaration in the SDK (no header declares it): a decision on the name"),
    ("not stubbed: not stubbed by the trace layer", "row with no stub and no skip reason", "should be empty: a stub-layer defect"),
    ("not spelled by this framework's 26.2 headers", "name not spelled by the framework's headers", "check the other framework headers (umbrella subframeworks) and the runtime; decide per row"),
    ("init/new: not spelled", "init or new not spelled by the headers", "decide per class: implicit from NSObject, or unavailable by a macro"),
    ("not in the header parse (category or other)", "not in the header parse", "read the header by hand"),
    ("swift: needs the Swift interface source", "Swift row", "declaration from the .swiftinterface text, then a decision on overlay (see the Swift page)"),
]


def queue_item(state):
    for prefix, kind, step in QUEUE_NEXT:
        if state.startswith(prefix):
            return kind, step
    return None


def cmd_scope(args):
    """The scope of the surface, from the tables: one row per framework and kind, and the work queue by demand."""
    sdk = args.sdk or SDK26
    surface = []
    with open(os.path.join(LEDGER_DIR, "sdk-26.2-surface.tsv"), newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            surface.append(row)
    by_fw = {}
    for row in surface:
        by_fw.setdefault(row["framework"], []).append(row)
    counts = {}
    generable = {}
    queue_items = []
    frameworks = surface_frameworks()
    for fw in frameworks:
        rows = by_fw.get(fw, [])
        led6 = ledger_status(fw, "ledger-w45") if os.path.exists(os.path.join(LEDGER_DIR, "ledger-w45", fw + ".tsv")) else {}
        led43 = ledger_status(fw, "ledger-w45-4.3") if os.path.exists(os.path.join(LEDGER_DIR, "ledger-w45-4.3", fw + ".tsv")) else {}
        snap = os.path.exists(spec_path(args.tree, fw))
        proto = load_protocols(args.tree, fw) if snap else None
        fns = load_functions(args.tree, fw) if snap else None
        cls_dec = load_class_decisions(args.tree, fw) if snap else None
        # the objc protocols only: a Swift protocol row with a class's name (CLCondition) is not a protocol the class's members belong to
        protocols = set(row["api"] for row in rows if row["kind"] == "protocol" and row.get("lang") == "objc")
        protocols |= set(proto or {})
        reg = registry_entries(args.tree, fw)
        registry = set(reg)
        spec_by_api, stub_reason = {}, {}
        if snap:
            spec = load_spec(args.tree, fw)
            for r in spec:
                spec_by_api.setdefault(r["api"], r)
                spec_by_api.setdefault(r["api"].replace("-[", "").rstrip("]").replace(" ", ".", 1) if r["kind"] == "property" else r["api"], r)
            overridden = registry
            if any(r["kind"] in ("method", "property") for r in spec):
                index_ok = True
                try:
                    release_missing = set(led6.keys()) if led6 else None
                    _, skipped = stub_members(spec, fw, sdk, overridden, hand_implementations(args.tree), release_missing)
                except Exception as error:  # a framework whose types cannot be resolved is named, not hidden
                    skipped, index_ok = [], False
                    stub_reason["__error__"] = str(error)[:100]
                stub_reason.update({api: reason for api, reason in skipped})
        trace_stubs = os.path.join(gen_dir(args.tree, fw), "trace", "stubs.tsv")
        stub_keys = {line.split("\t")[0] for line in read(trace_stubs).splitlines()[1:] if line} if os.path.exists(trace_stubs) else None
        header = {}

        def gap_of(api):
            if not header:
                header["facts"] = header_facts(sdk, fw, load_spec(args.tree, fw))
            return parse_gap_reason(api, *header["facts"])

        for row in rows:
            kind = row["kind"]
            if kind not in SCOPE_KINDS:
                continue
            api = row["api"]
            dotted = api
            key = (kind, api)
            in_missing = (kind, api) in led6
            header_only = led6.get((kind, api)) == "header-ok"
            state = scope_row_state(kind, api, registry, spec_by_api, stub_reason, in_missing, protocols, row.get("lang", "objc"),
                                    header_only, proto, gaps=gap_of if snap else None, functions=fns, stubs=stub_keys, class_decisions=cls_dec) if snap else "no snapshot"
            c = counts.setdefault((fw, kind), {"surface": 0, "demand_rows": 0, "demand_apps": 0, "missing_6_1_3": 0,
                                               "missing_4_3": 0, "states": {}})
            c["surface"] += 1
            if row.get("demand-rank"):
                c["demand_rows"] += 1
                c["demand_apps"] += int(row.get("demand-apps") or 0)
            if led6.get((kind, api)) is not None:
                c["missing_6_1_3"] += 1
            if led43.get((kind, api)) is not None:
                c["missing_4_3"] += 1
            c["states"][state] = c["states"].get(state, 0) + 1
            if state in GENERABLE_STATES:
                generable.setdefault(fw, set()).add(canonical_member(api, kind))
            item = queue_item(state)
            if item:
                queue_items.append((fw, kind, api, state, item[0], item[1], row.get("demand-rank") or "-", row.get("demand-apps") or "0"))
    # Reconciliation: the rows the scope calls generable against the stubs the trace layer writes (trace/stubs.tsv, one row per
    # stub, keyed by the surface row it answers). One set: a row is generable exactly when a stub answers it.
    reconcile, stubbed_total, generable_total, both = [], 0, 0, 0
    for fw in sorted(set(generable) | set(f for f, _ in counts)):
        trace = os.path.join(gen_dir(args.tree, fw), "trace", "stubs.tsv")
        stubs = set()
        if os.path.exists(trace):
            stubs = {row.split("\t")[0] for row in read(trace).splitlines()[1:] if row}
        gen_rows = generable.get(fw, set())
        stubbed_total += len(stubs)
        generable_total += len(gen_rows)
        both += len(stubs & gen_rows)
        for api in sorted(stubs - gen_rows):
            reconcile.append((fw, api, "trace stub that answers no surface row (spec-only member, or a class the surface does not list)"))
        for api in sorted(gen_rows - stubs):
            reconcile.append((fw, api, "surface row the scope calls generable with no trace stub (should be empty: one definition)"))
    write(os.path.join(SCOPE_DIR, "v-gen-reconcile.tsv"), ("framework\tapi\treason\n" + "".join(
        "%s\t%s\t%s\n" % row for row in reconcile)).encode("ascii", "backslashreplace").decode("ascii"))
    print("reconcile: %d generable rows, %d stubs, %d in both, %d differences -> v-gen-reconcile.tsv"
          % (generable_total, stubbed_total, both, len(reconcile)))
    lines = ["framework\tkind\tsurface_rows\tdemand_rows\tdemand_apps\tmissing_6_1_3\tmissing_4_3\tstates"]
    queue = {}
    for (fw, kind), c in sorted(counts.items()):
        states = "; ".join("%s=%d" % (k, v) for k, v in sorted(c["states"].items()))
        lines.append("\t".join([fw, kind, str(c["surface"]), str(c["demand_rows"]), str(c["demand_apps"]),
                                str(c["missing_6_1_3"]), str(c["missing_4_3"]), states]))
        queue[fw] = queue.get(fw, 0) + c["demand_apps"]
    os.makedirs(SCOPE_DIR, exist_ok=True)
    write(os.path.join(SCOPE_DIR, "v-gen-scope.tsv"), "\n".join(lines) + "\n")
    order = sorted(queue, key=lambda fw: (-queue[fw], fw))
    md = ["# v-gen scope: every surface row, counted from the tables", "",
          "Generated by `tools/gen.py scope` from sdk-26.2-surface.tsv, the ledgers (6.1.3 and 4.3), the registry, and the spec snapshots.",
          "", "Work queue by demand (apps that call the framework's rows, summed):", "",
          "| rank | framework | demand apps | surface rows |", "| --- | --- | --- | --- |"]
    surf_total = {}
    for (fw, kind), c in counts.items():
        surf_total[fw] = surf_total.get(fw, 0) + c["surface"]
    for i, fw in enumerate(order[:60], 1):
        md.append("| %d | %s | %d | %d |" % (i, fw, queue[fw], surf_total.get(fw, 0)))
    totals = {}
    for (fw, kind), c in counts.items():
        for state, n in c["states"].items():
            totals[state] = totals.get(state, 0) + n
    md += ["", "State totals over every surface row (each row has exactly one state):", "",
           "| state | rows |", "| --- | --- |"]
    md += ["| %s | %d |" % (state, n) for state, n in sorted(totals.items(), key=lambda kv: -kv[1])]
    surface_total = sum(len(v) for v in by_fw.values())
    # the work queue: every open row, by demand (demand rank first, then apps); swift rows are counted per framework, not listed
    queued = sorted(queue_items, key=lambda q: (q[6] == "-", int(q[6]) if q[6] != "-" else 0, -int(q[7] or 0), q[0], q[2]))
    write(os.path.join(SCOPE_DIR, "v-gen-queue.tsv"), ("framework\tkind\tapi\tstate\twork\tnext_step\tdemand_rank\tdemand_apps\n" + "".join(
        "\t".join([q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7]]) + "\n" for q in queued)).encode("ascii", "backslashreplace").decode("ascii"))
    for item in sorted({q[4] for q in queued}):
        print("queue: %6d  %s" % (sum(1 for q in queued if q[4] == item), item))
    tied = sum(totals.values())
    md += ["", "Tie-out: %d surface rows, %d rows in the state totals: %s." % (surface_total, tied,
                                                                             "tie" if tied == surface_total else "DO NOT TIE")]
    write(os.path.join(SCOPE_DIR, "v-gen-scope.md"), "\n".join(md) + "\n")
    print("tie-out: %d surface rows, %d in state totals" % (surface_total, tied))
    print("scope: %d framework-kind rows, %d frameworks -> %s" % (len(counts), len(queue), os.path.join(SCOPE_DIR, "v-gen-scope.tsv")))
    return 0


# ---------------------------------------------------------------- protocols: the 26.2 protocol objects the 6.1.3 release lacks

# A protocol is transcribed by tools/transcribe-protocols.py, the team's transcriber, with its own rules and refusals; this
# section only runs it, keeps what it reports as the snapshot (spec/<F>/protocols.tsv and the header it writes, when it writes
# one), and emits the protocol objects from the snapshot. The dumps are taken by `protocols`, not by every build.
PROTOCOL_TOOL = os.path.join("tools", "transcribe-protocols.py")
SDK16 = os.environ.get("CHARON_SDK16") or os.path.join(
    os.environ.get("HOME", ""), ".xmake", "packages", "i", "iphoneos-sdk", "16.4", "cccc080d0cbe42c2a85b1369aba6e290",
    "Developer.app", "Contents", "Developer", "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS16.4.sdk")
PROTOCOL_COLUMNS = ["protocol", "introduced", "status", "reasons", "bases", "section", "kind", "instance", "selector", "decl", "in16"]
PROTOCOL_STATES = {"sdk16 body": "protocol object: generated from the 16.4 body",
                   "transcribed": "protocol object: generated from the transcribed header",
                   "hand header": "protocol object: hand header (no generator)",
                   "refused": "protocol object: refused by the transcriber",
                   "missing": "protocol object: not in the 26.2 AST"}


def protocol_owners(tree, fw):
    """objc protocols that the framework's member rows name as their owner, which the header parse does not carry as a class and
    the header defines with a body (@protocol NAME, then its members). The surface lists a protocol row for only some of them; a
    delegate with no row of its own still has member rows, and the header parse reads classes only. name -> the earliest
    introduced release of its member rows."""
    rows = surface_rows(fw)
    classes = {r["cls"] for r in load_spec(tree, fw)} if os.path.exists(spec_path(tree, fw)) else set()
    introduced = {}
    for (kind, api), row in rows.items():
        if kind not in ("method", "property") or row["lang"] != "objc":
            continue
        m = re.search(r"^[-+]\[(\w+)", api) or re.search(r"^(\w+)\.", api)
        if m and m.group(1) not in classes:
            owner = m.group(1)
            if owner not in introduced or release_key(row["introduced"]) < release_key(introduced[owner]):
                introduced[owner] = row["introduced"]
    if not introduced:
        return {}
    text = re.sub(r"//[^\n]*|/\*.*?\*/", " ", header_text(SDK26, fw), flags=re.S)
    defined = set(re.findall(r"@protocol\s+(\w+)\s*(?:<[^;>]*>)?\s*(?=\n)", text))
    return {name: intro for name, intro in introduced.items() if name in defined}


def protocol_wanted(tree, fw):
    """(name, introduced) of each objc protocol the scope classifies: the surface's protocol rows and the protocol owners of its
    member rows. The facts are taken for all of them (a lifted, registry or missing protocol alike)."""
    wanted = {api: row["introduced"] for (kind, api), row in surface_rows(fw).items() if kind == "protocol" and row["lang"] == "objc"}
    for name, introduced in protocol_owners(tree, fw).items():
        wanted.setdefault(name, introduced)
    return sorted(wanted.items())


def ascii_text(path):
    """A transcriber header as the snapshot holds it: the transcriber's one em dash becomes a hyphen, and the text must be ASCII."""
    text = open(path, encoding="utf-8").read().replace("\u2014", "-")
    text.encode("ascii")
    return text


def protocols_tsv(facts):
    lines = ["\t".join(PROTOCOL_COLUMNS)]
    for record in sorted(facts, key=lambda r: r["name"]):
        bases = ",".join(record.get("bases", []))
        lines.append("\t".join([record["name"], record["introduced"], record["status"], "; ".join(record.get("reasons", [])),
                                bases, "-", "-", "-", "-", "-", "-"]))
        members16 = record.get("members16")
        for member in record.get("members", []):
            in16 = "-" if members16 is None else ("yes" if member["selector"] in members16 else "no")
            lines.append("\t".join([record["name"], record["introduced"], record["status"], "", bases, member["section"],
                                    member["kind"], "yes" if member["instance"] else "no", member["selector"],
                                    member["decl"].replace("\t", " "), in16]))
    return "\n".join(lines) + "\n"


def load_protocols(tree, fw):
    """protocol name -> its record from the snapshot, with its members; {} when the framework has no protocol snapshot."""
    path = os.path.join(snap_dir(tree, fw), "protocols.tsv")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="ascii", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            record = out.setdefault(row["protocol"], {"introduced": row["introduced"], "status": row["status"],
                                                      "reasons": row["reasons"], "bases": row["bases"], "members": []})
            if row["section"] != "-":
                record["members"].append({"section": row["section"], "kind": row["kind"], "instance": row["instance"] == "yes",
                                          "selector": row["selector"], "decl": row["decl"], "in16": row["in16"]})
    return out


def cmd_protocols(args):
    """Run the transcriber for the framework's objc protocols the 6.1.3 release lacks, and write the snapshot: protocols.tsv (what
    each protocol and each member is, from the 26.2 and 16.4 ASTs) and the header it writes. --all: every surface framework."""
    targets = surface_frameworks() if args.all else [args.framework]
    sdk = args.sdk or SDK26
    failed = 0
    for fw in targets:
        snap = snap_dir(args.tree, fw)
        wanted = protocol_wanted(args.tree, fw)
        if not os.path.exists(spec_path(args.tree, fw)):
            if wanted:
                print("protocols %s: %d wanted, no snapshot: not transcribed" % (fw, len(wanted)))
            continue
        for stale in glob.glob(os.path.join(snap, "Charon*Protocols.h")):
            os.remove(stale)
        if not wanted:
            if os.path.exists(os.path.join(snap, "protocols.tsv")):
                os.remove(os.path.join(snap, "protocols.tsv"))
            continue
        out = os.path.join(args.tree, ".agent-work", "runs", "protocols", fw)
        os.makedirs(out, exist_ok=True)
        facts_path = os.path.join(out, "facts.json")
        if os.path.exists(facts_path):
            os.remove(facts_path)
        cmd = [sys.executable, os.path.join(args.tree, PROTOCOL_TOOL), sdk, SDK16, args.tree, out] + [
            "%s:%s:%s" % (name, fw, introduced) for name, introduced in wanted]
        result = subprocess.run(cmd, env=dict(os.environ, CHARON_PROTOCOL_FACTS=facts_path), capture_output=True, text=True)
        if result.returncode != 0 or not os.path.exists(facts_path):
            print("protocols %s: the transcriber stopped: %s" % (fw, (result.stderr or result.stdout)[-300:].strip()))
            failed += 1
            continue
        with open(facts_path, encoding="utf-8") as handle:
            facts = json.load(handle)
        write(os.path.join(snap, "protocols.tsv"), protocols_tsv(facts))
        for path in glob.glob(os.path.join(out, "Charon*Protocols.h")):
            write(os.path.join(snap, os.path.basename(path)), ascii_text(path))
        counts = {}
        for record in facts:
            counts[record["status"]] = counts.get(record["status"], 0) + 1
        print("protocols %s: %s" % (fw, ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts))))
    return 1 if failed else 0


# ---------------------------------------------------------------- functions: the C functions the 6.1.3 release lacks

# A C function has no class to carry its stub, so the trace layer defines it at file scope; the shipping build defines none.
# The declaration is read from the iOS view of the framework's own headers (ios_text), every header of it, subfolders included
# (vImage), and the snapshot is spec/<F>/functions.tsv: one row per function the surface lists as missing at 6.1.3.
FUNCTION_COLUMNS = ["api", "introduced", "status", "reasons", "returns", "params", "decl"]
C_BASE_WORDS = {"void", "char", "short", "int", "long", "float", "double", "signed", "unsigned", "bool", "_Bool", "const",
                "volatile", "struct", "enum", "union", "id", "SEL", "Class", "BOOL", "IMP", "CGFloat", "NSInteger",
                "NSUInteger", "size_t", "instancetype"}


def function_wanted(tree, fw):
    """(api, introduced) of each objc C-function row the 6.1.3 ledger lists as missing (not header-ok) and no registry row names.
    The surface names a function 'Name()'."""
    led6 = ledger_status(fw, "ledger-w45")
    registry = set(registry_entries(tree, fw))
    return sorted((api, row["introduced"]) for (kind, api), row in surface_rows(fw).items()
                  if kind == "function" and row["lang"] == "objc" and api not in registry
                  and (kind, api) in led6 and led6[(kind, api)] != "header-ok")


def header_text_recursive(sdk, fw):
    base = os.path.join(sdk, "System", "Library", "Frameworks", fw + ".framework", "Headers")
    return "\n".join(read_any(p) for p in sorted(glob.glob(os.path.join(base, "**", "*.h"), recursive=True)))


def c_statements(text, name):
    """The statements that call NAME at their top level: from the ; or } before the name to the ; or { that ends it. A name on a
    preprocessor line (a macro definition) is not a declaration."""
    out = []
    for match in re.finditer(r"(?<![\w.>])%s\s*\(" % re.escape(name), text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        if text[line_start:match.start()].lstrip().startswith("#"):
            continue
        start = max(text.rfind(";", 0, match.start()), text.rfind("}", 0, match.start()), text.rfind("@end", 0, match.start()) + 3) + 1
        depth, end = 1, match.end()
        while end < len(text) and depth:
            depth += {"(": 1, ")": -1}.get(text[end], 0)
            end += 1
        while end < len(text) and text[end] not in ";{":
            end += 1
        out.append(re.sub(r"(?m)^\s*#.*$", " ", text[start:end]))
    return out


def split_top_level(body):
    out, depth, current = [], 0, ""
    for ch in body:
        if ch == "," and depth == 0:
            out.append(current.strip())
            current = ""
            continue
        depth += {"(": 1, ")": -1}.get(ch, 0)
        current += ch
    if current.strip():
        out.append(current.strip())
    return out


def named_param(text, index):
    """A parameter with its name: the header's own, or pN where the header leaves it unnamed (a block's or a function pointer's
    name goes inside its parentheses)."""
    if "(^)" in text or "(*)" in text:
        return text.replace("(^)", "(^p%d)" % index, 1).replace("(*)", "(*p%d)" % index, 1)
    words = re.findall(r"[A-Za-z_]\w*", text)
    if len(words) >= 2 and not text.endswith("*") and words[-1] not in C_BASE_WORDS:
        return text
    return text + ("p%d" % index if text.endswith("*") else " p%d" % index)


def c_declaration(statement, name):
    """(returns, params, introduced, decl) of a C function declaration read from its statement, or None when it does not read as
    one. The availability macro gives the iOS introduced release; the statement's macros and nullability words are not kept."""
    clean, avail = strip_macros(statement)
    clean = strip_nullability(clean)
    # the linkage words a framework puts before a function (CT_EXPORT, CF_EXPORT, CG_EXTERN) are not part of its type
    clean = " ".join(re.sub(r"\b[A-Z][A-Z0-9]*_(?:EXPORT|EXTERN|EXPORTED|INLINE)\b|\bextern\b|\bstatic\b|\binline\b", " ", clean).split())
    found = re.search(r"(?<![\w.>])%s\s*\(" % re.escape(name), clean)
    if not found or clean.startswith(("typedef", "return", "#")):
        return None
    idx = found.start()
    returns = clean[:idx].strip()
    if not returns or "=" in returns:
        return None
    start, depth, end = found.end(), 1, found.end()
    while end < len(clean) and depth:
        depth += {"(": 1, ")": -1}.get(clean[end], 0)
        end += 1
    if depth:
        return None
    body = clean[start:end - 1].strip()
    raw = [] if body in ("", "void") else split_top_level(body)
    params = [named_param(p, i) for i, p in enumerate(raw)]
    introduced = re.search(r"ios\((\d+(?:\.\d+)*)", avail)
    return returns, params, introduced.group(1) if introduced else "-", "%s %s(%s)" % (returns, name, ", ".join(params))


def cmd_functions(args):
    """The C-function snapshot of each framework: spec/<F>/functions.tsv, from the iOS view of its headers. A function no header
    of the framework declares, or whose declaration does not read, is a row with its reason."""
    targets = surface_frameworks() if args.all else [args.framework]
    sdk = args.sdk or SDK26
    for fw in targets:
        if not os.path.exists(spec_path(args.tree, fw)):
            continue
        path = os.path.join(snap_dir(args.tree, fw), "functions.tsv")
        wanted = function_wanted(args.tree, fw)
        if not wanted:
            if os.path.exists(path):
                os.remove(path)
            continue
        text = re.sub(r"//[^\n]*|/\*.*?\*/", " ", ios_text(header_text_recursive(sdk, fw))[0], flags=re.S)
        exported, _ = tbd_exports(sdk, fw)
        lines = ["\t".join(FUNCTION_COLUMNS)]
        counts = {}
        for api, introduced in wanted:
            name = api[:-2] if api.endswith("()") else api
            declarations = [d for d in (c_declaration(s, name) for s in c_statements(text, name)) if d]
            if not c_statements(text, name):
                status = "missing"
                reasons = ("exported by the 26.2 .tbd, with no declaration in the framework's headers" if name in exported
                           else "not declared in the framework's 26.2 headers and not exported by it")
                row = ["-", "-", "-"]
            elif not declarations:
                status, reasons, row = "refused", "the declaration does not read as a C function", ["-", "-", "-"]
            else:
                returns, params, found, decl = declarations[0]
                status, reasons, row = "generable", "", [returns, "; ".join(params), decl]
                introduced = found if found != "-" else introduced
            counts[status] = counts.get(status, 0) + 1
            lines.append("\t".join([name, introduced, status, reasons] + row).replace("\n", " "))
        write(path, "\n".join(lines) + "\n")
        print("functions %s: %s" % (fw, ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts))))
    return 0


def load_class_decisions(tree, fw):
    """class -> (generated, reason) from the trace layer's classes.tsv; {} when the trace has not run for the framework."""
    path = os.path.join(gen_dir(tree, fw), "trace", "classes.tsv")
    out = {}
    if os.path.exists(path):
        for row in csv.DictReader(open(path, encoding="ascii", newline=""), delimiter="\t", quoting=csv.QUOTE_NONE):
            out[row["class"]] = (row["generated"] == "yes", row["reason"])
    return out


def load_functions(tree, fw):
    path = os.path.join(snap_dir(tree, fw), "functions.tsv")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="ascii", newline="") as handle:
        return {row["api"] + "()": row for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE)}


# ---------------------------------------------------------------- behaviour facts: the 26.2 binary's ObjC metadata (v-cache26)

# v-cache26 publishes the Objective-C metadata of the 26.2 cache as objc-26.2.tsv.gz: one row per class, method, property, ivar,
# protocol and category, with the runtime's type encoding and the implementation address. A doc page reads the rows of its
# framework from a per-framework extract, written once here (the table is 110 MB compressed). These are facts about the binary,
# REFERENCE ONLY: they say what a method's arguments and return are, not what it does.
OBJC_TABLE = os.path.join(LEDGER_DIR, "cache-26.2", "objc-26.2.tsv.gz")
OBJC_EXTRACT = os.path.join(".agent-work", "objc-26.2")
OBJC_ENTITIES = ("class", "method", "property")


def cmd_objc_extract(args):
    """Write one extract per framework of the table's class, method and property rows (fields: entity, owner, section (instance or
    class), name, decl, types, address, superclass, protocols, category)."""
    out_dir = os.path.join(args.tree, OBJC_EXTRACT)
    os.makedirs(out_dir, exist_ok=True)
    handles, counts = {}, {}
    with gzip.open(OBJC_TABLE, "rt", encoding="utf-8", errors="replace") as table:
        header = table.readline().rstrip("\n").split("\t")
        col = {name: i for i, name in enumerate(header)}
        for line in table:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < len(header) or fields[col["entity"]] not in OBJC_ENTITIES:
                continue
            image = fields[col["image"]]
            folder = os.path.basename(os.path.dirname(image))
            fw = folder[:-len(".framework")] if folder.endswith(".framework") else os.path.basename(image)
            if fw not in handles:
                handles[fw] = open(os.path.join(out_dir, fw + ".tsv"), "w", encoding="ascii", errors="replace")
                handles[fw].write("entity\towner\tsection\tname\tdecl\ttypes\taddress\tsuperclass\tprotocols\tcategory\n")
                counts[fw] = 0
            keep = ["entity", "owner", "section", "name", "decl", "types", "address", "superclass", "protocols", "category"]
            handles[fw].write("\t".join(fields[col[k]].replace("\t", " ").replace("\n", " ") if k in col and col[k] < len(fields)
                                     else "" for k in keep) + "\n")
            counts[fw] += 1
    for handle in handles.values():
        handle.close()
    print("objc extract: %d frameworks, %d rows -> %s" % (len(counts), sum(counts.values()), out_dir))
    return 0


def objc_facts(tree, fw):
    """(entity, owner, section, name) -> the extract row for one framework; {} when the extract is not there."""
    path = os.path.join(tree, OBJC_EXTRACT, fw + ".tsv")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="ascii", errors="replace", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            key = (row["entity"], row["owner"], row["section"], row["name"])
            out.setdefault(key, row)
    return out


# ---------------------------------------------------------------- Swift: the rows the ObjC headers cannot describe

# The surface's Swift rows are the bucket the scope names 'swift: needs the Swift interface source'. v-cache26's Swift interface
# table (swiftinterface-26.2.tsv: module, kind, qualified name, introduced and deprecation, unavailability, via) describes each
# one as far as a table can: its name, kind and availability. It has no types, so no signature is written from it. The facts go
# to .gen/swift/bucket.tsv (derived: the build directory, not the snapshot), one row per bucket row, and a doc page per framework.
SWIFT_TABLE = os.path.join(LEDGER_DIR, "cache-26.2", "swiftinterface-26.2.tsv")
SWIFT_BUCKET = os.path.join("swift", "bucket.tsv")
SWIFT_COLUMNS = ["framework", "kind", "api", "introduced", "unavailable", "via", "table_match", "table_kind", "table_introduced",
                 "table_unavailable", "demand_rank", "demand_apps", "impl_lead", "state"]


def surface_by_framework():
    """framework -> {(kind, api): row}, read from the surface table once."""
    out = {}
    with open(os.path.join(LEDGER_DIR, "sdk-26.2-surface.tsv"), newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            out.setdefault(row["framework"], {})[(row["kind"], row["api"])] = row
    return out


SWIFT_OVERLAY_NEEDS = [
    "Declarations with types: the 26.2 .swiftinterface text of each module (241 files in the SDK). No table in v-cache26 carries types.",
    "A Swift compiler that targets armv7 for iOS 6.1.3: the local swiftc (6.4) rejects `armv7-apple-ios6.1.3` (minimum iOS 7.0).",
    "The Swift runtime on iOS 6.1.3 (libswiftCore and the rest): none of the 574 armv7 images of the 6.1.3 cache read is a Swift image.",
    "A mapping from each Swift name to its mangled symbol: swift-26.2.tsv has names, kinds and members, not symbols.",
    "Signatures of generic, async, throwing, protocol-constrained and property-wrapper rows: no table carries them.",
    "Whether an armv7 Swift module or runtime loads on iOS 6.1.3: only a device run can show it.",
]
SWIFT_MEMO = {}


def swift_bucket(tree):
    """framework -> the bucket rows of .gen/swift/bucket.tsv, read once per run; {} when the file is not generated yet."""
    if "rows" not in SWIFT_MEMO:
        rows = {}
        path = os.path.join(tree, OUT_ROOT, SWIFT_BUCKET)
        if os.path.exists(path):
            with open(path, encoding="ascii", newline="") as handle:
                for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
                    rows.setdefault(row["framework"], []).append(row)
        SWIFT_MEMO["rows"] = rows
    return SWIFT_MEMO["rows"]


def swift_bucket_rows(tree, surface):
    """The surface's Swift rows the scope puts in the bucket: method, property and constant rows, lang swift, missing at 6.1.3
    (not header-ok), and named by no registry row."""
    out = []
    for fw in sorted(surface):
        if not os.path.exists(os.path.join(LEDGER_DIR, "ledger-w45", fw + ".tsv")):
            continue
        led6 = ledger_status(fw, "ledger-w45")
        registry = set(registry_entries(tree, fw))
        for (kind, api), row in surface[fw].items():
            if row["lang"] == "swift" and kind in ("method", "property", "constant") and api not in registry \
                    and (kind, api) in led6 and led6[(kind, api)] != "header-ok":
                out.append((fw, kind, api, row))
    return out


def cmd_swift(args):
    """Write .gen/swift/bucket.tsv: each Swift bucket row with what the Swift interface table says of it. Nothing is written from
    the table beyond name, kind and availability."""
    table = {}
    with open(SWIFT_TABLE, newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            table.setdefault((row["module"], row["api"]), []).append(row)
    surface = surface_by_framework()
    rows = swift_bucket_rows(args.tree, surface)
    lines = ["\t".join(SWIFT_COLUMNS)]
    matched = {}
    for fw, kind, api, row in rows:
        found = table.get((fw, api), [])
        match = found[0] if found else None
        matched[fw] = matched.get(fw, 0) + (1 if match else 0)
        lines.append("\t".join([fw, kind, api, row["introduced"], row["unavailable"] or "-", row["via"], "yes" if match else "no",
                                 match["kind"] if match else "-", match["introduced"] if match else "-",
                                 (match["unavailable"] or "-") if match else "-", row.get("demand-rank") or "-",
                                 row.get("demand-apps") or "-", row.get("impl-lead") or "-", "swift: needs the Swift interface source"]))
    text = "\n".join(lines) + "\n"
    write(os.path.join(args.tree, OUT_ROOT, SWIFT_BUCKET), text.encode("ascii", "backslashreplace").decode("ascii"))
    total = len(rows)
    print("swift: %d bucket rows, %d matched by the table (%d frameworks)" % (total, sum(matched.values()), len(matched)))
    return 0


# ---------------------------------------------------------------- behaviour: per method, on demand, from the 26.2 binary (REFERENCE ONLY)

# The 26.2 iOS cache is read with ipsw (`ipsw dyld disass --vaddr`), one method at a time: the implementation address is the
# objc-26.2 extract's. Every call goes through coordination/heavy.sh under timeout, one process at a time; the decompiler flags
# (--dec, --dec-llm) are never used, because they send the code to an external service. The raw output and the summary are
# untracked (.agent-work); nothing from them is committed or copied into product code.
IPSW_CACHE = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "charon", ".agent-work", "scratch", "ipsw-26.2",
                          "23C55__iPhone17,1", "dyld_shared_cache_arm64e")
HEAVY = os.path.join(os.environ.get("HOME", ""), "Git", "projects", "ios", "coordination", "heavy.sh")
BEHAVIOUR_DIR = os.path.join(".agent-work", "behaviour")


def behaviour_methods(tree, fw):
    """(cls, section, selector, address) for each objc method of the framework that the 26.2 extract gives an address."""
    out = []
    for key, row in sorted(objc_facts(tree, fw).items()):
        if key[0] == "method" and row["address"] and row["address"] != "-":
            out.append((key[1], key[2], key[3], row["address"]))
    return out


def run_ipsw_disass(tree, address, out_json, timeout=300):
    """One ipsw disassembly of the function at address, through heavy.sh. Returns (wall seconds, peak resident MB, exit code)."""
    os.makedirs(os.path.dirname(out_json), exist_ok=True)
    err_path = out_json + ".err"
    command = [HEAVY, "/usr/bin/time", "-l", "timeout", str(timeout), "ipsw", "dyld", "disass", IPSW_CACHE,
               "--vaddr", address, "--demangle"]
    started = time.time()
    with open(out_json, "w", encoding="utf-8") as stdout, open(err_path, "w", encoding="utf-8") as stderr:
        code = subprocess.run(command, stdout=stdout, stderr=stderr).returncode
    wall = time.time() - started
    peak = 0.0
    for line in read_any(err_path).splitlines():
        found = re.search(r"(\d+)\s+maximum resident set size", line)
        if found:
            peak = int(found.group(1)) / 1048576.0
    return wall, peak, code


def markup_lines(text):
    """(address, mnemonic, operands, comment) of each instruction line of ipsw's markup disassembly of one function."""
    out = []
    for line in text.splitlines():
        found = re.match(r"^(0x[0-9a-f]+):\s+(?:[0-9a-f]{2}\s+){4}(\S+)\s*(.*)$", line)
        if not found:
            continue
        operands, _, comment = found.group(3).partition(";")
        out.append((int(found.group(1), 16), found.group(2), operands.strip(), comment.strip()))
    return out


def summarise_behaviour(text):
    """What one function does, read from ipsw's markup disassembly in address order: the calls by name (demangled by ipsw), the
    branches that test a register (the argument branches are the ones on x0..x7), the constants and strings its comments name,
    and the NSError domain a call to errorWithDomain passes. A straight-line pass: no control flow is followed, so a call in a
    branch is listed where it is in the code."""
    rows = markup_lines(text)
    calls, branches, constants, strings, domains = [], [], [], [], []
    last_comment = {}
    for address, mnemonic, operands, comment in rows:
        if mnemonic in ("bl", "blr", "b") and not operands.startswith("loc_") and "loc_" not in operands:
            target = operands or "indirect"
            calls.append(target)
            if "errorWithDomain" in target and "x2" in last_comment:
                domains.append(last_comment["x2"])
        elif mnemonic.startswith("b.") or mnemonic in ("cbz", "cbnz", "tbz", "tbnz"):
            tested = re.match(r"([wx]\d+|\w+)", operands)
            branches.append(tested.group(1) if tested and mnemonic not in ("b.eq", "b.ne") or mnemonic in ("b.eq", "b.ne") else "flags")
        if comment:
            for quoted in re.findall(r'"([^"]*)"', comment):
                strings.append(quoted)
            for symbol in re.findall(r"\b(_?k[A-Z]\w+|_?CF[A-Z]\w+|_?NS[A-Z]\w+)\b", comment):
                constants.append(symbol)
            destination = re.match(r"([wx]\d+)", operands)
            if destination:
                last_comment[destination.group(1).replace("w", "x")] = comment
    return {"instructions": len(rows), "calls": calls, "argument_branches": branches, "strings": strings,
            "constants": constants, "error_domains": domains}


def cmd_behaviour(args):
    """The behaviour summary of the framework's objc methods, one at a time through heavy.sh (--limit N, --selector to pick one).
    Writes untracked pages under .agent-work/spec-docs/<F>/behaviour/ and the cost of each call to .agent-work/behaviour/costs.tsv."""
    fw = args.framework
    methods = behaviour_methods(args.tree, fw)
    if args.selector:
        methods = [m for m in methods if m[2] == args.selector]
    methods = methods[:args.limit]
    raw_dir = os.path.join(args.tree, BEHAVIOUR_DIR, fw)
    page_dir = os.path.join(args.tree, DOC_OUT, fw, "behaviour")
    os.makedirs(page_dir, exist_ok=True)
    costs_path = os.path.join(args.tree, BEHAVIOUR_DIR, "costs.tsv")
    if not os.path.exists(costs_path):
        write(costs_path, "framework\tmethod\taddress\tseconds\tpeak_mb\texit\tcalls\tbranches\n")
    pages = {}
    done = failed = 0
    for cls, section, selector, address in methods:
        raw = os.path.join(raw_dir, "%s__%s.txt" % (cls, re.sub(r"[^A-Za-z0-9_.]", "_", selector)))
        wall, peak, code = run_ipsw_disass(args.tree, address, raw)
        summary = summarise_behaviour(read_any(raw)) if code == 0 else None
        if summary is None:
            failed += 1
        else:
            done += 1
            pages.setdefault(cls, []).append((section, selector, address, summary))
        with open(costs_path, "a", encoding="ascii") as handle:
            handle.write("%s\t-[%s %s]\t%s\t%.2f\t%.0f\t%d\t%s\t%s\n" % (
                fw, cls, selector, address, wall, peak, code, len(summary["calls"]) if summary else "-",
                len(summary["argument_branches"]) if summary else "-"))
    for cls, items in sorted(pages.items()):
        page = ["# %s behaviour (%s)" % (cls, fw), "",
                "REFERENCE ONLY. Read from the 26.2 iOS cache by ipsw (markup, demangled), one function at a time: calls in the order the"
                " code makes them (a straight line through the function, no branch followed), the branches that test a register, the"
                " constants and strings named in comments, and the NSError domain a call passes. Nothing here is a decompilation, and"
                " nothing is sent to an external service.", ""]
        for section, selector, address, summary in items:
            page += ["## %s[%s %s]" % ("-" if section == "instance" else "+", cls, selector), "",
                     "address %s, %d instructions" % (address, summary["instructions"]), ""]
            page += ["Calls, in order: " + ("; ".join(summary["calls"][:40]) or "none"), ""]
            page += ["Argument branches on: " + (", ".join(summary["argument_branches"]) or "none"), ""]
            page += ["Strings: " + ("; ".join(summary["strings"]) or "none in comments"), ""]
            page += ["Constants: " + (", ".join(summary["constants"]) or "none in comments"), ""]
            page += ["Error domains: " + (", ".join(summary["error_domains"]) or "none"), ""]
        write(os.path.join(page_dir, cls + ".md"), "\n".join(page) + "\n")
    print("behaviour %s: %d methods, %d summarised, %d failed (costs in %s)" % (
        fw, len(methods), done, failed, os.path.relpath(costs_path, args.tree)))
    return 0



def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["input", "doc", "scope", "protocols", "functions", "objc", "swift", "behaviour"])
    parser.add_argument("--tree", required=True)
    parser.add_argument("--framework")
    parser.add_argument("--ledger")
    parser.add_argument("--sdk")
    parser.add_argument("--owned")
    parser.add_argument("--measured", help="release-split output of the built objects: the first release each symbol is exported in")
    parser.add_argument("--ios-constants", help="v-cache26's constants table of the iOS 26.2 cache (default: coordination/corpus/cache-26.2/)")
    parser.add_argument("--all", action="store_true", help="input, doc, protocols, functions, objc and swift: every framework")
    parser.add_argument("--out", help="doc: where the page set is written (default: .agent-work/spec-docs under the tree)")
    parser.add_argument("--limit", type=int, default=5, help="behaviour: the number of methods to summarise (default 5)")
    parser.add_argument("--selector", help="behaviour: the one selector to summarise")
    args = parser.parse_args()
    if not args.framework and not (args.all and args.command in ("doc", "input", "protocols", "functions", "objc", "swift")) and args.command not in ("scope", "swift", "objc"):
        parser.error("--framework is required (input, doc, protocols, functions, objc and swift accept --all)")
    if args.command == "doc":
        return cmd_doc(args)
    if args.command == "scope":
        return cmd_scope(args)
    if args.command == "input":
        if args.all:
            args.sdk = args.sdk or SDK26
            return cmd_input_all(args)
        if not (args.ledger and args.sdk):
            raise SystemExit("input needs --ledger and --sdk")
        return cmd_input(args)
    if args.command == "protocols":
        return cmd_protocols(args)
    if args.command == "functions":
        return cmd_functions(args)
    if args.command == "objc":
        return cmd_objc_extract(args)
    if args.command == "swift":
        return cmd_swift(args)
    return cmd_behaviour(args)


if __name__ == "__main__":
    sys.exit(main())
