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
    """A text file as it is on disk: UTF-8, no newline translation (the Lua readers take the bytes as they are)."""
    with open(path, encoding="utf-8", newline="") as handle:
        return handle.read()


def snap_dir(tree, fw):
    """The committed snapshot of a framework: spec, measured releases, classification, and the manifest of generated digests."""
    return os.path.join(tree, SNAP_ROOT, fw)


def gen_dir(tree, fw):
    """The build directory of a framework: what the generator emits. Never committed."""
    return os.path.join(tree, OUT_ROOT, fw)


def spec_path(tree, fw):
    """The spec the Lua generator writes into the build directory (tools/gen/layout.lua): the input the port reads."""
    return os.path.join(gen_dir(tree, fw), "spec.%s.tsv" % SDK_ID)


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


# ---------------------------------------------------------------- constants and snapshots


def constant_base(decl):
    words = [w for w in re.findall(r"[A-Za-z_]\w*", decl) if w not in ("const", "volatile")]
    return words[0] if words else "NSString"


# ---------------------------------------------------------------- trace layer: generated-but-unimplemented members

# The trace layer is the DEFAULTS of the design: a stub for every declared member of a framework that has no override and no
# hand implementation, compiled only with CHARON_TRACE_DEFAULTS. A stub logs `unimplemented: <framework> <selector>` once per
# member, then returns the zero of its return type (nil for an object, 0 for a scalar or enum, a zeroed struct), and sets the
# NSError an `NSError **` parameter names to an error in the framework's own domain. Block parameters are not invoked.


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


NULLABILITY_WORDS = re.compile(r"\b(_Nullable|_Nonnull|__nullable|__nonnull|_Null_unspecified|nullable|nonnull|null_resettable|null_unspecified)\b")


PLATFORM_MACROS = re.compile(r"\b__[A-Z][A-Z0-9_]*(?:\([^()]*\))?")


def strip_nullability(decl):
    """A declaration without its nullability words and the platform macros the SDK puts after it (__TVOS_PROHIBITED and the
    like): the stub compiles whether or not the header's audit and availability macros are in scope."""
    return " ".join(PLATFORM_MACROS.sub(" ", NULLABILITY_WORDS.sub(" ", decl)).split())


# The stub rule of the trace layer, as the scope counts it: which of a framework's declared members a stub would leave out, and why
# (tools/gen/stubs.lua members, with the environment tools/gen/cmd_trace.lua rule_env builds). Its inputs are the declaration
# shards' typed columns (type, params, attrs), read by name from each shard's columns=... line, and the shards' typedef, interface
# and protocol rows (tools/gen/headers.lua, tools/found/shard.lua). The scope keeps the reasons only: whether a stub exists is read
# from the trace layer's own stubs.tsv.

SCALAR_TYPES = {"BOOL", "bool", "_Bool", "char", "signed char", "unsigned char", "short", "unsigned short", "int", "signed",
                "unsigned", "unsigned int", "long", "unsigned long", "long long", "unsigned long long", "long double", "float",
                "double", "NSInteger", "NSUInteger", "CGFloat", "NSTimeInterval", "size_t", "int8_t", "int16_t", "int32_t",
                "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t"}
# The words a parameter's name cannot be, and the tags and qualifiers that come before an unnamed parameter's type (decl.lua).
KEYWORD_WORDS = {"void", "char", "short", "int", "long", "float", "double", "signed", "unsigned", "_Bool", "bool", "const",
                 "volatile", "restrict", "struct", "enum", "union", "id", "instancetype", "__kindof", "__autoreleasing",
                 "__strong", "__weak", "__unsafe_unretained"}
TYPE_LEADERS = {"struct", "enum", "union", "const", "volatile"}
MACRO_WORD = re.compile(r"_*[A-Z][A-Z0-9]*_[A-Z0-9_]*")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# A capitalised word with one of these prefixes is a macro, not a type the stub needs (stubs.lua undeclared_types).
MACRO_PREFIXES = ("NS_", "API_", "CF_")
# The C whitespace of a Lua pattern's %s.
SPACE = " \t\n\r\f\v"
SPACE_RUN = re.compile(r"[ \t\n\r\f\v]+")
# The directories the hand sources scan leaves out, at every level (hand.lua).
HAND_SKIP = {".gen", "spec", "registry", "facts", "overrides", "gen"}


def shard_path(tree, fw):
    return os.path.join(tree, SNAP_ROOT, fw, "declarations.tsv")


def shard_files(tree):
    """The declaration shards of the tree, nested frameworks included, in byte order (headers.lua shard_files)."""
    root = os.path.join(tree, SNAP_ROOT)
    return sorted(glob.glob(os.path.join(root, "*", "declarations.tsv")) + glob.glob(os.path.join(root, "*", "*", "declarations.tsv")))


def shard_rows(path, kinds=None):
    """The rows of one shard, each a dict keyed by the names of its columns=... line (headers.lua read_rows). kinds, when given,
    keeps the rows of those kinds. A missing shard has no rows."""
    if not os.path.exists(path):
        return []
    columns, out = None, []
    for line in read(path).split("\n"):
        if not line:
            continue
        if line.startswith("#"):
            names = re.search(r"columns=([^\t]*)", line)
            if names:
                columns = [name for name in names.group(1).split(",") if name]
        elif columns is not None and (kinds is None or line.split("\t", 1)[0] in kinds):
            out.append(dict(zip(columns, line.split("\t"))))
    return out


def usr_name(kind, usr):
    """The name a USR gives (shard.lua name_of): what follows its last ')' for a member, class or protocol, else what follows its
    last '@'; none for a row with no USR."""
    if usr == "-":
        return ""
    found = re.search(r"\)([^)]*)$", usr) if kind in ("method", "property", "interface", "protocol") else re.search(r"@([^@]*)$", usr)
    return found.group(1) if found else ""


def shard_name(row):
    """The name and the side a shard row gives (shard.lua decode): each is the cell the row stores, or else what its USR gives."""
    kind, usr = row["kind"], row["usr"]
    name = row.get("name") or usr_name(kind, usr)
    side = row.get("side") or ("+" if kind == "method" and "(cm)" in usr else "-")
    return name, side


def shard_members(tree, fw):
    """The method and property rows of a framework's shard that name an ObjC class, as dicts {kind, api, cls, alias, type, params,
    attrs} in the shard's order (headers.lua shard_facts). An api is side, '[', the class, a space, the name and ']'; a class
    property takes the '+' of its class accessor, and its alias is the dotted name the ledgers give it."""
    members = []
    for row in shard_rows(shard_path(tree, fw), {"method", "property"}):
        name, side = shard_name(row)
        if row["kind"] == "property" and "(cpy)" in row["usr"]:
            side = "+"
        found = re.match(r"c:objc\(cs\)([^(]+)", row["usr"])
        if found:
            cls = found.group(1)
            api = "%s[%s %s]" % (side, cls, name)
            alias = api if row["kind"] == "method" else "%s.%s" % (cls, name)
            members.append({"kind": row["kind"], "api": api, "cls": cls, "alias": alias, "type": row.get("type"),
                            "params": row.get("params"), "attrs": row.get("attrs")})
    return members


def typedef_index(tree):
    """typedef name -> the type its shard row gives, the first in the shards' order (headers.lua typedef_index)."""
    index = {}
    for path in shard_files(tree):
        for row in shard_rows(path, {"typedef"}):
            if row.get("type") is not None and row["type"] != "-":
                index.setdefault(shard_name(row)[0], row["type"])
    return index


def ios_unavailable(availability):
    """True when a shard's availability column has the iOS platform unavailable: its ios entry's last field is 1 (headers.lua)."""
    for entry in re.findall(r"[^,]+", availability or ""):
        if entry.startswith("ios=") and entry[4:].rsplit("/", 1)[-1] == "1":
            return True
    return False


def declared_names(tree):
    """The typedef, class and protocol names the iOS build sees, over every shard, less the classes the iOS SDK marks unavailable
    (headers.lua declared_names)."""
    names, unavailable = set(), set()
    for path in shard_files(tree):
        for row in shard_rows(path, {"typedef", "interface", "protocol"}):
            name = shard_name(row)[0]
            names.add(name)
            if row["kind"] == "interface" and ios_unavailable(row.get("availability")):
                unavailable.add(name)
    return names - unavailable


def canonical_type(text, index):
    """A type as a stub spells it (decl.lua canonical): no nullability word, and no macro word that no typedef names; one space
    between words; no space before a closing bracket or a comma, or after an opening one; each run of stars one run. index: typedef
    name -> the type it is defined as."""
    def drop(found):
        word = found.group(0)
        if NULLABILITY_WORDS.fullmatch(word) or (MACRO_WORD.fullmatch(word) and word not in index):
            return " "
        return word

    out = SPACE_RUN.sub(" ", re.sub(r"[A-Za-z0-9_]+", drop, text or "")).strip(SPACE)
    out = re.sub(r"[ \t\n\r\f\v]+([),>])", r"\1", out)
    out = re.sub(r"([(<])[ \t\n\r\f\v]+", r"\1", out)
    joined = re.sub(r"\*[ \t\n\r\f\v]+\*", "**", out)
    while joined != out:
        out = joined
        joined = re.sub(r"\*[ \t\n\r\f\v]+\*", "**", out)
    return out.strip(SPACE)


def kind_of(text, index, seen=None):
    """'void', 'object', 'scalar' or 'struct' for a type, through the typedefs (decl.lua kind_of); None when the type is not known.
    A typedef chain is followed to its end, and a name met again on the chain is a cycle, which gives None."""
    seen = set() if seen is None else seen
    text = canonical_type(text, index)
    if text == "void":
        return "void"
    if text in ("id", "instancetype") or "*" in text or "^" in text or "<" in text:
        return "object"
    found = re.match(r"const[ \t\n\r\f\v]+(.*)$", text)
    bare = found.group(1) if found else text
    if bare in SCALAR_TYPES or bare.startswith("enum "):
        return "scalar"
    if bare.startswith(("struct ", "union ")):
        return "struct"
    if bare in index and bare not in seen:
        seen.add(bare)
        return kind_of(index[bare], index, seen)
    return None


