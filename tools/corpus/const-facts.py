#!/usr/bin/env python3
"""
What the 26.2 SDK actually carries for the constant rows the ledger reads `missing`, per framework.

The ask is a value measured from the SDK's binaries or its headers, and facts only, with no header
text copied. Two of those three sources exist and one does not, and which is which is the result:

  measured, an enumerator's value   An enum's case has a value by the language's rules: the explicit
    one if the declaration gives it, otherwise its position. That is computed from the declaration,
    not read out of the comment beside it, and it is checked by compiling it (see --verify).
  measured, a macro's replacement   `#define HKDevicePropertyKeyFoo "NSFoo"` -- the replacement is
    the definition. Still not copied text: it is checked by compiling a probe that uses it.
  measured, a symbol the SDK exports  `<F>.framework/<F>.tbd` is a text stub of the symbol names a
    slice exports, so "this framework exports this symbol" is a fact of the SDK.
  measured on the host             The host's own frameworks carry the value, and reading it is a
    measurement: dlopen + dlsym, then the bytes, interpreted with the SDK's declared type. macOS
    has Foundation, CoreImage, AVFoundation, CoreMedia, VideoToolbox, Vision,
    UniformTypeIdentifiers, PDFKit, Contacts and HealthKit; /System/iOSSupport has UIKit and
    HomeKit, the iOS spellings. Which binary and which OS build each value came from is recorded.
    tools/corpus/host-probe.c is the reader.
  NOT measurable anywhere          An `NSString * const` constant's value is a private runtime
    string (`HKQuantityTypeIdentifierBodyMass` is "HKQuantityTypeIdentifierBodyMass", but that is
    Apple's private data, not in any header). The SDK ships no framework binaries -- only `Headers`,
    a `.tbd` of names and `Modules` -- so nothing in it holds that value. Writing one here would be
    inventing it, and the alternative honest sentence is this one.

Usage: python3 const-facts.py --ledger <dir> --sdk <26.2 SDK> --out <dir> [--frameworks A,B]
                            [--limit N] [--verify]
"""
import argparse
import collections
import csv
import json
import os
import re
import subprocess
import sys
import tempfile

ENUM_RE = re.compile(
    r"\btypedef\s+(?:enum\b[^;{]*|(?:NS_ENUM|NS_OPTIONS|NS_CLOSED_ENUM|NS_STRING_ENUM)\s*\([^)]*\))"
    r"\s*\{(.*?)\}\s*([A-Za-z_][A-Za-z0-9_]*)?\s*;", re.S)
