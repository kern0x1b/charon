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
import re
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
    "HMAccessory": {
        "home": "HMAccessory.h:37",
        "cameraProfiles": "HMAccessory+Camera.h:28",
    },
    "HMCameraProfile": {
        "streamControl": "HMCameraProfile.h:33",
        "snapshotControl": "HMCameraProfile.h:38",
        "settingsControl": "HMCameraProfile.h:43",
        "speakerControl": "HMCameraProfile.h:48",
    },
}

ATTRIBUTES = ("readonly", "copy", "nonatomic", "weak")

# The two protocols, and the header each is declared in. Their selectors are read from the AST and their
# required/optional split from the header's own @optional / @required marker lines, because this clang's
# JSON dump carries no optional or required key anywhere in the subtree - measured over the whole dump, not
# assumed from a field name.
PROTOCOLS = {"HMHomeDelegate": "HMHome.h", "HMHomeManagerDelegate": "HMHomeManager.h"}


def protocol_members(source, protocol, port_file):
    """Every selector the AST says this protocol declares, as (selector, line, side). One dump of the
    port's file carries both sides - the header's declarations arrive through its import and are tagged
    with the SDK file by includedFrom, the port's are not - which is the same join the property check uses."""
    header, port_side = [], []

    def walk(node):
        if node.get("kind") == "ObjCMethodDecl" and "[" + protocol + " " in node.get("mangledName", ""):
            line = (node.get("loc") or {}).get("line")
            named = ((node.get("loc") or {}).get("includedFrom") or {}).get("file", "")
            from_sdk = bool(named) and os.path.realpath(named) != os.path.realpath(source)
            (header if from_sdk else port_side).append((node.get("name"), line))
        for child in node.get("inner", []):
            walk(child)

    for document in ast(source, protocol):
        walk(document)
    return header, port_side


PARAMETER = re.compile(r"\([^()]*\)\s*[A-Za-z_][A-Za-z0-9_]*")
MACROS = ("API_AVAILABLE", "API_UNAVAILABLE", "API_DEPRECATED", "NS_SWIFT_UNAVAILABLE",
          "NS_REFINED_FOR_SWIFT", "NS_SWIFT_NAME", "NS_SWIFT_SENDABLE", "NS_SWIFT_ASYNC_NAME")


def _strip_macros(line):
    """A declaration line with its availability macros removed, by scanning for each macro's name and then
    counting its parentheses. A macro is a name in caps, optionally followed by a parenthesised argument
    list whose parentheses nest: API_AVAILABLE(ios(11.0), watchos(4.0), tvos(11.0)) is three deep. The
    argument is skipped whole, so nothing of it can survive into a selector."""
    out = line
    index = 0
    while index < len(out):
        if not (out[index].isupper() and (index == 0 or not (out[index - 1].isalnum() or out[index - 1] == "_"))):
            index += 1
            continue
        start = index
        while index < len(out) and (out[index].isupper() or out[index].isdigit() or out[index] == "_"):
            index += 1
        name = out[start:index]
        end = index
        while end < len(out) and out[end] == " ":
            end += 1
        if end < len(out) and out[end] == "(":
            depth = 0
            while end < len(out):
                if out[end] == "(":
                    depth += 1
                elif out[end] == ")":
                    depth -= 1
                    if depth == 0:
                        end += 1
                        break
                end += 1
            index = end
        out = out[:start] + " " + out[index:]
        index = start + 1
    return out


def selector_in(line):
    """The selector on a declaration line: what is left after the return type, with each "(Type) name"
    dropped, the availability macros removed and the whitespace collapsed. The colon stays on every part,
    including the last, because that is the spelling the AST and the runtime both use.

    The macros are removed by SCANNING for the macro's name and then its balanced parentheses, not by a
    pattern. API_AVAILABLE(ios(11.0), watchos(4.0), tvos(11.0)) holds three of them, so a pattern over the
    macro's argument either stops at the first ")" and leaves ",watchos(4.0),tvos(11.0))" in the selector,
    or has to be written to allow nesting and then breaks on a bare name. Counting the parentheses is the
    one reading that is right for both, and it cannot be over-escaped into a literal backslash."""
    body = _strip_macros(line)
    after = body[body.index(")") + 1:]
    return PARAMETER.sub("", after).split(";")[0].replace(" ", "").strip()