def parameter_types(text, index):
    """The types of a params column ("TYPE NAME | TYPE NAME"; "-" or nothing for none), each without its name (decl.lua parse_params
    and split_name): the last word is a name when it is an identifier that is no keyword and the word before it is no tag."""
    if text in (None, "", "-"):
        return []
    types = []
    for part in text.split(" | "):
        spelled = canonical_type(part, index)
        words = spelled.split(" ") if spelled else []
        if len(words) >= 2 and IDENTIFIER.fullmatch(words[-1]) and words[-1] not in KEYWORD_WORDS and words[-2] not in TYPE_LEADERS:
            types.append(" ".join(words[:-1]))
        else:
            types.append(spelled)
    return types


def member_name(api):
    """The name a member row's api ends in: its last word once the closing brackets are gone (decl.lua member_name)."""
    found = re.search(r"(\S+)\s*$", re.sub(r"\]+$", "", api))
    return found.group(1) if found else None


def attribute_value(attrs, key):
    """The value of one attribute of a property's attrs column ("nonatomic,getter=isEnabled"), or None (decl.lua attribute_value)."""
    for entry in re.findall(r"[^,]+", attrs or ""):
        if entry.startswith(key + "="):
            return entry[len(key) + 1:].strip(SPACE)
    return None


def has_attribute(attrs, name):
    """True when the attrs column has the attribute by its bare name (decl.lua has_attribute)."""
    return any(entry.strip(SPACE) == name for entry in re.findall(r"[^,]+", attrs or ""))


def undeclared_types(text, declared):
    """The capitalised words of a type text that the iOS build does not declare, sorted, a macro word left out (stubs.lua
    undeclared_types)."""
    out = set()
    for word in re.findall(r"[A-Za-z0-9_]+", text):
        if "A" <= word[0] <= "Z" and word not in declared and not word.startswith(MACRO_PREFIXES):
            out.add(word)
    return sorted(out)


def hand_sources(tree):
    """The .m and .mm files of the package, the directories HAND_SKIP names left out at every level, and no symbolic link followed
    (hand.lua sources)."""
    found = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(tree, SOURCES_ROOT)):
        dirnames[:] = [d for d in dirnames if d not in HAND_SKIP and not os.path.islink(os.path.join(dirpath, d))]
        found += [os.path.join(dirpath, name) for name in filenames if name.endswith((".m", ".mm"))]
    return found


def hand_implementations(tree):
    """class -> the selectors, and the synthesized or dynamic property names, that the package's hand sources define (hand.lua
    implementations). A method signature spans lines until its brace or its semicolon. A stub must not replace one of these."""
    found = {}

    def add(cls, selector):
        if selector:
            found.setdefault(cls, set()).add(selector)

    for path in hand_sources(tree):
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as handle:
            text = handle.read().replace("\r\n", "\n").replace("\r", "\n")
        current, signature = None, None
        for line in text.splitlines():
            if signature is not None:
                signature += " " + line.strip(SPACE)
                if "{" in line or ";" in line:
                    add(current, selector_of(signature.split("{")[0].split(";")[0]))
                    signature = None
                continue
            impl = re.match(r"[ \t\n\r\f\v]*@implementation[ \t\n\r\f\v]+([A-Za-z0-9_]+)", line)
            if impl:
                current = impl.group(1)
            elif re.match(r"[ \t\n\r\f\v]*@end(?![A-Za-z0-9_])", line):
                current = None
            elif current is not None:
                synth = re.match(r"[ \t\n\r\f\v]*@(?:synthesize|dynamic)[ \t\n\r\f\v]+([A-Za-z0-9_]+)", line)
                if synth:
                    found.setdefault(current, set()).add(synth.group(1))
                if re.match(r"[ \t\n\r\f\v]*[-+][ \t\n\r\f\v]*\(", line):
                    if "{" in line or ";" in line:
                        add(current, selector_of(line.split("{")[0].split(";")[0]))
                    else:
                        signature = line.strip(SPACE)
    return found


def member_skip(r, env, seen):
    """Why the stub rule leaves one spec row out, or None when a stub answers it (stubs.lua consider, with its property and method
    rules). seen: the (sign, class, selector) keys already taken; a repeat is the same selector declared twice in the class."""
    api, kind, cls = r["api"], r["kind"], r["cls"]
    if env["release_missing"] is not None:
        ledger_api = api if kind == "method" else "%s.%s" % (cls, member_name(api))
        if (kind, ledger_api) not in env["release_missing"]:
            return "implemented at 6.1.3: the release answers"
    fact = env["members"].get(api)
    if fact is None:
        return "no typed fact in the shard"
    params = parameter_types(fact["params"], env["index"])
    ret = canonical_type(fact["type"], env["index"])
    undeclared = undeclared_types(" ".join([ret] + params), env["declared"])
    if undeclared:
        return "type not declared for iOS: " + ",".join(undeclared)
    sign, hand = api[0], env["hand"]
    if kind == "property":
        name = member_name(api)
        selector = attribute_value(fact["attrs"], "getter") or name
        hand_defined = cls in hand and (name in hand[cls] or selector in hand[cls])
    else:
        selector = re.match(r"[^ ]* (.*)$", re.sub(r"\]+$", "", api)).group(1)
        hand_defined = cls in hand and selector in hand[cls]
    if api in env["overridden"] or hand_defined:
        return "override or hand implementation"
    if ret == "":
        return "no property type in the shard" if kind == "property" else "no return type in the shard"
    if kind == "method" and selector.count(":") != len(params):
        return "parameters do not match the selector"
    if kind_of(ret, env["index"]) is None:
        return "type not resolved: " + ret
    key = (sign, cls, selector)
    if key in seen:
        return "same selector declared twice in the class"
    seen.add(key)
    return None


def stub_skips(spec, env):
    """(api, reason) for each method and property row of the spec the stub rule leaves out, in the order the rule decides them
    (stubs.lua members)."""
    seen, skipped = set(), []
    for r in spec:
        if r["kind"] in ("method", "property"):
            reason = member_skip(r, env, seen)
            if reason is not None:
                skipped.append((r["api"], reason))
    return skipped


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


# The doc command is the port of tools/gen/cmd_doc.lua and the modules it uses. Its inputs are read the way the Lua reads them: the spec
# table the generator wrote under .gen (one row per member and constant), the declaration shard of each framework (the superclasses),
# the doc-time rows of the extractor (decls --doc, read through a pipe), the registry, the pins and the trace's skipped list of the tree,
# and the surface, ledgers, oracle defaults, ObjC table (three gzip parts) and protocol records of --coordination. Every text is read as
# bytes (one character per byte), a table is split on tabs and its lines on line feeds (tsv.lua), and a page is written only when it is
# ASCII (emit.lua). The page text the oracle always had is kept, so the output is identical.
DOC_REGENERATE = "tools/gen.py doc"
DOC_IMPLEMENTED = "implemented"
DOC_NO_VALUE = "-"
DOC_DEFAULT_SUPERCLASS = "NSObject"
DOC_LEDGER_6_1_3 = "ledger-w45"
DOC_LEDGER_4_3 = "ledger-w45-4.3"
DOC_COMMENTS_NOT_DERIVED = "- not derived: the extractor does not run for this framework"
DOC_DECL_NOT_DERIVED = "not derived: decl (ruling D8)"
DOC_NOT_IN_ROWS = "not derived: not in the doc rows"
DOC_NO_COMMENT = "no comment in the doc rows"
DOC_BEHAVIOUR_NOTE = ("Not part of this page. `xmake l tools/gen.lua behaviour --framework <framework> --coordination <corpus> "
                      "--ipsw-cache <cache>` writes the summary of the methods it is run on (the calls in the order the code makes "
                      "them, the register branches, the strings, constants and error domains its comments name; REFERENCE ONLY) "
                      "to `behaviour/<Class>.md` beside this page. It reads the on-disk iOS 26.2 cache one method at a time through "
                      "coordination/heavy.sh (--limit and --selector choose the methods). No command produces implementation "
                      "pseudocode yet.")
DOC_ORACLE_ROWS = 60
DOC_CELL_LIMIT = 400
DOC_FIXED_PAGES = ("index.md", "Constants.md", "Swift.md")
DOC_EXTENSION = {"class": ".md", "protocol": ".protocol.md"}
DOC_SUFFIX_LENGTH = 8
DOC_EXTRACTOR = os.path.join("build", "macosx", "arm64", "release", "decls")
DOC_CELLS = 10
DOC_UNESCAPE = {"\\": "\\", "t": "\t", "n": "\n", "r": "\r"}
DOC_OBJC_ENTITIES = (b"class", b"method", b"property")
DOC_OBJC_FIELDS = ("entity", "owner", "section", "name", "decl", "types", "address", "superclass", "protocols", "category")


def doc_lines(text):
    """The lines of a text as tsv.lua lines gives them: a line feed ends a line, and a final one ends the last line."""
    if text == "":
        return []
    lines = text.split("\n")
    if text.endswith("\n"):
        lines.pop()
    return lines


def doc_records(text):
    """The rows of a table (tsv.lua records): a dict per row keyed by the header's names, empty lines skipped; a cell the row lacks is None."""
    lines = doc_lines(text)
    header = lines[0].split("\t") if lines else [""]
    out = []
    for line in lines[1:]:
        if line == "":
            continue
        cells = line.split("\t")
        out.append({name: (cells[i] if i < len(cells) else None) for i, name in enumerate(header)})
    return out


def doc_read(filepath):
    """A file as its bytes, one character per byte (latin-1), or None when there is no such file (files.lua read_text)."""
    if not os.path.isfile(filepath):
        return None
    with open(filepath, "rb") as handle:
        return handle.read().decode("latin-1")


def doc_present(value):
    """Lua's present(): a missing or an empty cell is not present."""
    return value is not None and value != ""


def doc_either(value, fallback):
    """Lua's either(): the value when it is present, else the fallback."""
    return value if doc_present(value) else fallback


def doc_tostring(value):
    """Lua's tostring() of a cell: a missing cell is "nil"."""
    return "nil" if value is None else str(value)


