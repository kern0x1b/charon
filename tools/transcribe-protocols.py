#!/usr/bin/env python3
"""transcribe-protocols.py — the Charon headers that declare the protocols the SDK the package compiles
against does not declare, from the SDK that does.

    transcribe-protocols.py <sdk26> <sdk16> <worktree> <out> <name:framework:introduced>...

Facts only: the base list, each member with its kind, return type and parameter types, @required and
@optional as sections, properties as properties, and API_AVAILABLE(ios(<the row's introduced>)) so the lift
and a band place the row by the release it arrived in. No header text and no comment is copied.

Two refusals, each one line, and nothing is written for what is refused:

  * a protocol with no ObjCProtocolDecl in the 26.2 dump, or that adopts one, is refused: the SDK that
    declares it is not the one the build compiles against;
  * a member whose type the 16.4 SDK does not declare as a class or a typedef is refused by name, rather
    than written with a guessed spelling. A class is written as @class, which is the declaration a header
    needs for a type it only names.
"""
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

sdk26, sdk16, worktree, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
wanted = {}
for item in sys.argv[5:]:
    name, framework, introduced = item.split(":")
    wanted[name] = (framework, introduced)

registry = os.path.join(worktree, "packages", "a", "apple-backports", "registry")
LIBRARIES = []
for line in open(os.path.join(worktree, "modules", "apple", "backports.lua"), encoding="utf-8"):
    found = re.search(r'name = "([A-Za-z]+Backports)", folder = "([A-Za-z]+)"', line)
    if found:
        LIBRARIES.append({"name": found.group(1), "folder": found.group(2)})
FOLDER_OF_FRAMEWORK = {entry["folder"]: entry["folder"] for entry in LIBRARIES}

# a protocol a band already declares needs no transcription
# a protocol a header already declares with a body; a forward declaration (@protocol X;) is not one, and
# counting one here is how the headers this tool writes fed themselves back as "already declared"
have = set()
for base, _, files in os.walk(os.path.join(worktree, "packages")):
    for name in files:
        if not name.endswith(".h"):
            continue
        for line in open(os.path.join(base, name), encoding="utf-8", errors="replace"):
            for protocol in re.findall(r"@protocol\s+([A-Za-z0-9_]+)", line):
                if not re.search(r"@protocol\s+" + protocol + r"\s*;", line):
                    have.add(protocol)

os.makedirs(out, exist_ok=True)


def dump(sdk, frameworks, target, filename):
    """Write the AST of one SDK's umbrella headers, whole, into out/filename. The declarations the header
    needs are inside the host's @interface, and a filter on a selector never reaches them, so the dump is
    unfiltered and the choice of what to read out of it is made here."""
    with open(os.path.join(out, "probe.m"), "w") as stream:
        for framework in frameworks:
            stream.write("#import <%s/%s.h>\n" % (framework, framework))
        stream.write("int main(void) { return 0; }\n")
    result = subprocess.run(["xcrun", "clang", "-target", target, "-isysroot", sdk, "-fobjc-arc", "-w",
                             "-fsyntax-only", "-Xclang", "-ast-dump=json", os.path.join(out, "probe.m")],
                            capture_output=True, text=True)
    if '"kind": "TranslationUnitDecl"' not in result.stdout:
        sys.exit("no AST from %s for %s: %s" % (sdk, target, result.stderr[:300]))
    with open(os.path.join(out, filename), "w", encoding="utf-8") as stream:
        stream.write(result.stdout)


def documents(text):
    decoder, index = json.JSONDecoder(), 0
    while True:
        index = text.find("{", index)
        if index < 0:
            return
        node, index = decoder.raw_decode(text, index)
        yield node


def walk(node, visit):
    if isinstance(node, list):
        for item in node:
            walk(item, visit)
        return
    if not isinstance(node, dict):
        return
    visit(node)
    for value in node.values():
        if isinstance(value, (list, dict)):
            walk(value, visit)


frameworks = sorted({f for f, _ in wanted.values()})

classes26, classes16, decls = set(), set(), {}


def collect26(node):
    if node.get("kind") == "ObjCInterfaceDecl" and node.get("name"):
        classes26.add(node["name"])
    if node.get("kind") == "ObjCProtocolDecl" and node.get("name") and node["name"] not in decls:
        bases = [b.get("referencedDecl", {}).get("name") or b.get("name")
                 for b in node.get("protocols", [])]
        members = []
        for inner in node.get("inner", []):
            if inner.get("kind") == "ObjCMethodDecl" and inner.get("name"):
                members.append((inner.get("optional") is True, inner.get("instance") is True,
                                inner.get("type", {}).get("qualType", ""), inner["name"], inner.get("inner", [])))
        decls[node["name"]] = ([b for b in bases if b], members)


# one dump per SDK: the 26.2 that declares the protocols, and the gate's 16.4 that has to compile what is
# written, so the two class sets are the ones a header is actually written against
dump(sdk26, frameworks, "arm64-apple-ios26.2", "ast26.json")
dump(sdk16, frameworks, "armv7-apple-ios6.1.3", "ast16.json")

for document in documents(open(os.path.join(out, "ast26.json")).read()):
    walk(document, collect26)