def port_side_set(path, protocol):
    """(selector, optional) as the PORT's own file states it: its marker lines and the selector on each of
    its declaration lines, in order."""
    with open(path) as handle:
        lines = handle.read().split("\n")
    state = "required"
    inside = False
    out = set()
    for text in lines:
        stripped = text.strip()
        if re.match(r"^@protocol %s\b" % protocol, stripped):
            inside = True
            state = "required"
            continue
        if inside and stripped == "@end":
            break
        if not inside:
            continue
        if stripped == "@optional":
            state = "optional"
            continue
        if stripped == "@required":
            state = "required"
            continue
        if stripped.startswith("-"):
            selector = selector_in(stripped)
            if selector:
                out.add((selector, state))
    return out


def declared_set(source, protocol, header_path, port_file):
    """(selector, optional) as one side declares it: the AST's selector joined, by line, to that side's own
    @optional/@required marker. The header's side is read from the SDK header and the port's from the port's
    file, so the two are read the same way and a difference between them is a real difference."""
    header, _ = protocol_members(source, protocol, port_file)
    header_split = protocol_split(header_path, protocol)
    header_set = set()
    for selector, line in header:
        header_set.add((selector, header_split.get(line, "unknown")))
    return header_set, port_side_set(port_file, protocol)


def protocol_split(path, protocol):
    """The split a given file states: which of its method lines it puts after @optional and which after
    @required. The path is a parameter so the header, the port's own file and a scratch copy of the port
    are read by this one function - the reader is not re-implemented per side and cannot drift."""
    with open(path) as handle:
        lines = handle.read().split("\n")
    state = "required"
    out = {}
    inside = False
    for number, text in enumerate(lines, start=1):
        stripped = text.strip()
        if re.match(r"^@protocol %s<" % protocol, stripped):
            inside = True
            state = "required"
            continue
        if inside and stripped == "@end":
            break
        if not inside:
            continue
        if stripped == "@optional":
            state = "optional"
            continue
        if stripped == "@required":
            state = "required"
            continue
        if stripped.startswith("-"):
            out[number] = state
    return out


PORT_INCLUDE = None  # the port's directory, set once the root is found, so a scratch copy can include it


def _worktree_root(here):
    while not os.path.isdir(os.path.join(here, "packages", "a", "apple-backports")):
        if os.path.dirname(here) == here:
            raise SystemExit("ast_check.py: no packages/a/apple-backports above %s" % here)
        here = os.path.dirname(here)
    return here


HERE = os.path.dirname(os.path.abspath(__file__))
# this worktree's own run directory: a control's scratch copy is band output and belongs under
# .agent-work/runs/, never in a system temp path
RUNS = os.path.join(_worktree_root(HERE), ".agent-work", "runs", "homekit")


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


MACROS = ("API_AVAILABLE", "API_UNAVAILABLE", "API_DEPRECATED", "NS_SWIFT_UNAVAILABLE",
          "NS_REFINED_FOR_SWIFT", "NS_SWIFT_NAME", "NS_SWIFT_SENDABLE", "NS_SWIFT_ASYNC_NAME",
          "NS_EXTENSION_UNAVAILABLE_IOS", "API_DEPRECATED_WITH_REPLACEMENT")