def doc_md_cell(value):
    """A value in a markdown cell (cmd_doc.lua md_cell): "None" when missing, pipes escaped, newlines turned to spaces, length capped."""
    text = "None" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ")[:DOC_CELL_LIMIT]


def doc_sequence_at(text, i):
    """The UTF-8 sequence at character i of text (one character per byte): its length and code point, or None when the bytes there are
    not one well-formed sequence (cmd_doc.lua sequence_at)."""
    lead = ord(text[i])
    if 0xC2 <= lead <= 0xDF:
        count, code = 2, lead & 0x1F
    elif 0xE0 <= lead <= 0xEF:
        count, code = 3, lead & 0x0F
    elif 0xF0 <= lead <= 0xF4:
        count, code = 4, lead & 0x07
    else:
        return None
    if i + count > len(text):
        return None
    for k in range(i + 1, i + count):
        byte = ord(text[k])
        if byte < 0x80 or byte > 0xBF:
            return None
        code = (code << 6) | (byte & 0x3F)
    return count, code


def doc_ascii(text):
    """The text as ASCII (cmd_doc.lua ascii_text): a UTF-8 character is written \\u{hex}, a byte that is not UTF-8 is written \\xhh."""
    out, i = [], 0
    while i < len(text):
        code = ord(text[i])
        if code < 0x80:
            out.append(text[i])
            i += 1
            continue
        found = doc_sequence_at(text, i)
        if found is None:
            out.append("\\x%02x" % code)
            i += 1
        else:
            out.append("\\u{%x}" % found[1])
            i += found[0]
    return "".join(out)


def doc_decl_text(text):
    """A declaration in a markdown table cell: ASCII, with its pipes escaped; it is not cut (cmd_doc.lua decl_text)."""
    return doc_ascii(text).replace("|", "\\|")


def doc_longest_run(text):
    """The length of the longest run of backticks in the text (0 when there is none)."""
    return max((len(run) for run in re.findall(r"`+", text)), default=0)


def doc_fence(text):
    """A fence for a block that holds the text: three backticks, or one more than the longest run of backticks in it (fence_of)."""
    return "`" * max(3, doc_longest_run(text) + 1)


def doc_code_span(text):
    """The text as a markdown code span: its delimiter one backtick longer than the longest run in it, padded when it is longer than one
    (cmd_doc.lua code_span)."""
    longest = doc_longest_run(text)
    if longest == 0:
        return "`" + text + "`"
    delimiter = "`" * (longest + 1)
    return delimiter + " " + text + " " + delimiter


def doc_decl_cell(docs, kind, api):
    """The declaration cell of a member (cmd_doc.lua decl_cell): the extractor's declaration as a code span, the marked text when the
    framework has no doc rows (docs is None), or when the extractor does not list the member."""
    if docs is None:
        return doc_code_span(DOC_DECL_NOT_DERIVED)
    row = docs.get(kind + " " + api)
    if row is None:
        return doc_code_span(DOC_NOT_IN_ROWS)
    return doc_code_span(doc_decl_text(row["decl"]))


def doc_comments_section(docs, entries):
    """The header comments section of a class or protocol, as lines (cmd_doc.lua comments_section): the heading, a blank line, then the
    body. A member with a comment has a heading (its api) and its raw comment in a fenced block; a member with no comment, or that the
    extractor does not list, is one bullet after the blocks. entries are (kind, api) pairs in the page's order."""
    page = ["## Header comments", ""]
    if docs is None:
        page.append(DOC_COMMENTS_NOT_DERIVED)
        return page
    blocks, bullets = [], []
    for kind, api in entries:
        row = docs.get(kind + " " + api)
        if row is None:
            bullets.append("- `%s`: %s" % (api, DOC_NOT_IN_ROWS))
        elif row["comment"] == "":
            bullets.append("- `%s`: %s" % (api, DOC_NO_COMMENT))
        else:
            text = doc_ascii(row["comment"])
            fence = doc_fence(text)
            blocks.append(["### `" + api + "`", "", fence] + (text + "\n").split("\n")[:-1] + [fence])
    body = []
    for block in blocks:
        if body:
            body.append("")
        body.extend(block)
    if bullets:
        if body:
            body.append("")
        body.extend(bullets)
    return page + body


def doc_strip_brackets(api):
    """api.rstrip("]") of the oracle (cmd_doc.lua strip_brackets)."""
    return api.rstrip("]")


def doc_selector_of(api):
    """A method's selector: the text after the first space of api.rstrip("]") (cmd_doc.lua selector_of)."""
    text = doc_strip_brackets(api)
    space = text.find(" ")
    return text[space + 1:] if space >= 0 else ""


def doc_name_of(api):
    """A property's name: the last space-separated word of api.rstrip("]") (cmd_doc.lua name_of)."""
    return doc_strip_brackets(api).rsplit(" ", 1)[-1]


def doc_objc_key(entity, owner, section, name):
    """The key of an ObjC fact: entity, owner, section and name, joined by tabs (objc.lua key_of)."""
    return "\t".join((entity, owner, section, name))


def doc_sorted(items, fields):
    """The items in the order of their named fields (cmd_doc.lua by_fields with sorted_stable): a stable sort."""
    return sorted(items, key=lambda item: tuple(item[name] for name in fields))


def doc_emit(filepath, lines):
    """The page's lines written as one text, ending in a line feed (emit.lua)."""
    write(filepath, "\n".join(lines) + "\n")


def doc_frameworks(tree):
    """The frameworks of the tree that have a declaration shard, in byte order, nested ones named Outer/Inner (spec.lua frameworks)."""
    root = os.path.join(tree, SNAP_ROOT)
    names = []
    for pattern in ("*", "*/*"):
        for filepath in glob.glob(os.path.join(root, pattern, "declarations.tsv")):
            if os.path.isfile(filepath):
                names.append(os.path.relpath(os.path.dirname(filepath), root))
    return sorted(names)


def doc_spec(tree, fw):
    """The spec rows of a framework: the member and constant rows the generator wrote under .gen, as records."""
    text = doc_read(spec_path(tree, fw))
    if text is None:
        raise SystemExit("doc %s: no spec table at %s (run gen first)" % (fw, spec_path(tree, fw)))
    return doc_records(text)


def doc_needs(spec):
    """The ObjC keys the framework's pages read: the key of each method and property the spec names, and the owners of its classes."""
    keys, owners = set(), set()
    for r in spec:
        if r["kind"] not in ("method", "property"):
            continue
        owners.add(r["cls"])
        if r["kind"] == "method":
            section = "instance" if r["api"].startswith("-") else "class"
            keys.add(doc_objc_key("method", r["cls"], section, doc_selector_of(r["api"])))
        else:
            keys.add(doc_objc_key("property", r["cls"], "instance", doc_name_of(r["api"])))
    return {"keys": keys, "owners": owners}


def doc_framework_of(image):
    """The framework of an ObjC table image (objc.lua framework_of): the folder of the image without its .framework suffix when the
    folder is a framework, else the image's own name."""
    folder = image.rpartition("/")[0].rpartition("/")[2]
    if folder.endswith(".framework"):
        return folder[:-len(".framework")]
    return image.rpartition("/")[2]


def doc_read_objc(corpus, needs):
    """One pass over the ObjC table's three gzip parts for every framework of the run (cmd_doc.lua read_objc, objc.lua each): per
    framework, the first row of each member key the spec names and the last class row of each owner the spec names (the first row of
    each class key). Returns framework -> {"index", "meta"}."""
    state = {}
    for fw, need in needs.items():
        state[fw] = {"keys": need["keys"], "owners": need["owners"], "index": {}, "meta": {}, "seen": set()}
    memo = {}
    header, columns, count = None, {}, 0
    for part in OBJC_PARTS:
        filepath = os.path.join(corpus, "cache-26.2", part)
        if not os.path.isfile(filepath):
            raise SystemExit("no objc table part: " + filepath)
        first, number = True, 0
        with gzip.open(filepath, "rb") as handle:
            for raw in handle:
                number += 1
                line = raw[:-1] if raw.endswith(b"\n") else raw
                if first:
                    first = False
                    if header is None:
                        header = line
                        names = line.decode("latin-1").split("\t")
                        columns = {name: i for i, name in enumerate(names)}
                        if columns.get("image") != 0 or columns.get("entity") != 1:
                            raise SystemExit("the objc table's first columns are image and entity")
                        for name in DOC_OBJC_FIELDS:
                            if name not in columns:
                                raise SystemExit("the objc table has no column " + name)
                        count = len(names)
                    elif line != header:
                        raise SystemExit("objc table part %s has another header" % part)
                    continue
                t1 = line.find(b"\t")
                if t1 < 0:
                    raise SystemExit("objc table %s line %d is a short row (no tab): %s" % (filepath, number, line[:80]))
                t2 = line.find(b"\t", t1 + 1)
                entity = line[t1 + 1:(t2 if t2 >= 0 else len(line))]
                if entity not in DOC_OBJC_ENTITIES:
                    continue
                if t2 < 0:
                    raise SystemExit("objc table %s line %d is a short row (no cell after its entity): %s" % (filepath, number, line[:80]))
                image = line[:t1].decode("latin-1")
                fw = memo.get(image)
                if fw is None:
                    fw = doc_framework_of(image)
                    memo[image] = fw
                if fw not in state:
                    continue
                cells = line.decode("latin-1").split("\t")
                if len(cells) < count:
                    raise SystemExit("objc table %s line %d is a short row: %d cells where the header has %d" % (filepath, number, len(cells), count))
                s = state[fw]
                key = "\t".join((cells[columns["entity"]], cells[columns["owner"]], cells[columns["section"]], cells[columns["name"]]))
                if entity == b"class":
                    owner = cells[columns["owner"]]
                    if owner in s["owners"] and key not in s["seen"]:
                        s["seen"].add(key)
                        s["meta"][owner] = {name: cells[columns[name]] for name in DOC_OBJC_FIELDS}
                elif key in s["keys"] and key not in s["index"]:
                    s["index"][key] = {name: cells[columns[name]] for name in DOC_OBJC_FIELDS}
    return state