def collect16(node):
    if node.get("kind") in ("ObjCInterfaceDecl", "TypedefDecl") and node.get("name"):
        classes16.add(node["name"])


for document in documents(open(os.path.join(out, "ast16.json")).read()):
    walk(document, collect16)

BUILTIN = {"id", "SEL", "Class", "BOOL", "instancetype", "IMP", "NSInteger", "NSUInteger", "CGFloat", "double",
           "float", "int", "unsigned", "long", "char", "void", "NSString", "NSData", "NSArray", "NSDictionary",
           "NSError", "NSNumber", "NSTimeInterval", "NSUInteger", "CGRect", "CGPoint", "CGSize", "NSUInteger",
           "objc_AssociationPolicy", "dispatch_queue_t", "CFStringRef", "CFTypeRef", "NSRange", "NSInteger"}


def base_of(qual):
    text = re.sub(r"\b_Nullable\b|\b_Nonnull\b|\b_None\b|\b_null_unspecified\b"
                r"|\b__kindof\b|\b__strong\b|\b__weak\b|\b__unsafe_unretained\b|\b__autoreleasing\b", "", qual)
    text = re.sub(r"<[^<>]*>", "", text)
    text = re.sub(r"\bconst\b|\bvolatile\b|\*", " ", text)
    parts = [p for p in re.split(r"[^A-Za-z_][^A-Za-z0-9_]*", text) if p]
    return parts[-1] if parts else ""


per_library, refusals, missing = defaultdict(list), [], []
for name, (framework, introduced) in wanted.items():
    if name in have:
        per_library[(FOLDER_OF_FRAMEWORK.get(framework, framework), framework)].append((name, introduced))
        continue
    if name not in decls:
        missing.append("%s: not in the 26.2 AST; the SDK that declares it is not the one the build uses" % name)
        continue
    bases, members = decls[name]
    adopted = [b for b in bases if b not in decls and b not in have]
    if adopted:
        missing.append("%s: adopts %s, which the 26.2 AST does not carry either" % (name, ", ".join(adopted)))
        continue
    typed, refused = [], []
    for optional, instance, return_type, selector, params in members:
        types = [return_type] + [p.get("type", {}).get("qualType", "") for p in params if p.get("kind") == "ParmVarDecl"]
        for qual in types:
            base = base_of(qual)
            if not base or base in BUILTIN or base in classes26 or base in classes16:
                continue
            if not any(selector in line for line in refused):
                refused.append("%s.%s needs %s, which %s does not declare"
                               % (name, selector, base, os.path.basename(sdk16.rstrip("/"))))
            typed.append(base)
        if refused:
            break
    if refused:
        refusals.extend(refused)
        continue
    per_library[(FOLDER_OF_FRAMEWORK.get(framework, framework), framework)].append((name, introduced, bases, members, typed))

for line in sorted(missing + refusals):
    print("refused: " + line)


def spelled_of(qual):
    return re.sub(r"\s*__\w+", "", qual)


def render(members, prefix):
    lines, seen_optional = [], False
    for optional, instance, return_type, selector, params in members:
        keywords = selector.split(":")[:-1] if ":" in selector else [selector]
        types = [spelled_of(p.get("type", {}).get("qualType", "")) for p in params if p.get("kind") == "ParmVarDecl"]
        if ":" in selector:
            if len(keywords) != len(types):
                sys.exit("%s: %d pieces and %d parameters" % (selector, len(keywords), len(types)))
            text = " ".join("%s:(%s)%s" % (piece, qual, param.get("name") or "")
                            for piece, qual, param in zip(keywords, types, params))
        else:
            text = selector
        if optional and not seen_optional:
            lines.append("@optional")
            seen_optional = True
        elif not optional and seen_optional:
            lines.append("@required")
            seen_optional = False
        lines.append("%s (%s)%s;" % ("-" if instance else "+", spelled_of(return_type), text))
    return lines


for (folder, framework), entries in sorted(per_library.items()):
    lines = ["// Charon%sProtocols.h — the %s protocols the SDK this package compiles against does not declare,"
             % (folder, framework),
             "// transcribed by tools/transcribe-protocols.py from the SDK that declares them: the base list, each",
             "// member with its kind, return type and parameter types, @required and @optional as sections, and",
             "// API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the release it arrived in.",
             "// Facts only, and nothing written for a protocol or a member the generator refused by name below.",
             "#import <%s/%s.h>" % (framework, framework),
             "#import <Foundation/Foundation.h>",
             "#import <objc/NSObject.h>", ""]
    for entry in entries:
        name, introduced = entry[0], entry[1]
        if len(entry) == 2:
            lines.append("@protocol %s;" % name)
            lines.append("")
            continue
        _, _, bases, members, typed = entry
        for one in sorted(set(typed)):
            lines.append("@class %s;" % one)
        lines.append("API_AVAILABLE(ios(%s))" % introduced)
        lines.append("@protocol %s <%s>" % (name, ", ".join(bases) if bases else "NSObject"))
        lines.extend(render(members, folder))
        if not members:
            lines.append("@end")
            lines.append("")
            continue
        lines.append("@end")
        lines.append("")
    path = os.path.join(out, "Charon%sProtocols.h" % folder)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write("\n".join(lines))
    print("%-24s %2d protocols (from %s) -> %s" % (folder, len(entries), framework, path))
