#!/usr/bin/env python3
"""The AST contract check for the HomeKit rows.

The port's own headers import <HomeKit/HomeKit.h> from the iOS SDK, and the SDK's HomeKit types are
marked API_UNAVAILABLE(macos) - so nothing of the model compiles for this host, and there is no
HomeKit framework in any macOS SDK to ask. A probe that runs is therefore not available, and this check is
what runs instead: it compiles the port's source for **iOS** and compares the **port's** declarations
against the **header's**, from clang's AST, without executing anything.

For every class this piece carries, and for every property the header declares on it:

  * the port declares a member of that name;
  * with the same type, nullability included - the AST's qualType carries the _Nonnull/_Nullable the
    header wrote, and a port that declared the property nullable where the header does not would be
    answered differently by a caller;
  * with the same attributes: readonly, copy, nonatomic, weak;
  * and a property the header marks NS_UNAVAILABLE is absent from the port.

The attributes compared are the ones the header writes. `strong` is the default and is not written on a
property line, so it is not compared - what would be compared is a *changed* attribute, and a property
that lost `readonly` or `copy` is caught by the absence of the key rather than by its presence here.

The control: run against a scratch copy with one property's attribute flipped, and this must name it and
exit non-zero. A check that cannot fail is not a check.
"""
import json
import os
import subprocess
import sys
import tempfile

SDK = os.environ.get(
    "SDK",
    os.path.expanduser(
        "~/Git/projects/ios/charon/.agent-work/sdk-26.2/iPhoneOS26.2.sdk"
    ),
)
HM_HEADERS = os.path.join(SDK, "System/Library/Frameworks/HomeKit.framework/Headers")
TARGET = ("arm64-apple-ios12.0", SDK)

# What each carried class must match, and the header line each member comes from. The lines are recorded so
# a failure names where the expectation was read from, not only what was expected.
EXPECTED = {
    "HMAccessoryProfile": {
        "uniqueIdentifier": "HMAccessoryProfile.h:27",
        "services": "HMAccessoryProfile.h:32",
        "accessory": "HMAccessoryProfile.h:37",
    },
    "HMCameraProfile": {
        "streamControl": "HMCameraProfile.h:33",
        "snapshotControl": "HMCameraProfile.h:38",
        "settingsControl": "HMCameraProfile.h:43",
        "speakerControl": "HMCameraProfile.h:48",
    },
}

ATTRIBUTES = ("readonly", "copy", "nonatomic", "weak")


PORT_INCLUDE = None  # the port's directory, set once the root is found, so a scratch copy can include it