def doc_ledger_status(corpus, fw, release_dir):
    """(kind, api) -> status for the rows the framework's ledger of one release lists (surface.lua ledger_status); a row the ledger does not
    list is implemented in that release."""
    out = {}
    text = doc_read(os.path.join(corpus, release_dir, fw.replace("/", "_") + ".tsv"))
    if text is None:
        return out
    for row in doc_records(text):
        if row.get("kind") and row.get("api"):
            out[(row["kind"], row["api"])] = row.get("status")
    return out


DOC_SURFACE = {}


def doc_surface_rows(corpus, fw):
    """(kind, api) -> the surface row for one framework (surface.lua surface_rows): the table is read once, and a key the table names
    again keeps the later row."""
    if corpus not in DOC_SURFACE:
        rows = {}
        header = None
        text = doc_read(os.path.join(corpus, "sdk-26.2-surface.tsv"))
        if text is None:
            raise SystemExit("no surface table in the corpus: " + os.path.join(corpus, "sdk-26.2-surface.tsv"))
        for line in doc_lines(text):
            cells = line.split("\t")
            if header is None:
                header = cells
                continue
            row = {name: (cells[i] if i < len(cells) else None) for i, name in enumerate(header)}
            rows.setdefault(row.get("framework"), {})[(row.get("kind"), row.get("api"))] = row
        DOC_SURFACE[corpus] = rows
    return DOC_SURFACE[corpus].get(fw, {})


def doc_oracle_defaults(corpus, fw):
    """class -> [(item, value_kind, value, build)] from the host oracle capture (surface.lua oracle_defaults)."""
    out = {}
    text = doc_read(os.path.join(corpus, "cache-26.2", "oracle-defaults.tsv"))
    if text is None:
        return out
    for row in doc_records(text):
        if row.get("framework") == fw:
            out.setdefault(row.get("class"), []).append((row.get("item"), row.get("value_kind"), row.get("value"), row.get("build")))
    return out


def doc_pins(tree, fw):
    """api -> the pin row of the framework's sidecar; the last row of an api wins (snapshot.pins)."""
    out = {}
    text = doc_read(os.path.join(tree, PINS_ROOT, fw + ".tsv"))
    if text is not None:
        for row in doc_records(text):
            out[row.get("api")] = row
    return out


def doc_skipped(tree, fw):
    """api -> the reason the trace layer leaves the member out (trace_files.lua skipped_file); a row with no reason removes the api."""
    out = {}
    text = doc_read(os.path.join(gen_dir(tree, fw), "trace", "skipped.tsv"))
    if text is not None:
        for row in doc_records(text):
            if row.get("reason") is None:
                out.pop(row.get("api"), None)
            else:
                out[row.get("api")] = row["reason"]
    return out


def doc_superclasses(tree, fw):
    """class -> the superclass its @interface names, from the super rows of the framework's declaration shard (headers.lua shard_facts:
    a super row names its class in container and its superclass in name; a later row of one class replaces an earlier one)."""
    out = {}
    text = doc_read(os.path.join(tree, SNAP_ROOT, fw, "declarations.tsv"))
    if text is None:
        return out
    columns = None
    for line in text.split("\n"):
        if line == "":
            continue
        if line.startswith("#"):
            found = re.search(r"columns=([^\t]*)", line)
            if found:
                columns = [name for name in found.group(1).split(",") if name]
        elif columns is not None and line.split("\t", 1)[0] == "super":
            row = dict(zip(columns, line.split("\t")))
            usr = row.get("usr") or "-"
            name = row.get("name") or ""
            if name == "" and usr != "-":
                found = re.search(r"@([^@]*)$", usr)
                name = found.group(1) if found else ""
            out[row.get("container")] = name
    return out


def doc_protocols(tree, fw):
    """protocol name -> its record from the snapshot, with its members (protocols.lua records); {} without a protocol snapshot."""
    out = {}
    text = doc_read(os.path.join(tree, SNAP_ROOT, fw, "protocols.tsv"))
    if text is None:
        return out
    for row in doc_records(text):
        name = row.get("protocol")
        record = out.get(name)
        if record is None:
            record = {"introduced": row.get("introduced"), "status": row.get("status"), "reasons": row.get("reasons"),
                      "bases": row.get("bases"), "members": []}
            out[name] = record
        if row.get("section") != "-":
            record["members"].append({"section": row.get("section"), "kind": row.get("kind"),
                                      "instance": row.get("instance") == "yes", "selector": row.get("selector"),
                                      "decl": row.get("decl"), "in16": row.get("in16")})
    return out


def doc_swift_rows(tree, fw):
    """The Swift bucket rows of a framework, as the generator wrote them (swift.lua read_bucket), in the file's order."""
    text = doc_read(os.path.join(tree, OUT_ROOT, "swift", "bucket.tsv"))
    if text is None:
        return []
    return [row for row in doc_records(text) if row.get("framework") == fw]


DOC_UNESCAPE_RE = re.compile(r"\\(.)", re.S)


def doc_decode(line):
    """The cells of one row of the extractor's doc mode, unescaped (doc_text.lua decode)."""
    return [DOC_UNESCAPE_RE.sub(lambda m: DOC_UNESCAPE.get(m.group(1), m.group(0)), piece) for piece in line.split("\t")]


def doc_side_of(kind, usr):
    """The side of a member as the shard reader gives it: a class method and a class property are "+", every other member "-"."""
    if kind == "method" and "(cm)" in usr:
        return "+"
    if kind == "property" and "(cpy)" in usr:
        return "+"
    return "-"


def doc_api_of(kind, usr, name):
    """The api a member row has, as the spec writes it, or None when it is not a member of an ObjC owner (doc_text.lua api_of)."""
    if kind not in ("method", "property"):
        return None
    found = re.match(r"c:objc\([A-Za-z]+\)([^(]+)", usr)
    if found is None:
        return None
    return doc_side_of(kind, usr) + "[" + found.group(1) + " " + name + "]"


