#!/usr/bin/env python3
"""The contract check for UIDocumentBrowserViewControllerDelegate.

The port's declaration is a transcription of the 26.2 header, and a transcription is worth nothing
without something to check it against. Both sides are read the same way, and neither reading does any
line arithmetic:

  * the **selector set** from clang's JSON AST, keyed by `mangledName`, which is the selector with
    its trailing colon and needs no parsing;
  * the **required/optional split** from the compiler. An empty conformer compiled with -Wprotocol is
    warned about for every @required method the protocol declares and for none of the @optional ones,
    so the set of selectors those warnings name *is* the required set and the AST's set minus it is
    the optional one. Clang already knows and says; this only listens.

The two sides differ only in the translation unit, and that difference is the whole reason this works
at all: the header's imports UIKit, and the port's imports Foundation and the port's own headers.
With the umbrella in the port's unit the SDK's declaration of this protocol shadows the port's and the
compiler reads only the SDK's copy -- the port's transcription checked against itself, which is not a
check.

An independent count of the port file's `- (` lines must agree with the AST on the port's side, and a
disagreement fails rather than passing one of the two quietly.

Two controls, both on named scratch copies under .agent-work/runs/documentbrowser/, and both
required to fail: one @optional flipped to @required, which makes the warning appear and names the
selector; and one declaration removed, which takes the selector out of the AST set and names it.

    DDR_ROOT=<the checkout> python3 tests/backports/host/documentbrowser/ast_check.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("DDR_ROOT") or os.path.abspath(
    os.path.join(HERE, os.pardir, os.pardir, os.pardir, os.pardir))
RUNS = os.path.join(ROOT, ".agent-work", "runs", "documentbrowser")
SDK = os.environ.get("SDK", os.path.join(ROOT, os.pardir, os.pardir, "sdk-26.2", "iPhoneOS26.2.sdk"))
UIKIT_HEADERS = os.path.join(SDK, "System/Library/Frameworks/UIKit.framework/Headers")

PROTOCOL = "UIDocumentBrowserViewControllerDelegate"
TARGET = "arm64-apple-ios13.0"
SDK_HEADER = os.path.join(UIKIT_HEADERS, "UIDocumentBrowserViewController.h")
PORT_DIR = os.path.join(ROOT, "packages/a/apple-backports/UIKit")
PORT_HEADER = os.path.join(PORT_DIR, "UIDocumentBrowserViewControllerDelegate.h")
PORT_TYPES = os.path.join(PORT_DIR, "CharonDocumentBrowserTypes.h")

METHOD_START = re.compile(r"^\s*[-+]\s*\(")
REQUIRED_WARNING = re.compile(
    r"method '([^']+)' in protocol '%s' not implemented" % PROTOCOL)

CONFORMER = '''#import <Foundation/Foundation.h>
#import "%(types)s"
#import "%(header)s"
@interface CheckConformer : NSObject <%(protocol)s>
@end
@implementation CheckConformer
@end
'''

SDK_CONFORMER = '''#import <UIKit/UIKit.h>
@interface CheckConformer : NSObject <%(protocol)s>
@end
@implementation CheckConformer
@end
'''


def _tu(header, port):
    """The translation unit the compiler reads, which is the only difference between the two sides."""
    folder = tempfile.mkdtemp()
    source = os.path.join(folder, "tu.m")
    if port:
        open(source, "w").write(CONFORMER % {
            "types": PORT_TYPES, "header": header, "protocol": PROTOCOL})
    else:
        open(source, "w").write(SDK_CONFORMER % {"protocol": PROTOCOL})
    return source


def _clang(source, extra=()):
    return subprocess.run(
        ["xcrun", "clang", "-fsyntax-only", "-fobjc-arc", "-target", TARGET, "-isysroot", SDK,
         "-I", UIKIT_HEADERS, "-I", PORT_DIR, *extra,
         "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter=%s" % PROTOCOL, source],
        capture_output=True, text=True)


def ast_selectors(header, port):
    """Every selector the protocol declares, by mangledName, which is the selector itself."""
    result = _clang(_tu(header, port))
    if result.returncode != 0:
        raise SystemExit("clang failed for %s: %s" % (header, result.stderr[:400]))
    decoder = json.JSONDecoder()
    documents, index, raw = [], 0, result.stdout
    while index < len(raw):
        while index < len(raw) and raw[index] in " \n\t\r":
            index += 1
        if index >= len(raw):
            break
        document, index = decoder.raw_decode(raw, index)
        documents.append(document)
    found = set()

    def walk(node):
        if node.get("kind") in ("ObjCMethodDecl", "ObjCInstanceMethodDecl"):
            if "[%s " % PROTOCOL in node.get("mangledName", ""):
                found.add(node.get("name") or node["mangledName"])
        for child in node.get("inner", []):
            walk(child)

    for document in documents:
        walk(document)
    return found


def required_selectors(header, port):
    """The @required selectors, from the compiler's -Wprotocol warnings on an empty conformer."""
    source = _tu(header, port)
    result = subprocess.run(
        ["xcrun", "clang", "-fsyntax-only", "-fobjc-arc", "-Wprotocol", "-target", TARGET,
         "-isysroot", SDK, "-I", UIKIT_HEADERS, "-I", PORT_DIR, source],
        capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("the conformer did not compile: %s" % result.stderr[:400])
    return set(REQUIRED_WARNING.findall(result.stderr))


def raw_count(path):
    """The independent reader: a plain count of the `- (` lines inside the protocol."""
    inside, count = False, 0
    for line in open(path, errors="replace"):
        stripped = line.strip()
        if stripped.startswith("@protocol %s" % PROTOCOL):
            inside = True
            continue
        if inside and stripped.startswith("@end"):
            break
        if inside and METHOD_START.match(line):
            count += 1
    return count


def side(header, port):
    """One side of the contract: every selector, and which of them are required."""
    selectors = ast_selectors(header, port)
    required = required_selectors(header, port)
    return {selector: ("required" if selector in required else "optional")
            for selector in selectors}


def main():
    os.makedirs(RUNS, exist_ok=True)
    header = side(SDK_HEADER, False)
    port = side(PORT_HEADER, True)
    counted = raw_count(PORT_HEADER)
    print("%s: header %d selectors, port %d" % (PROTOCOL, len(header), len(port)))
    print("  required: header %d, port %d" % (
        sum(1 for v in header.values() if v == "required"),
        sum(1 for v in port.values() if v == "required")))
    print("  the independent count of the port's method lines: %d" % counted)

    problems = []
    if len(port) != counted:
        problems.append("the AST and the count disagree on the port's file: %d and %d"
                        % (len(port), counted))
    for selector in sorted(set(header) - set(port)):
        problems.append("the port does not declare %s, which the header declares" % selector)
    for selector in sorted(set(port) - set(header)):
        problems.append("the port declares %s, which the header does not" % selector)
    for selector in sorted(set(header) & set(port)):
        if header[selector] != port[selector]:
            problems.append("%s is %s in the header and %s in the port"
                            % (selector, header[selector], port[selector]))
    if problems:
        for problem in problems:
            print("FAIL: " + problem)
        return 1

    # Control one: one @optional flipped to @required in a scratch copy of the port's header.
    text = open(PORT_HEADER, errors="replace").read()
    control = os.path.join(RUNS, "control-optionality.h")
    open(control, "w").write(text.replace("@optional", "@required", 1))
    flipped = side(control, True)
    caught = [s for s in flipped if header.get(s) != flipped.get(s)]
    if not caught:
        print("FAIL: the control flipped an @optional and the check did not notice")
        return 1
    print("  control, @optional flipped: %s is now %s" % (caught[0], flipped[caught[0]]))

    # Control two: one declaration removed, which must leave the AST set and be named.
    victim = sorted(port)[0]
    lines = open(PORT_HEADER, errors="replace").read().split("\n")
    keywords = victim.split(":")[:-1]
    unique = [k for k in keywords if k != "documentBrowser"] or keywords
    index = next(i for i, line in enumerate(lines)
                 if METHOD_START.match(line) and re.search(r"\b%s\s*:" % re.escape(unique[0]), line))
    end = index
    while ";" not in lines[end] and end + 1 < len(lines):
        end += 1
    del lines[index:end + 1]
    dropped = os.path.join(RUNS, "control-missing.h")
    open(dropped, "w").write("\n".join(lines))
    gone = side(dropped, True)
    if victim in gone:
        print("FAIL: the control removed %s and the AST still has it" % victim)
        return 1
    if len(gone) != len(port) - 1:
        print("FAIL: the control removed %s and %d selectors are left, not %d"
              % (victim, len(gone), len(port) - 1))
        return 1
    print("  control, %s removed: the AST went %d -> %d and named it"
          % (victim, len(port), len(gone)))

    print("PASS: the port's declaration is the header's, selectors and optionality")
    return 0


if __name__ == "__main__":
    sys.exit(main())