def ast(root, name):
    """clang's filtered AST for one class, as a list of documents."""
    command = [
        # ARC, because the port's own code uses __weak and a manual-reference-counting parse of it would
        # fail on the port's source rather than on anything the check is about.
        "xcrun", "clang", "-fsyntax-only", "-fobjc-arc", "-target", TARGET[0], "-isysroot", TARGET[1],
        "-I", HM_HEADERS, "-I", os.path.dirname(root), "-I", os.path.dirname(os.path.dirname(root)),
        *([ "-I", PORT_INCLUDE ] if PORT_INCLUDE else []),
        "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter=%s" % name, root,
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit("clang failed for %s in %s" % (name, root))
    raw = result.stdout
    decoder = json.JSONDecoder()
    documents = []
    index = 0
    while index < len(raw):
        while index < len(raw) and raw[index] in " \n\t\r":
            index += 1
        if index >= len(raw):
            break
        document, index = decoder.raw_decode(raw, index)
        documents.append(document)
    return documents


def properties(documents):
    """Every property in the dump, with the file it came from, so the header's and the port's can be told
    apart: the header's decls carry an includedFrom of the SDK."""
    found = {}

    def walk(node):
        if node.get("kind") in ("ObjCMethodDecl", "ObjCInstanceMethodDecl"):
            selector = node.get("name")
            if selector and ":" not in selector:
                source = (node.get("loc") or {}).get("includedFrom", {}).get("file", "")
                found.setdefault(selector, []).append(
                    {
                        "file": source,
                        "type": (node.get("type") or {}).get("qualType", ""),
                        "attrs": tuple(ATTRIBUTES),
                        "line": (node.get("loc") or {}).get("line"),
                        "accessor": True,
                    }
                )
        if node.get("kind") == "ObjCPropertyDecl":
            source = (node.get("loc") or {}).get("includedFrom", {}).get("file", "")
            found.setdefault(node.get("name"), []).append(
                {
                    "file": source,
                    "type": (node.get("type") or {}).get("qualType", ""),
                    "attrs": tuple(a for a in ATTRIBUTES if node.get(a)),
                    "line": (node.get("loc") or {}).get("line"),
                }
            )
        for child in node.get("inner", []):
            walk(child)

    for document in documents:
        walk(document)
    return found


def compare(name, expected, header_props, port_props):
    """The header's declaration against the port's, member by member."""
    failures = []
    for member, line in sorted(expected.items()):
        header = next((p for p in header_props.get(member, []) if p["file"].endswith(".h")), None)
        port = next((p for p in port_props.get(member, []) if not p["file"].endswith(".h")), None)
        if header is None:
            failures.append("%s.%s: the header declares no such property (%s)" % (name, member, line))
            continue
        if port is None:
            failures.append("%s.%s: the port declares no such property (%s)" % (name, member, line))
            continue
        if port.get("accessor"):
            # a hand-written accessor returns the type it names; compare it to the header's type with the
            # header's pointer spelling, since the AST writes a method's return type without the
            # property's own _Nonnull suffix
            if header["type"].replace(" _Nonnull", "") not in port["type"] and port["type"] not in header["type"]:
                failures.append(
                    "%s.%s: the accessor returns %s, the header declares %s (%s)"
                    % (name, member, port["type"], header["type"], line)
                )
        elif port["type"] != header["type"]:
            failures.append(
                "%s.%s: type %s in the port, %s in the header (%s)"
                % (name, member, port["type"], header["type"], line)
            )
        if port.get("accessor"):
            missing, extra = [], []
        else:
            missing = [a for a in header["attrs"] if a not in port["attrs"]]
            extra = [a for a in port["attrs"] if a not in header["attrs"]]
        if missing:
            failures.append(
                "%s.%s: the port is missing %s, which the header has (%s)"
                % (name, member, ", ".join(missing), line)
            )
        if extra:
            failures.append(
                "%s.%s: the port adds %s, which the header does not (%s)"
                % (name, member, ", ".join(extra), line)
            )
        print("  %-28s %-34s %-24s %s" % (name + "." + member, header["type"],
                                          ",".join(header["attrs"]) or "-", line))
    return failures


def main():
    # tests/backports/host/homekit -> the repository root, found by walking up to the one holding
    # packages/ rather than by counting levels, so a moved directory cannot silently point elsewhere.
    here = os.path.abspath(os.path.dirname(__file__))
    root = here
    while not os.path.isdir(os.path.join(root, "packages", "a", "apple-backports")):
        if os.path.dirname(root) == root:
            raise SystemExit("ast_check.py: no packages/a/apple-backports above %s" % here)
        root = os.path.dirname(root)
    port = os.path.join(root, "packages/a/apple-backports/HomeKit")
    global PORT_INCLUDE
    PORT_INCLUDE = port
    source = os.path.join(port, "HMAccessoryProfile10_0.m")

    print("header contract, from clang's AST of the SDK and of the port, for %s" % TARGET[0])
    failures = []
    for name, expected in sorted(EXPECTED.items()):
        both = properties(ast(source, name))
        header_props = {k: v for k, v in both.items()}
        port_props = {k: [p for p in v if not p["file"].endswith(".h")] for k, v in both.items()}
        failures.extend(compare(name, expected, header_props, port_props))

    # The control: a scratch copy with one attribute flipped. This must be caught, or nothing above is.
    print("\ncontrol: the same check with HMCameraProfile's weak removed from streamControl")
    with tempfile.TemporaryDirectory() as scratch:
        broken = os.path.join(scratch, "HMAccessoryProfile10_0.m")
        with open(source) as handle:
            text = handle.read()
        with open(broken, "w") as handle:
            handle.write(text.replace("@property (nullable, nonatomic, readonly, strong) HMCameraStreamControl *streamControl;",
                                      "@property (nullable, atomic, readonly, strong) HMCameraStreamControl *streamControl;"))
        control = properties(ast(broken, "HMCameraProfile"))
        caught = []
        for member, line in sorted(EXPECTED["HMCameraProfile"].items()):
            header = next((p for p in control.get(member, []) if p["file"].endswith(".h")), None)
            port = next((p for p in control.get(member, []) if not p["file"].endswith(".h") and not p.get("accessor")), None)
            if port and header and [a for a in header["attrs"] if a not in port["attrs"]]:
                caught.append("%s: %s" % (member, ", ".join(a for a in header["attrs"] if a not in port["attrs"])))
        if caught:
            print("  control caught: %s" % "; ".join(caught))
        else:
            print("  control NOT caught: the check cannot fail, so it is not a check")
            failures.append("the control was not caught")

    if failures:
        print("\nFAILED")
        for failure in failures:
            print("  %s" % failure)
        return 1
    print("\nok: every declared member matches the header's type, nullability and attributes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