def doc_run(program, args, sdk, each):
    """Runs the extractor with IR_SDK set and calls each(line) for every line of its standard output, read through a pipe (nothing is
    written to a file). Returns the exit status and the last bytes of its standard error (doc_text.lua stream.run)."""
    import threading
    env = dict(os.environ)
    env["IR_SDK"] = sdk
    proc = subprocess.Popen([program] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    errors = []
    reader = threading.Thread(target=lambda: errors.append(proc.stderr.read()))
    reader.daemon = True
    reader.start()
    try:
        for raw in proc.stdout:
            each(raw[:-1].decode("latin-1") if raw.endswith(b"\n") else raw.decode("latin-1"))
    except BaseException:
        proc.kill()
        proc.wait()
        raise
    status = proc.wait()
    reader.join()
    return status, b"".join(errors)[-(1 << 20):].decode("latin-1")


def doc_decls_binary(tree):
    """The extractor's binary of a tree: build/macosx/arm64/release/decls under the tree. One that is not built is an error."""
    program = os.path.join(os.path.abspath(tree), DOC_EXTRACTOR)
    if not os.path.isfile(program):
        raise SystemExit("the extractor is not built: %s (build it from the tree: xmake -P tools/found)" % program)
    return program


def doc_listed(program, sdk):
    """The frameworks the extractor lists for the SDK (decls --list): a set of names."""
    names = set()

    def take(line):
        name = line.split("\t", 1)[0]
        if name != "":
            names.add(name)

    status, err = doc_run(program, ["--list"], sdk, take)
    if status != 0:
        raise SystemExit("decls --list failed (status %d): %s" % (status, err.strip()[-300:]))
    return names


def doc_api_map(program, fw, sdk):
    """The doc-time rows of a listed framework (doc_text.lua rows): from "kind api" to the first row of each member, the rows of a USR
    the extractor writes twice counting once. A listed framework whose doc mode fails stops the run."""
    usr_seen = set()
    api = {}

    def take(line):
        cells = doc_decode(line)
        if len(cells) != DOC_CELLS:
            raise SystemExit("a doc row of %s has %d cells, not %d" % (fw, len(cells), DOC_CELLS))
        key = cells[2]
        if key == "-" or key in usr_seen:
            return
        usr_seen.add(key)
        kind = cells[1]
        member = doc_api_of(kind, key, cells[4])
        entry = {"kind": kind, "api": member, "comment": cells[8] if cells[8] != "" else cells[7], "decl": cells[9]}
        if member is not None:
            api.setdefault(kind + " " + member, entry)

    status, err = doc_run(program, ["--doc", fw], sdk, take)
    if status != 0:
        raise SystemExit("doc %s: the extractor lists it, but its doc rows cannot be produced: decls --doc exits with status %d%s"
                         % (fw, status, (": " + err.strip()[-300:]) if err.strip() else ""))
    return api


def doc_text_rows(ctx, fw):
    """The doc-time rows of a framework: (its api map, None), or (None, the reason) when the extractor does not list it (its pages keep
    the marked text)."""
    if ctx["binary"] is None:
        ctx["binary"] = doc_decls_binary(ctx["tree"])
    if ctx["listed"] is None:
        ctx["listed"] = doc_listed(ctx["binary"], ctx["sdk"])
    if fw not in ctx["listed"]:
        return None, "the extractor does not list it"
    return doc_api_map(ctx["binary"], fw, ctx["sdk"]), None


def doc_page_names(entries, reserved):
    """The file names of the pages of one folder (pages.lua names): a class is <Name>.md and a protocol <Name>.protocol.md; a name that
    would be shared on a case-insensitive file system is disambiguated with the first 8 hex digits of the SHA-256 of "<kind> <Name>"."""
    def fold(name):
        if not name.isascii():
            raise SystemExit("a page name is ASCII: " + name)
        return name.lower()

    plain, count = {}, {}
    for file in reserved:
        count[fold(file)] = count.get(fold(file), 0) + 1
    for kind, name in entries:
        file = name + DOC_EXTENSION[kind]
        plain[(kind, name)] = file
        count[fold(file)] = count.get(fold(file), 0) + 1
    out, owner = {}, {}
    for file in reserved:
        owner[fold(file)] = file
    for kind, name in entries:
        ident = kind + " " + name
        file = plain[(kind, name)]
        if count[fold(file)] > 1:
            file = name + "." + hashlib.sha256(ident.encode("ascii")).hexdigest()[:DOC_SUFFIX_LENGTH] + DOC_EXTENSION[kind]
        clash = owner.get(fold(file))
        if clash is not None:
            raise SystemExit("pages of %s and %s have one file name on a case-insensitive file system: %s" % (ident, clash, file))
        owner[fold(file)] = ident
        out[(kind, name)] = file
    return out


def doc_class_page(fw, cls, members, ctx):
    """The page of one class (cmd_doc.lua class_page): its members in (kind, api) order, the oracle's table, the header comments, the
    binary's ObjC metadata and the behaviour note."""
    page = ["# %s (%s)" % (cls, fw), "",
            "Superclass: %s. Status at 6.1.3 and 4.3 is per member below." % doc_either(ctx["superclasses"].get(cls), DOC_NO_VALUE), "",
            "| kind | declaration (26.2 header, normalised) | availability | 6.1.3 | 4.3 | demand | impl-lead | ours (registry, pin) | stub |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    ordered = doc_sorted(members, ("kind", "api"))
    for r in ordered:
        key = (r["kind"], r["api"])
        s6 = doc_either(ctx["led6"].get(key), DOC_IMPLEMENTED)
        s43 = doc_either(ctx["led43"].get(key), DOC_IMPLEMENTED)
        srow = ctx["surf"].get(key) or {}
        demand = DOC_NO_VALUE
        if doc_present(srow.get("demand-rank")):
            demand = "rank %s, %s, %s apps" % (doc_either(srow.get("demand-rank"), DOC_NO_VALUE),
                                               doc_either(srow.get("demand-severity"), DOC_NO_VALUE),
                                               doc_either(srow.get("demand-apps"), DOC_NO_VALUE))
        ours = DOC_NO_VALUE
        registered = ctx["regs"].get(r["api"])
        if registered is not None:
            registry_path, entry = registered
            status = entry.get("status")
            pin = ctx["pins"].get(r["api"])
            pin_text = (", pin " + doc_tostring(pin.get("pinned-by"))) if pin is not None else ""
            ours = "%s: %s%s" % ("?" if status is None else status, registry_path, pin_text)
        if registered is not None:
            stub = "hand/override"
        elif r["api"] in ctx["skipped"]:
            stub = "not stubbed: " + ctx["skipped"][r["api"]]
        else:
            stub = "stub"
        availability = r.get("availability")
        if availability is None or availability == DOC_NO_VALUE:
            availability = DOC_NO_VALUE
        page.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["kind"], doc_decl_cell(ctx["docs"], r["kind"], r["api"]), doc_md_cell(availability), s6, s43, demand,
            doc_md_cell(doc_either(srow.get("impl-lead"), DOC_NO_VALUE)), doc_md_cell(ours), doc_md_cell(stub)))
    page.append("")
    page.extend(doc_comments_section(ctx["docs"], [(r["kind"], r["api"]) for r in ordered]))
    if cls in ctx["oracle"]:
        page += ["", "## Host oracle (macOS, class state and defaults; v-cache26 capture)", "", "| item | kind | value | build |",
                 "| --- | --- | --- | --- |"]
        for row in ctx["oracle"][cls][:DOC_ORACLE_ROWS]:
            page.append("| %s | %s | %s | %s |" % tuple(doc_md_cell(x) for x in row))
    page += ["", "## Runtime metadata (26.2 binary, v-cache26 ObjC table; REFERENCE ONLY: the encodings give the binary's argument",
             "and return types, not what a method does)", ""]
    meta = ctx["meta"].get(cls)
    if meta is not None:
        page.append("Superclass in the binary: %s. Protocols: %s." % (doc_either(meta.get("superclass"), DOC_NO_VALUE),
                                                                      doc_either(meta.get("protocols"), DOC_NO_VALUE)))
    else:
        page.append("No class row for this class in the binary's ObjC table.")
    page += ["", "| member | binary type encoding | binary address |", "| --- | --- | --- |"]
    for r in ordered:
        if r["kind"] == "method":
            key = doc_objc_key("method", cls, "instance" if r["api"].startswith("-") else "class", doc_selector_of(r["api"]))
        else:
            key = doc_objc_key("property", cls, "instance", doc_name_of(r["api"]))
        row = ctx["objc"].get(key)
        if row is None:
            types_cell, address_cell = "not in the table", DOC_NO_VALUE
        else:
            types_cell = doc_md_cell(row.get("types"))
            address_cell = DOC_NO_VALUE if row.get("address") is None else row["address"]
        page.append("| `%s` | %s | %s |" % (doc_md_cell(r["api"]), types_cell, address_cell))
    page += ["", "## Behaviour summary", "", DOC_BEHAVIOUR_NOTE, ""]
    return page


def doc_protocol_page(fw, name, record, ctx):
    """The page of one protocol (cmd_doc.lua protocol_page): its record, its members in (section, kind, selector) order, the header
    comments (from the doc rows, or marked) and the behaviour note. A member's doc row is keyed by its sign: "-" for an instance member."""
    page = ["# %s (%s, protocol)" % (name, fw), "",
            "Status in the transcriber's facts: %s. Introduced %s. Bases: %s." % (record["status"], record["introduced"],
                                                                               doc_either(record["bases"], DOC_DEFAULT_SUPERCLASS)), "",
            "Reasons from the transcriber: %s." % doc_either(record["reasons"], "none"), "",
            "A protocol member has no stub: its implementation is the conforming class's, and a class row of the surface is"
            " stubbed where the release lacks it. The declaration is the transcriber's rendering of the 26.2 AST.", "",
            "| section | kind | declaration (26.2 AST, transcriber rendering) | in 16.4 body | 6.1.3 | demand | ours |",
            "| --- | --- | --- | --- | --- | --- | --- |"]
    entries = []
    for member in doc_sorted(record["members"], ("section", "kind", "selector")):
        api = "-[%s %s]" % (name, member["selector"])
        srow = ctx["surf"].get((member["kind"], api)) or {}
        demand = DOC_NO_VALUE
        if doc_present(srow.get("demand-rank")):
            demand = "rank %s, %s apps" % (srow["demand-rank"], doc_either(srow.get("demand-apps"), DOC_NO_VALUE))
        ours = "hand/registry" if ctx["regs"].get(api) is not None else DOC_NO_VALUE
        doc_api = ("-" if member["instance"] else "+") + "[" + name + " " + member["selector"] + "]"
        entries.append((member["kind"], doc_api))
        page.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            member["section"], member["kind"], doc_decl_cell(ctx["docs"], member["kind"], doc_api), member["in16"],
            doc_either(ctx["led6"].get((member["kind"], api)), DOC_IMPLEMENTED), demand, ours))
    page.append("")
    page.extend(doc_comments_section(ctx["docs"], entries))
    page += ["", "## Behaviour summary", "", DOC_BEHAVIOUR_NOTE]
    return page