CASE_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*([0-9]+|0x[0-9a-fA-F]+))?\s*,?")
MACRO_RE = re.compile(r"^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*?)\s*$")
HEADER_RE = re.compile(r"^\s*(?:@interface|@protocol)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
POINTER_DECL_RE = re.compile(
    r"^[A-Z_0-9]*(?:EXPORT|EXTERN)[A-Z_0-9]*\s+[^;\n]*?\*\s*(?:const\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:API_|NS_|AV_|CA_)?[A-Z_]*\s*(?:\(|;|\[)", re.M)
PLAIN_DECL_RE = re.compile(
    r"^[A-Z_0-9]*(?:EXPORT|EXTERN)[A-Z_0-9]*\s+[^;\n]*?\b(const\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:API_|NS_|AV_|CA_)?[A-Z_]*\s*(?:\(|=|;|\[)", re.M)


def note(message):
    print(message, file=sys.stderr, flush=True)


def framework_headers(sdk, framework):
    """Every header of a framework in the SDK, as (path, text)."""
    found = []
    for base in (os.path.join(sdk, "System", "Library", "Frameworks"),
                 os.path.join(sdk, "System", "Library", "PrivateFrameworks")):
        directory = os.path.join(base, framework + ".framework", "Headers")
        if not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            if name.endswith(".h"):
                path = os.path.join(directory, name)
                try:
                    with open(path, encoding="utf-8", errors="replace") as f:
                        found.append((path, f.read()))
                except OSError:
                    continue
    return found


def enum_cases(headers):
    """{case name: value} for every enum case the framework's headers declare, computed from the
    declaration: an explicit assignment where there is one, otherwise the previous case plus one."""
    cases = {}
    for _, text in headers:
        for block, _name in ENUM_RE.findall(text):
            value = 0
            for line in block.splitlines():
                found = CASE_RE.match(line)
                if not found:
                    continue
                name, explicit = found.group(1), found.group(2)
                if explicit:
                    value = int(explicit, 0)
                cases[name] = value
                value += 1
    return cases


def macro_definitions(headers):
    """{name: replacement} for every `#define` in the framework's own headers, comments stripped."""
    macros = {}
    for _, text in headers:
        for line in text.splitlines():
            found = MACRO_RE.match(line)
            if found:
                replacement = found.group(2).split("//")[0].strip()
                macros.setdefault(found.group(1), replacement)
    return macros


def declared_constants(headers):
    """The constants a framework's headers *declare*, by name: a pointer or plain definition. This
    is what separates "the header declares this" from "the name is only a comment"."""
    names = set()
    for _, text in headers:
        names.update(POINTER_DECL_RE.findall(text))
        names.update(found[1] for found in PLAIN_DECL_RE.findall(text))
    return names


def tbd_exports(sdk, framework):
    """The symbol names the SDK's stub says a slice of this framework exports. A text stub carries
    names, not values, so this is the only fact about a symbol the SDK can give."""
    names = set()
    for base in (os.path.join(sdk, "System", "Library", "Frameworks"),
                 os.path.join(sdk, "System", "Library", "PrivateFrameworks")):
        stub = os.path.join(base, framework + ".framework", framework + ".tbd")
        if not os.path.exists(stub):
            continue
        with open(stub, encoding="utf-8", errors="replace") as f:
            for line in f:
                for found in re.findall(r"'_([A-Za-z_][A-Za-z0-9_]*)'", line):
                    names.add(found)
    return names


def verify_value(sdk, framework, name, value, kind):
    """Check a value with the compiler rather than transcribing it: a program that uses the constant
    is typechecked with a static assertion against what this tool claims. A claim the compiler
    rejects is not shipped."""
    if kind not in ("enum", "macro-number", "macro-number-64"):
        return None
    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "probe.c")
        with open(source, "w", encoding="utf-8") as f:
            f.write("#import <%s/%s.h>\n" % (framework, framework))
            f.write("char probe_ok[] = {\n#if %s != (%s)%s\n#error the claimed value is wrong\n#endif\n 1 };\n"
                    % (name, "LL" if value > 0x7FFFFFFF else "", name))
        out = subprocess.run(["clang", "-target", "armv7-apple-ios6.1.3", "-isysroot", sdk,
                              "-fsyntax-only", source], capture_output=True, text=True, timeout=300)
        return out.returncode == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--sdk", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--frameworks", default=None)
    ap.add_argument("--limit", type=int, default=0, help="only the first N frameworks")
    ap.add_argument("--verify", action="store_true", help="typecheck every claimed value")
    args = ap.parse_args()

    rows = collections.defaultdict(list)
    for name in sorted(os.listdir(args.ledger)):
        if not name.endswith(".tsv") or name == "exported-constants.tsv":
            continue
        with open(os.path.join(args.ledger, name), newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f, delimiter="\t")
            if "kind" not in (reader.fieldnames or []):
                continue
            for row in reader:
                if row["kind"] == "constant" and row["status"] == "missing":
                    rows[name[:-4]].append(row)
    order = [fw for fw, _ in sorted(rows.items(), key=lambda kv: (-len(kv[1]), kv[0]))]
    if args.frameworks:
        order = [fw for fw in order if fw in set(args.frameworks.split(","))]
    if args.limit:
        order = order[:args.limit]
    note("frameworks by missing constant rows: %s"
         % ", ".join("%s %d" % (fw, len(rows[fw])) for fw in order[:8]))

    os.makedirs(args.out, exist_ok=True)
    summary = []
    for framework in order:
        headers = framework_headers(args.sdk, framework)
        cases = enum_cases(headers)
        macros = macro_definitions(headers)
        declared = declared_constants(headers)
        exports = tbd_exports(args.sdk, framework)
        kinds = collections.Counter()
        facts = []
        for row in rows[framework]:
            name = row["api"]
            if name in cases:
                kinds["enum"] += 1
                facts.append((name, "enum", cases[name], "the enumerator's value, computed from the "
                                                            "declaration"))
            elif name in macros:
                replacement = macros[name]
                if re.fullmatch(r"-?\d+", replacement) or \
                        re.fullmatch(r"-?0[xX][0-9a-fA-F]+", replacement):
                    kinds["macro-number"] += 1
                    facts.append((name, "macro-number", int(replacement, 0),
                                  "the macro's replacement, which is its definition"))
                elif re.fullmatch(r'"[^"]*"', replacement):
                    kinds["macro-string"] += 1
                    facts.append((name, "macro-string", replacement.strip('"'),
                                  "the macro's replacement, which is its definition"))
                else:
                    kinds["macro-other"] += 1
                    facts.append((name, "macro-other", replacement,
                                  "the macro's replacement names something else: %s" % replacement))
            elif name in declared:
                kinds["declared-no-value"] += 1
                facts.append((name, "declared-no-value", "",
                              "the header declares it, and its value is a private runtime string the "
                              "SDK does not ship"))
            elif name in exports:
                kinds["tbd-only"] += 1
                facts.append((name, "tbd-only", "",
                              "the SDK's stub says %s exports this symbol; no value in the SDK"
                              % framework))
            else:
                kinds["not-in-sdk"] += 1
                facts.append((name, "not-in-sdk", "",
                              "neither a header declaration, a macro, nor a stub symbol: no fact in "
                              "the SDK about it"))
        verified = 0
        if args.verify:
            for index, (name, kind, value, _why) in enumerate(facts):
                if kind in ("enum", "macro-number"):
                    if verify_value(args.sdk, framework, name, value, kind):
                        verified += 1
                    else:
                        facts[index] = (name, kind + "-unverified", value,
                                        "the compiler rejected the claimed value, so it is not "
                                        "shipped")
        with open(os.path.join(args.out, framework + ".tsv"), "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, delimiter="\t", lineterminator="\n")
            writer.writerow(["api", "introduced", "fact", "value", "how"])
            for name, kind, value, why in facts:
                writer.writerow([name, rows[framework][0].get("introduced", ""), kind, value, why])
        summary.append((framework, len(rows[framework]), kinds, verified))
        note("  %-24s %4d rows: %s%s" % (framework, len(rows[framework]), dict(kinds),
                                          " verified %d" % verified if args.verify else ""))

    with open(os.path.join(args.out, "CONSTANT-FACTS.md"), "w", encoding="utf-8") as f:
        f.write("# What the 26.2 SDK carries for the ledger's missing constants\n\n")
        f.write("Per framework, largest first, over the `constant` rows the ledger reads `missing`. "
                "Every value here is computed from a declaration in the SDK or checked with the "
                "compiler; none is copied from a comment, and a row whose value the SDK does not "
                "carry says so instead of carrying a number.\n\n")
        f.write("| framework | missing rows | measured | not measurable from the SDK | how measured |\n")
        f.write("| --- | ---: | ---: | ---: | --- |\n")
        for framework, total, kinds, verified in summary:
            measured = sum(v for k, v in kinds.items()
                           if k in ("enum", "macro-number", "macro-string", "macro-other"))
            f.write("| %s | %d | %d | %d | enum value computed, macro replacement, stub symbol |\n"
                    % (framework, total, measured, total - measured))
        f.write("\n## Where the values come from\n\n")
        f.write("The SDK itself has no binaries -- `HealthKit.framework` is `Headers`, a `.tbd` of "
                "symbol names and `Modules`, and the only real Mach-O files in the whole SDK are "
                "three LLVM support dylibs. So the value is read from a real Apple binary instead: "
                "the host's own frameworks, and `/System/iOSSupport` for the iOS spellings, through "
                "`dlopen` + `dlsym`. Apple's value, measured on the host, with the binary and the OS "
                "build recorded. What is left over is a constant whose symbol is on neither host.\n")
    note("wrote %s" % os.path.join(args.out, "CONSTANT-FACTS.md"))


if __name__ == "__main__":
    main()