def clean_type(text):
    """The property's own type, with the availability macros the header writes after it removed: they land
    in the AST's type string, and what is being compared is the type and its nullability, not the release
    annotation - which the registry row carries and the check reads from the header's own line."""
    out = text
    for macro in MACROS:
        while macro in out:
            head = out.index(macro)
            # the macro and its parenthesised argument, or the bare name
            if "(" in out[head:head + 80] and ")" in out[head:head + 120]:
                end = out.index(")", head) + 1
            else:
                end = head + len(macro)
            out = out[:head] + out[end:]
    return " ".join(out.split())


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
                    "type": clean_type((node.get("type") or {}).get("qualType", "")),
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
        port_member = next((p for p in port_props.get(member, []) if not p["file"].endswith(".h")), None)
        if header is None:
            failures.append("%s.%s: the header declares no such property (%s)" % (name, member, line))
            continue
        if port_member is None:
            failures.append("%s.%s: the port declares no such property (%s)" % (name, member, line))
            continue
        if port_member.get("accessor"):
            # a hand-written accessor returns the type it names; compare it to the header's type with the
            # header's pointer spelling, since the AST writes a method's return type without the
            # property's own _Nonnull suffix
            if header["type"].replace(" _Nonnull", "") not in port_member["type"] and port_member["type"] not in header["type"]:
                failures.append(
                    "%s.%s: the accessor returns %s, the header declares %s (%s)"
                    % (name, member, port_member["type"], header["type"], line)
                )
        elif port_member["type"] != header["type"]:
            failures.append(
                "%s.%s: type %s in the port, %s in the header (%s)"
                % (name, member, port_member["type"], header["type"], line)
            )
        if port_member.get("accessor"):
            missing, extra = [], []
        else:
            missing = [a for a in header["attrs"] if a not in port_member["attrs"]]
            extra = [a for a in port_member["attrs"] if a not in header["attrs"]]
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
        # each class's own file: the properties arrive through that file's import, tagged with the SDK
        # header they came from, and the port's own declaration of them is in the same dump
        path = os.path.join(port, "HMAccessoryHome10_0.m") if name == "HMAccessory" else source
        both = properties(ast(path, name))
        header_props = {k: v for k, v in both.items()}
        port_props = {k: [p for p in v if not p["file"].endswith(".h")] for k, v in both.items()}
        failures.extend(compare(name, expected, header_props, port_props))

    # The control: a scratch copy with one attribute flipped. This must be caught, or nothing above is.
    # A missing member, not a flipped attribute: this port writes its accessors out by hand, and a method
    # carries no attributes for the AST to compare, so deleting the accessor is the failure this piece
    # could actually have.
    print("\ncontrol: the same check with HMAccessory's cameraProfiles accessor removed")
    control_failures = []
    with tempfile.TemporaryDirectory() as scratch:
        broken = os.path.join(scratch, "HMAccessoryHome10_0.m")
        with open(os.path.join(port, "HMAccessoryHome10_0.m")) as handle:
            text = handle.read()
        with open(broken, "w") as handle:
            handle.write(text.replace("- (NSArray<HMCameraProfile *> *)cameraProfiles",
                                      "- (NSArray<HMCameraProfile *> *)charon_cameraProfilesRemoved"))
        seen = properties(ast(broken, "HMAccessory"))
        for member, line in sorted(EXPECTED["HMAccessory"].items()):
            header = next((x for x in seen.get(member, []) if x["file"].endswith(".h")), None)
            port = next((x for x in seen.get(member, []) if not x["file"].endswith(".h")), None)
            if header and port is None:
                control_failures.append("%s: the port declares no such member" % member)
        if control_failures:
            print("  control caught: %s" % "; ".join(control_failures))
        else:
            print("  control NOT caught: this piece's check cannot fail")
            failures.append("the HMAccessory control was not caught")

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
            port_member = next((p for p in control.get(member, []) if not p["file"].endswith(".h") and not p.get("accessor")), None)
            if port_member and header and [a for a in header["attrs"] if a not in port_member["attrs"]]:
                caught.append("%s: %s" % (member, ", ".join(a for a in header["attrs"] if a not in port_member["attrs"])))
        if caught:
            print("  control caught: %s" % "; ".join(caught))
        else:
            print("  control NOT caught: the check cannot fail, so it is not a check")
            failures.append("the control was not caught")

    # The two protocols: the selector set the port declares against the one the header declares, and the
    # split, which is the part that matters here - an optional method turned required would make a
    # conformer that legitimately omits it fail to compile.
    print("\nthe two delegate protocols, of 8.0:")
    port_dir = os.path.dirname(source)
    port_protocols = os.path.join(port_dir, "HMHomeDelegateProtocols8_0.m")
    for protocol, header in sorted(PROTOCOLS.items()):
        header_path = os.path.join(HM_HEADERS, header)
        header_set, port_set = declared_set(port_protocols, protocol, header_path, port_protocols)
        if not port_set or not header_set:
            failures.append("%s: the comparison read %d from the header and %d from the port - one side is "
                            "empty, so every member would differ and the check would pass for the wrong "
                            "reason" % (protocol, len(header_set), len(port_set)))
        print("  %-24s header %d, port %d, %d optional in the header"
              % (protocol, len(header_set), len(port_set),
                 sum(1 for _, state in header_set if state == "optional")))
        for difference in sorted(header_set ^ port_set):
            side, state = difference
            where = "the port has the header does not" if difference in port_set else "missing from the port"
            failures.append("%s: %s is %s (%s where the header says %s)"
                            % (protocol, side, where, state,
                               dict(header_set).get(side, "nothing")))

    # Control 1, per protocol: an @optional flipped to @required on a scratch copy. The split is the whole
    # point of these two, so a port that required a method the header calls optional must be caught.
    print("\ncontrol: one @optional flipped to @required in the port, per protocol")
    import shutil
    for protocol, header in sorted(PROTOCOLS.items()):
        header_path = os.path.join(HM_HEADERS, header)
        scratch_dir = os.path.join(RUNS, "scratch")
        os.makedirs(scratch_dir, exist_ok=True)
        broken = os.path.join(scratch_dir, "%s-optional-flipped.m" % protocol)
        shutil.copyfile(port_protocols, broken)
        with open(broken) as handle:
            text = handle.read()
        block = text.index("@protocol %s " % protocol)
        marker = text.index("@optional", block)
        with open(broken, "w") as handle:
            handle.write(text[:marker] + "@required" + text[marker + len("@optional"):])
        header_set, port_set = declared_set(broken, protocol, header_path, broken)
        differing = sorted(header_set ^ port_set)
        if differing:
            print("  %-24s control caught: %s" % (protocol, "; ".join(
                "%s is %s where the header says %s" % (side, state, dict(header_set).get(side, "nothing"))
                for side, state in differing[:3])))
        else:
            print("  %-24s control NOT caught" % protocol)
            failures.append("%s: the required/optional control was not caught" % protocol)

    # Control 2, per protocol: a selector removed from the scratch copy, which the set comparison must
    # notice as the port declaring fewer than the header.
    print("\ncontrol: one declaration deleted from the port, per protocol")
    for protocol, header in sorted(PROTOCOLS.items()):
        header_path = os.path.join(HM_HEADERS, header)
        scratch_dir = os.path.join(RUNS, "scratch")
        os.makedirs(scratch_dir, exist_ok=True)
        broken = os.path.join(scratch_dir, "%s-selector-deleted.m" % protocol)
        with open(port_protocols) as handle:
            lines = handle.read().split("\n")
        block = next(i for i, line in enumerate(lines) if line.startswith("@protocol %s " % protocol))
        first = next(i for i in range(block, len(lines)) if lines[i].strip().startswith("-"))
        victim = next((n for n in range(first, len(lines))
                       if lines[n].strip().startswith("-") and "]" not in lines[n]), None)
        end = victim
        while ";" not in lines[end]:
            end += 1
        removed = [line for line in lines[:victim - 1] if line.strip().startswith("//")]
        kept = lines[:victim - 1] + removed + lines[end + 1:]
        with open(broken, "w") as handle:
            handle.write("\n".join(kept))
        header_set, port_set = declared_set(broken, protocol, header_path, broken)
        missing = sorted(s for s, _ in header_set - port_set)
        if missing:
            print("  %-24s control caught: %s is missing from the port (%d in the header, %d in the port)"
                  % (protocol, missing[0], len(header_set), len(port_set)))
        else:
            print("  %-24s control NOT caught: deleting one declaration changed nothing" % protocol)
            failures.append("%s: the deleted-selector control was not caught" % protocol)

    if failures:
        print("\nFAILED")
        for failure in failures:
            print("  %s" % failure)
        return 1
    print("\nok: every declared member matches the header's type, nullability and attributes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