def doc_write_framework(ctx, fw, objc):
    """Writes the pages of one framework (cmd_doc.lua write_framework). Returns the number of class pages."""
    tree, corpus = ctx["tree"], ctx["corpus"]
    spec = doc_spec(tree, fw)
    superclasses = doc_superclasses(tree, fw)
    members_by_class, class_names, constant_rows = {}, [], []
    for r in spec:
        if r["kind"] in ("method", "property"):
            if r["cls"] not in members_by_class:
                members_by_class[r["cls"]] = []
                class_names.append(r["cls"])
            members_by_class[r["cls"]].append(r)
        elif r["kind"] == "constant":
            constant_rows.append(r)
    classes = sorted(class_names)
    member_count = sum(len(members_by_class[cls]) for cls in classes)
    skipped = doc_skipped(tree, fw)
    pins = doc_pins(tree, fw)
    docs, why = doc_text_rows(ctx, fw)
    if docs is None:
        print("doc %s: no doc rows (%s): its comments and declarations keep the marked text" % (fw, why))
    protos = doc_protocols(tree, fw)
    proto_names = sorted(protos)
    page_files = doc_page_names([("class", cls) for cls in classes] + [("protocol", name) for name in proto_names], DOC_FIXED_PAGES)
    fw_ctx = {"led6": doc_ledger_status(corpus, fw, DOC_LEDGER_6_1_3), "led43": doc_ledger_status(corpus, fw, DOC_LEDGER_4_3),
              "surf": doc_surface_rows(corpus, fw), "regs": registry_entries(tree, fw), "pins": pins,
              "oracle": doc_oracle_defaults(corpus, fw), "skipped": skipped, "superclasses": superclasses,
              "meta": objc["meta"], "objc": objc["index"], "docs": docs}
    out = os.path.join(ctx["out_root"], fw)

    index = ["# %s: worker page set" % fw, "",
             "Regenerated by `%s %s` from the committed snapshot, the ledgers and the surface table. Do not edit: regenerate." % (
                 DOC_REGENERATE, fw), "",
             "- Spec: the 26.2 header of %s, as recorded in `spec/%s/` (%d method and property rows, %d constant rows)." % (
                 fw, fw, member_count, len(constant_rows)),
             "- Status at 6.1.3: %s. A member the ledger does not list is implemented in that release. Status at 4.3: %s." % (
                 DOC_LEDGER_6_1_3, DOC_LEDGER_4_3),
             "- Demand and impl-lead: sdk-26.2-surface.tsv. Overrides and pins: `registry/%s/` and `overrides/hashes/%s.tsv`." % (fw, fw),
             "- Behaviour summaries (what a method calls, its strings, constants and error domains) and implementation pseudocode: not part"
             " of these pages; the Behaviour summary section of a class page says what produces them.",
             "- REFERENCE ONLY: nothing here is Apple binary, disassembly or pseudocode, and none of it is sent to an external service.", "",
             "## Classes (%d)" % len(classes), "",
             "| class | superclass | members | overridden | stub | page |", "| --- | --- | --- | --- | --- | --- |"]
    for cls in classes:
        members = members_by_class[cls]
        overridden, stubbed = 0, 0
        for r in members:
            if fw_ctx["regs"].get(r["api"]) is not None:
                overridden += 1
            elif r["api"] not in skipped:
                stubbed += 1
        file = page_files[("class", cls)]
        index.append("| %s | %s | %d | %d | %d | [%s](%s) |" % (cls, doc_either(superclasses.get(cls), DOC_NO_VALUE), len(members),
                                                             overridden, stubbed, file, file))
    if proto_names:
        index += ["", "## Protocols (%d)" % len(proto_names), "", "| protocol | status | members | page |", "| --- | --- | --- | --- |"]
        for name in proto_names:
            file = page_files[("protocol", name)]
            index.append("| %s | %s | %d | [%s](%s) |" % (name, protos[name]["status"], len(protos[name]["members"]), file, file))
    index += ["", "Constants: [Constants.md](Constants.md) (%d rows)." % len(constant_rows), ""]
    doc_emit(os.path.join(out, "index.md"), index)

    for cls in classes:
        doc_emit(os.path.join(out, page_files[("class", cls)]), doc_class_page(fw, cls, members_by_class[cls], fw_ctx))
    for name in proto_names:
        doc_emit(os.path.join(out, page_files[("protocol", name)]), doc_protocol_page(fw, name, protos[name], fw_ctx))

    constants = ["# %s constants" % fw, "", "| name | declaration | iOS 26.2 value | host value | 6.1.3 | 4.3 | ours |",
                 "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in doc_sorted(constant_rows, ("api",)):
        s6 = doc_either(fw_ctx["led6"].get(("constant", r["api"])), DOC_IMPLEMENTED)
        s43 = doc_either(fw_ctx["led43"].get(("constant", r["api"])), DOC_IMPLEMENTED)
        status = r["value_status"]
        value = r["value"] if (status == "found" and r["value"] is not None) else status
        owned = r["owned"] if (r["owned"] is not None and r["owned"] != DOC_NO_VALUE) else ("generated" if status == "found" else status)
        constants.append("| %s | `%s` | %s | %s | %s | %s | %s |" % (
            r["api"], DOC_DECL_NOT_DERIVED, doc_md_cell(value), doc_md_cell(r.get("host_value")), s6, s43, doc_md_cell(owned)))
    doc_emit(os.path.join(out, "Constants.md"), constants)

    swift_rows = doc_swift_rows(tree, fw)
    if swift_rows:
        page = ["# %s: Swift rows (%d)" % (fw, len(swift_rows)), "",
                "Rows of the surface in Swift, which the ObjC headers do not describe. The table describes name, kind and availability;"
                " it has no types, so no signature is shown. Overlay needs: see the list at the end.", "",
                "| kind | Swift name | introduced | unavailable | table match | demand | impl-lead |",
                "| --- | --- | --- | --- | --- | --- | --- |"]
        for row in doc_sorted(swift_rows, ("kind", "api")):
            page.append("| %s | `%s` | %s | %s | %s | %s | %s |" % (
                row["kind"], doc_md_cell(row["api"]), row["introduced"], doc_md_cell(row["unavailable"]), row["table_match"],
                doc_md_cell(row["demand_rank"]), doc_md_cell(row["impl_lead"])))
        page += ["", "## What a Swift overlay build needs that the project does not have", ""]
        page += ["- " + need for need in SWIFT_OVERLAY_NEEDS]
        doc_emit(os.path.join(out, "Swift.md"), page)

    shown = out[len(tree) + 1:] if out.startswith(tree + "/") else out
    print("doc %s: %d class pages, constants page, index -> %s" % (fw, len(classes), shown))
    return len(classes)


def cmd_doc(args):
    """`doc`: the worker's page set, written into --out (cmd_doc.lua run). For each framework: an index, one page per class, one page per
    protocol, Constants.md, and Swift.md when the Swift bucket has rows. --out and --coordination are required: nothing is written
    to a default folder."""
    if not args.coordination:
        raise SystemExit("doc needs --coordination: the corpus folder")
    if not args.sdk:
        raise SystemExit("doc needs --sdk: the iOS SDK directory")
    if not args.out:
        raise SystemExit("doc needs --out: the folder the page set is written to")
    tree = args.tree
    bucket = os.path.join(tree, OUT_ROOT, SWIFT_BUCKET)
    if not os.path.isfile(bucket):
        raise SystemExit("doc needs the Swift bucket " + bucket + ": run the swift command first (without it, the Swift pages are dropped)")
    targets = doc_frameworks(tree) if args.all else [args.framework]
    needs = {fw: doc_needs(doc_spec(tree, fw)) for fw in targets}
    objc_states = doc_read_objc(args.coordination, needs)
    ctx = {"tree": tree, "corpus": args.coordination, "sdk": args.sdk, "out_root": args.out, "binary": None, "listed": None}
    for fw in targets:
        doc_write_framework(ctx, fw, objc_states[fw])
    return 0


# ---------------------------------------------------------------- scope: every surface row, counted from the tables

# The kinds the scope counts. A surface row of any other kind is in the tie-out's total and in no state.
SCOPE_KINDS = {"class", "method", "property", "constant", "function", "enum", "struct", "typealias", "protocol"}
# The ledgers the scope counts against: the 6.1.3 release (the members it lacks are the work) and the 4.3 release.
LEDGER_6_1_3 = "ledger-w45"
LEDGER_4_3 = "ledger-w45-4.3"
# The states a generated stub answers: the trace layer's stub list is the one definition of generable.
GENERABLE_STATES = {"generable stub", "C function: generable stub (trace layer)"}
# The ledger status of a row the header parse covers with no symbol to generate; the status of a C function the trace layer stubs.
HEADER_OK = "header-ok"
GENERABLE = "generable"
# The state of a row whose framework has no declaration shard, and of a Swift row (the spec is the ObjC headers).
NO_SNAPSHOT = "no snapshot"
SWIFT_STATE = "swift: needs the Swift interface source"
# The frameworks the markdown page lists by demand.
TOP_RANKS = 60
# The selectors NSObject implies: the scope reads a bare one of them as implicit, not as a gap of the header parse (nsobject.lua).
SCOPE_IMPLICIT = {"init", "new", "copy", "mutableCopy", "dealloc", "description"}
# The decided states: a row the release answers, the registry covers, a stub, a generated constant or object, a hand implementation, or
# a recorded decision. Every other state is open, and queue_item() queues it.
DECIDED_STATES = (
    "implemented at 6.1.3", "header-only (lift)", "overridden", "generable stub", "generable constant", "numeric (not a string object)",
    "owned by a live branch", "registry decision", "not declared for iOS", "hand implementation (no registry row)",
    "class object: generated", "class object: hand code covers it", "protocol object: generated from",
    "protocol member: in the 16.4 body", "protocol member: in the transcribed protocol header", "protocol member: declared by a hand header",
    "C function: generable stub",
)
# The open states the work queue lists: the prefix of a state, the kind of work and the next step. The first prefix that matches names
# the entry; a state no entry names is still queued, by queue_item()'s fallback.
QUEUE_NEXT = (
    ("protocol member: 26.2 only", "protocol member added after the 16.4 body", "a registry decision: the protocol object is the 16.4 body, so the member needs a transcribed or hand body for it"),
    ("protocol member: not in the 26.2 facts", "protocol member with no 26.2 fact", "read the header by hand; the member's owner is not the protocol the surface names"),
    ("framework skipped by the extractor", "member of a framework the extractor skips", "a decision on the framework: read its Swift interface or its headers (the reason in the state names what is missing)"),
    ("not in the extractor's parse", "member the parse of a parsed framework does not declare", "read the framework's declaration for this member by hand (the parse holds none): decide per row"),
    ("class object: not generated", "class object with uncovered members", "cover each listed member with a stub or a registry decision, or leave the class out"),
    ("C function: exported by the 26.2 .tbd", "C function exported without a declaration", "find its declaration in the SDK (no header declares it): a decision on the name"),
    ("not stubbed: not stubbed by the trace layer", "row with no stub and no skip reason", "should be empty: a stub-layer defect"),
    ("init/new: not spelled", "init or new not spelled by the headers", "decide per class: implicit from NSObject, or unavailable by a macro"),
    ("not in the header parse (category or other)", "not in the header parse", "read the header by hand"),
    ("swift: needs the Swift interface source", "Swift row", "declaration from the .swiftinterface text, then a decision on overlay (see the Swift page)"),
    ("needs a generator: ", "a generator for the kind is missing", "write the generator for the kind (enum, struct or typealias), or decide the row by hand"),
    ("no snapshot", "framework has no committed declaration shard", "commit the framework's declaration shard (spec/<F>/declarations.tsv), or decide the framework's scope"),
    ("protocol object: ", "protocol object not generated", "read the transcriber's status for the protocol in the state, and decide the object"),
    ("protocol member: ", "protocol member not generated", "read the protocol's status in the state, and decide the member"),
    ("C function: ", "C function not generable", "read the reason in the state, and decide the name"),
    ("not stubbed: ", "row the trace layer skips", "read the skip reason in the state, and decide the row"),
    ("not generated: ", "constant not generated", "read the value status in the state, and decide the constant"),
    ("class object: not a candidate", "class row missing with no member missing", "the class has no missing member to generate: decide the class row by hand"),
    ("class object: ", "class object not generated", "read the class state, and decide the class"),
)


def table_rows(text):
    """The rows of a tab-separated table, each a dict keyed by the header's names; a cell a row lacks is None, an empty line is
    skipped (tools/gen/tsv.lua records). Nothing is quoted: a field is the text between two tabs."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    header = lines[0].split("\t") if lines else []
    rows = []
    for line in lines[1:]:
        if line:
            cells = line.split("\t")
            rows.append({name: cells[i] if i < len(cells) else None for i, name in enumerate(header)})
    return rows


def scope_surface(corpus):
    """framework -> the rows of the surface table that name it, every row the table names (a row named twice is counted twice), in the
    table's order; the frameworks come in the order the table first names them (surface.lua all_rows)."""
    rows = {}
    for row in table_rows(read(os.path.join(corpus, "sdk-26.2-surface.tsv"))):
        rows.setdefault(row["framework"], []).append(row)
    return rows


def scope_ledger(corpus, release, fw):
    """(kind, api) -> the status the framework's ledger of one release gives the row (surface.lua ledger_status). A nested framework's
    ledger is named with an underscore for its slash. A row the ledger does not list is implemented in that release."""
    path = os.path.join(corpus, release, fw.replace("/", "_") + ".tsv")
    out = {}
    if os.path.exists(path):
        for row in table_rows(read(path)):
            if row.get("kind") and row.get("api") and row.get("status") is not None:
                out[(row["kind"], row["api"])] = row["status"]
    return out


def extractor_skipped(tree):
    """framework -> the reason the extractor skips it, from its list tools/found/unparsed.tsv (coverage.lua): a comment line and an empty
    line are not entries. A missing list is an error, not an empty one."""
    path = os.path.join(tree, "tools", "found", "unparsed.tsv")
    if not os.path.exists(path):
        raise SystemExit("no extractor list of skipped frameworks at " + path)
    out = {}
    for line in read(path).split("\n"):
        if line and not line.startswith("#"):
            cells = line.split("\t")
            out[cells[0]] = cells[1] if len(cells) > 1 else ""
    return out


def spec_rows(tree, fw):
    """The spec rows of a framework: the table the generator writes into its build directory (spec.lua load)."""
    path = spec_path(tree, fw)
    if not os.path.exists(path):
        raise SystemExit("no spec table for %s at %s: run gen first" % (fw, path))
    return table_rows(read(path))


def spec_index(spec):
    """api -> the spec row: each row under its api and, for a property, under the dotted Class.name the registry uses. The first row of a
    key wins (spec.lua index)."""
    found = {}
    for r in spec:
        found.setdefault(r["api"], r)
        if r["kind"] == "property":
            found.setdefault("%s.%s" % (r["cls"], member_name(r["api"])), r)
    return found


def overridden_keys(tree, fw, members):
    """The canonical keys the framework's registry rows cover, and for a class property the key of its class accessor too (trace.lua
    overrides_of)."""
    class_props = {m["alias"]: m["api"] for m in members if m["kind"] == "property" and m["api"].startswith("+[")}
    keys = set()
    for canonical, (_, entry) in registry_entries(tree, fw).items():
        keys.add(canonical)
        if entry.get("kind") == "property" and entry.get("api") in class_props:
            keys.add(class_props[entry["api"]])
    return keys


def stub_keys_of(tree, fw, members):
    """The keys the trace layer's stubs file answers (trace_files.lua load_stub_keys), or None when the trace layer has not written it.
    A class property's stub is keyed by its class accessor, +[Cls name]; its instance form, -[Cls name], is added beside it, since the
    surface names the property by its dotted name, which keys as the instance form (scope new_context)."""
    path = os.path.join(gen_dir(tree, fw), "trace", "stubs.tsv")
    if not os.path.exists(path):
        return None
    keys = {line.split("\t")[0] for line in read(path).split("\n")[1:] if line}
    for api in {m["api"] for m in members if m["kind"] == "property" and m["api"].startswith("+[")}:
        if api in keys:
            keys.add("-" + api[1:])
    return keys


def gap_reason(api, extractor_reason):
    """Why the header parse does not hold a method or property the surface names (scope gap_reason): a bare init, new, copy, mutableCopy,
    dealloc or description is implicit from NSObject; a framework the extractor skips takes the extractor's reason; any other member is
    one the parsed framework does not declare."""
    if api.startswith(("-[", "+[")):
        sel = api[api.index(" ") + 1:-1]
    else:
        sel = api.split(".", 1)[-1]
    if sel.split(":", 1)[0] in SCOPE_IMPLICIT:
        return "init/new: not spelled by the 26.2 headers (implicit, or unavailable by a macro)"
    if extractor_reason is not None:
        return "framework skipped by the extractor: " + extractor_reason
    return "not in the extractor's parse (the framework is parsed and declares no such member)"


def protocol_member_state(owner, api, proto):
    """The state of a member of an objc protocol, by the transcriber's facts for its protocol: in the 16.4 body the protocol object is built
    from, in a transcribed header, declared by a hand header, or a gap (26.2 only, or no fact)."""
    record = proto.get(owner)
    if record is None:
        return "protocol member: protocol not in the transcriber's facts"
    kind = "property" if "." in api and not api.startswith(("-[", "+[")) else "method"
    selector = re.sub(r"\]$", "", re.sub(r"^[-+]\[%s " % re.escape(owner), "", canonical_member(api, kind), count=1))
    member = next((m for m in record["members"] if m["selector"] == selector), None)
    status = record["status"]
    if status == "sdk16 body":
        if member is None:
            return "protocol member: not in the 26.2 facts (gap)"
        if member["in16"] == "no":
            return "protocol member: 26.2 only, the 16.4 body the protocol object is built from lacks it (gap)"
        return "protocol member: in the 16.4 body (lifted protocol object)"
    if status == "transcribed":
        if member is not None:
            return "protocol member: in the transcribed protocol header"
        return "protocol member: not in the 26.2 facts (gap)"
    if status == "hand header":
        return "protocol member: declared by a hand header (no generator)"
    return "protocol member: its protocol is " + ("refused by the transcriber" if status == "refused" else "not in the 26.2 AST")


def member_state(kind, api, ctx):
    """The state of a method or property the spec holds: a stub of the trace layer, or the stub rule's reason it has none. A row the spec
    does not hold is explained by the header parse's gap reason."""
    r = ctx["spec_by_api"].get(api)
    if r is None:
        return gap_reason(api, ctx["extractor_reason"])
    key = canonical_member(api, kind)
    if ctx["stub_keys"] is not None:
        reason = None if key in ctx["stub_keys"] else (ctx["skips"].get(key) or "not stubbed by the trace layer")
    else:
        reason = ctx["skips"].get(key)
    if reason is None:
        return "generable stub"
    if reason.startswith("type not declared for iOS"):
        return "not declared for iOS"
    if reason.startswith("override or hand implementation"):
        return "hand implementation (no registry row)"
    return "not stubbed: " + reason


def constant_state(r):
    """The state of a constant, from its spec row: its owner and its value (nil when the spec holds no row for it)."""
    if r is None:
        return "not in the header parse (category or other)"
    if r["owned"] != "-":
        return "registry decision" if r["owned"].startswith("registry:") else "owned by a live branch"
    if r["value_status"] == "found" and r["tbd"] == "exported":
        return "generable constant"
    if r["value_status"] == "numeric":
        return "numeric (not a string object)"
    return "not generated: " + (r["value_status"] or "-")


def class_state(api, ctx):
    """The state of a class object, by the trace layer's decision for it (classes.tsv)."""
    decision = ctx["class_decisions"].get(api)
    if decision is None:
        return "class object: not a candidate (no missing member rows in the header parse)"
    generated, reason = decision
    if generated:
        return "class object: generated (trace layer; every member a stub)"
    if "own sources" in reason or "override" in reason:
        return "class object: hand code covers it (not generated)"
    return "class object: not generated (a member uncovered, or the superclass is not in the release)"


def function_state(api, ctx):
    """The state of a C function, by the functions snapshot."""
    record = ctx["functions"].get(api)
    if record is None:
        return "C function: not in the functions snapshot"
    if record["status"] == GENERABLE:
        return "C function: generable stub (trace layer)"
    return "C function: " + record["reasons"]


def protocol_state(api, ctx):
    """The state of a protocol object, by the transcriber's status for its protocol."""
    record = ctx["proto"].get(api)
    if record is None:
        return "protocol object: not in the transcriber's list"
    return PROTOCOL_STATES[record["status"]]


def scope_row_state(kind, api, lang, ctx):
    """The one state a surface row is in, by the tables (scope.lua row_state): the first rule that holds decides it. ctx: the facts of
    the row's framework, built by scope_framework."""
    if canonical_member(api, kind) in ctx["registry"]:
        return "overridden"
    status = ctx["led6"].get((kind, api))
    if status is None:
        return "implemented at 6.1.3: the release answers"
    if status == HEADER_OK:
        return "header-only (lift): no symbol to generate"
    if lang == "swift":
        return SWIFT_STATE
    if kind == "class":
        return class_state(api, ctx)
    if kind == "function" and lang == "objc":
        return function_state(api, ctx)
    if kind == "protocol" and lang == "objc":
        return protocol_state(api, ctx)
    if kind not in ("method", "property", "constant"):
        return "needs a generator: " + kind
    if kind in ("method", "property"):
        owner = re.match(r"[-+]\[([A-Za-z0-9_]+)", api) or re.match(r"([A-Za-z0-9_]+)\.", api)
        if owner and owner.group(1) in ctx["protocols"]:
            return protocol_member_state(owner.group(1), api, ctx["proto"])
        return member_state(kind, api, ctx)
    return constant_state(ctx["spec_by_api"].get(api))


def queue_item(state):
    """The kind of work and the next step of an open state, or None when the state is decided (scope.lua queue_item). A state no queue
    entry names is still queued, with a fallback entry."""
    if any(state.startswith(decided) for decided in DECIDED_STATES):
        return None
    for prefix, work, step in QUEUE_NEXT:
        if state.startswith(prefix):
            return work, step
    return "open state, no queue entry names it", "decide the row by hand: the state names what is missing"


def canonical_member(api, kind):
    """The key a member has in the trace layer's stub list: a property written 'Class.name' is '-[Class name]'."""
    if kind == "property" and not api.startswith(("-[", "+[")) and "." in api:
        return "-[%s %s]" % tuple(api.split(".", 1))
    return api


def number_of(value):
    """The integer a demand-apps cell names: 0 for an empty or missing cell."""
    return 0 if value in (None, "") else int(value)


def reconcile(tally):
    """The rows the scope calls generable against the stubs the trace layer wrote (scope.lua reconcile): the lines of the file (its header
    first), the number of generable rows, of stubs, of rows both share, the number of differences, and of those marked should be empty
    (a generable row with no stub: the run fails on those)."""
    lines = ["framework\tapi\treason"]
    generable_total = stubbed_total = both = marked = 0
    for fw in sorted(set(tally["generable"]) | {fw for fw, _ in tally["counts"]}):
        stubs = tally["stub_sets"].get(fw, set())
        gen = tally["generable"].get(fw, set())
        stubbed_total += len(stubs)
        generable_total += len(gen)
        both += len(stubs & gen)
        for api in sorted(stubs - gen):
            lines.append("%s\t%s\ttrace stub that answers no surface row (spec-only member, or a class the surface does not list)" % (fw, api))
        for api in sorted(gen - stubs):
            lines.append("%s\t%s\tsurface row the scope calls generable with no trace stub (should be empty: one definition)" % (fw, api))
            marked += 1
    return lines, generable_total, stubbed_total, both, len(lines) - 1, marked


def scope_framework(args, fw, rows, shared, skipped, tally):
    """Counts the rows of one framework into the tally: the facts its rows are stated by (scope.lua new_context), then the state of each
    row and its count (scope.lua scope_rows). shared: the tree's typedef index, declared names and hand implementations. skipped:
    framework -> the extractor's reason for skipping it."""
    tree = args.tree
    members = shard_members(tree, fw)
    snap = os.path.isfile(shard_path(tree, fw))
    led6 = scope_ledger(args.coordination, LEDGER_6_1_3, fw)
    led43 = scope_ledger(args.coordination, LEDGER_4_3, fw)
    stub_keys = stub_keys_of(tree, fw, members)
    tally["stub_sets"][fw] = stub_keys or set()
    registry = overridden_keys(tree, fw, members)
    ctx = {"led6": led6, "registry": registry, "stub_keys": stub_keys, "extractor_reason": skipped.get(fw),
           "protocols": {r["api"] for r in rows if r["kind"] == "protocol" and r.get("lang") == "objc"},
           "spec_by_api": {}, "functions": {}, "class_decisions": {}, "proto": {}, "skips": {}}
    if snap:
        spec = spec_rows(tree, fw)
        ctx["spec_by_api"] = spec_index(spec)
        ctx["proto"] = load_protocols(tree, fw)
        ctx["protocols"] |= set(ctx["proto"])
        ctx["functions"] = load_functions(tree, fw)
        ctx["class_decisions"] = load_class_decisions(tree, fw)
        if any(r["kind"] in ("method", "property") for r in spec):
            by_api = {}
            for m in members:
                by_api.setdefault(m["api"], m)
            env = {"members": by_api, "index": shared["index"], "declared": shared["declared"], "hand": shared["hand"],
                   "overridden": registry, "release_missing": led6 or None}
            ctx["skips"] = dict(stub_skips(spec, env))
    for row in rows:
        kind = row["kind"]
        if kind not in SCOPE_KINDS:
            continue
        api = row["api"]
        lang = row.get("lang")
        if lang is None:
            lang = "objc"
        state = scope_row_state(kind, api, lang, ctx) if snap else NO_SNAPSHOT
        count = tally["counts"].setdefault((fw, kind), {"surface": 0, "demand_rows": 0, "demand_apps": 0, "missing_6_1_3": 0,
                                                       "missing_4_3": 0, "states": {}})
        count["surface"] += 1
        rank = row.get("demand-rank")
        ranked = rank is not None and rank != ""
        if ranked:
            count["demand_rows"] += 1
            count["demand_apps"] += number_of(row.get("demand-apps"))
        if led6.get((kind, api)) is not None:
            count["missing_6_1_3"] += 1
        if led43.get((kind, api)) is not None:
            count["missing_4_3"] += 1
        count["states"][state] = count["states"].get(state, 0) + 1
        if state in GENERABLE_STATES:
            tally["generable"].setdefault(fw, set()).add(canonical_member(api, kind))
        work = queue_item(state)
        if work:
            apps = row.get("demand-apps") or "0"
            tally["queued"].append({"fw": fw, "kind": kind, "api": api, "state": state, "work": work[0], "step": work[1],
                                    "unranked": not ranked, "rank": int(rank) if ranked else 0, "apps": int(apps),
                                    "rank_text": rank if ranked else "-", "apps_text": apps, "seq": len(tally["queued"]) + 1})


def cmd_scope(args):
    """The scope of the surface (scope.lua run): one row per framework and kind, the state of each row, the work queue by demand, and the
    reconciliation of the generable rows with the trace layer's stubs. Writes four files into --out and prints the tie-out. Returns 1 when
    the tie-out does not tie or a reconcile difference is marked should be empty, else 0; the four files are written either way."""
    if not (args.sdk and args.coordination and args.out):
        raise SystemExit("scope needs --sdk (the iOS SDK directory), --coordination (the corpus folder) and --out (the folder to write)")
    out = args.out
    by_fw = scope_surface(args.coordination)
    shared = {"index": typedef_index(args.tree), "declared": declared_names(args.tree), "hand": hand_implementations(args.tree)}
    skipped = extractor_skipped(args.tree)
    tally = {"counts": {}, "generable": {}, "queued": [], "stub_sets": {}}
    for fw, rows in by_fw.items():
        scope_framework(args, fw, rows, shared, skipped, tally)
    surface_total = sum(len(rows) for rows in by_fw.values())

    reconcile_lines, generable_total, stubbed_total, both, differences, marked = reconcile(tally)
    write(os.path.join(out, "v-gen-reconcile.tsv"), ("\n".join(reconcile_lines) + "\n").encode("ascii", "backslashreplace").decode("ascii"))
    print("reconcile: %d generable rows, %d stubs, %d in both, %d differences (%d marked should be empty) -> v-gen-reconcile.tsv"
          % (generable_total, stubbed_total, both, differences, marked))

    lines = ["framework\tkind\tsurface_rows\tdemand_rows\tdemand_apps\tmissing_6_1_3\tmissing_4_3\tstates"]
    queue_total, surface_of = {}, {}
    for fw, kind in sorted(tally["counts"]):
        c = tally["counts"][(fw, kind)]
        states = "; ".join("%s=%d" % (state, c["states"][state]) for state in sorted(c["states"]))
        lines.append("\t".join([fw, kind, str(c["surface"]), str(c["demand_rows"]), str(c["demand_apps"]),
                                str(c["missing_6_1_3"]), str(c["missing_4_3"]), states]))
        queue_total[fw] = queue_total.get(fw, 0) + c["demand_apps"]
        surface_of[fw] = surface_of.get(fw, 0) + c["surface"]
    write(os.path.join(out, "v-gen-scope.tsv"), "\n".join(lines) + "\n")
    by_demand = sorted(queue_total, key=lambda fw: (-queue_total[fw], fw))

    md = ["# v-gen scope: every surface row, counted from the tables", "",
          "Generated by `tools/gen.py scope` from sdk-26.2-surface.tsv, the ledgers (6.1.3 and 4.3), the registry, and the spec snapshots.",
          "", "Work queue by demand (apps that call the framework's rows, summed):", "",
          "| rank | framework | demand apps | surface rows |", "| --- | --- | --- | --- |"]
    md += ["| %d | %s | %d | %d |" % (i, fw, queue_total[fw], surface_of[fw]) for i, fw in enumerate(by_demand[:TOP_RANKS], 1)]
    totals = {}
    for c in tally["counts"].values():
        for state, n in c["states"].items():
            totals[state] = totals.get(state, 0) + n
    md += ["", "State totals over every surface row (each row has exactly one state):", "", "| state | rows |", "| --- | --- |"]
    md += ["| %s | %d |" % (state, n) for state, n in sorted(totals.items(), key=lambda kv: -kv[1])]

    queued = sorted(tally["queued"], key=lambda q: (q["unranked"], q["rank"], -q["apps"], q["fw"], q["api"], q["seq"]))
    queue_lines = ["framework\tkind\tapi\tstate\twork\tnext_step\tdemand_rank\tdemand_apps"]
    queue_lines += ["\t".join([q["fw"], q["kind"], q["api"], q["state"], q["work"], q["step"], q["rank_text"], q["apps_text"]])
                    for q in queued]
    write(os.path.join(out, "v-gen-queue.tsv"), ("\n".join(queue_lines) + "\n").encode("ascii", "backslashreplace").decode("ascii"))
    works = {}
    for q in queued:
        works[q["work"]] = works.get(q["work"], 0) + 1
    for work in sorted(works):
        print("queue: %6d  %s" % (works[work], work))

    tied = sum(totals.values())
    verdict = "tie" if tied == surface_total else "DO NOT TIE"
    md += ["", "Tie-out: %d surface rows, %d rows in the state totals: %s." % (surface_total, tied, verdict)]
    write(os.path.join(out, "v-gen-scope.md"), "\n".join(md) + "\n")
    print("tie-out: %d surface rows, %d in state totals" % (surface_total, tied))
    print("scope: %d framework-kind rows, %d frameworks -> %s"
          % (len(tally["counts"]), len(by_demand), os.path.join(out, "v-gen-scope.tsv")))
    status = 0
    if tied != surface_total:
        print("scope: DO NOT TIE: %d surface rows, %d rows in the state totals" % (surface_total, tied))
        status = 1
    if marked:
        print("scope: %d reconcile difference(s) marked should be empty, see v-gen-reconcile.tsv" % marked)
        status = 1
    return status


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
OBJC_PARTS = ("objc-26.2-part1.tsv.gz", "objc-26.2-part2.tsv.gz", "objc-26.2-part3.tsv.gz")
OBJC_EXTRACT = os.path.join(".agent-work", "objc-26.2")
OBJC_ENTITIES = ("class", "method", "property")


def objc_table_lines():
    """The lines of the objc table: its gzip parts in order, the header line once. The parts repeat the header, and a part whose
    header differs is refused; tools/gen/objc.lua reads the same parts the same way."""
    header = None
    for part in OBJC_PARTS:
        with gzip.open(os.path.join(LEDGER_DIR, "cache-26.2", part), "rt", encoding="utf-8", errors="replace") as table:
            first = table.readline()
            if header is None:
                header = first
                yield first
            assert first == header, "objc table part %s has another header" % part
            yield from table


def cmd_objc_extract(args):
    """Write one extract per framework of the table's class, method and property rows (fields: entity, owner, section (instance or
    class), name, decl, types, address, superclass, protocols, category)."""
    out_dir = os.path.join(args.tree, OBJC_EXTRACT)
    os.makedirs(out_dir, exist_ok=True)
    handles, counts = {}, {}
    table = objc_table_lines()
    header = next(table).rstrip("\n").split("\t")
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
    parser.add_argument("--out", help="doc: where the page set is written (required); scope: the folder the four files go to")
    parser.add_argument("--coordination", help="scope: the corpus folder (the surface table and the ledgers)")
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
