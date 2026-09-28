#!/usr/bin/env python3
"""transcribe-protocols.py — the Charon headers that declare the protocols the SDK the package compiles
against does not declare, from the SDK that does.

    transcribe-protocols.py <sdk26> <sdk16> <worktree> <out> <name:framework:introduced>...

Facts only: the base list, each member with its kind, return type and parameter types, @required and
@optional as sections, properties as properties, and API_AVAILABLE(ios(<the row's introduced>)) so the lift
and a band place the row by the release it arrived in. No header text and no comment is copied.

A protocol is usually declared more than once in a dump: forward (@protocol X;) wherever a header names it,
and once with its body. The members come from the one declaration that has any, and two declarations with
differing member sets stop the tool; the bases come from that declaration, or from any one for a protocol with
no members. Implicit methods (a property's getter and setter) are the property's and are not written. clang's
JSON marks a property @optional (control) and not a method, so a member's section is read from the header the
dump names: the last @optional or @required between the definition's start and the member.

A protocol the 16.4 SDK already defines, as the armv7 build sees it, or that a header of the tree other than
the ones this tool writes already defines, is only forward-declared: the umbrella import supplies the body of
the first, and the second's header, which has to be in the library's own folder, is imported.

Two refusals, each one line, and nothing is written for what is refused:

  * a protocol with no ObjCProtocolDecl in the 26.2 dump, or that adopts one, is refused: the SDK that
    declares it is not the one the build compiles against;
  * a member naming a type (in its return, its parameters, a block's parameters or a property) that the
    16.4 SDK does not declare as a class, typedef, enum or record, and that is not a class of the 26.2 SDK,
    is refused by name, rather than written with a guessed spelling. A class only the 26.2 SDK declares is
    written as @class, which is the declaration a header needs for a type it only names.
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
# The headers this tool writes (Charon<Folder>Protocols.h) are not read: a regeneration fed by the headers it
# replaces would forward-declare every protocol they transcribed and transcribe none of them again.
have = {}
for base, _, files in os.walk(os.path.join(worktree, "packages")):
    for name in files:
        if not name.endswith(".h") or re.fullmatch(r"Charon[A-Za-z0-9]+Protocols\.h", name):
            continue
        for line in open(os.path.join(base, name), encoding="utf-8", errors="replace"):
            for protocol in re.findall(r"@protocol\s+([A-Za-z0-9_]+)", line):
                if not re.search(r"@protocol\s+" + protocol + r"\s*;", line):
                    have.setdefault(protocol, os.path.join(base, name))

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


class Located:
    """clang's JSON writes a location's file only when it differs from the one it wrote last, so the file of
    every location is the last one written before it in document order. walk() visits keys in the order they
    were written, so this is tracked as the walk goes and stored on the location itself."""

    def __init__(self):
        self.file = None

    def __call__(self, node):
        if "offset" in node:
            if "file" in node:
                self.file = node["file"]
            node["_file"] = self.file


def place(loc):
    """The file and byte offset a location stands for in the header text: the expansion when it is a macro's."""
    loc = loc.get("expansionLoc", loc)
    if "_file" not in loc or loc["_file"] is None:
        sys.exit("a location with no file: %s" % json.dumps(loc)[:200])
    return loc["_file"], loc["offset"]


SOURCES = {}


def source(file):
    if file not in SOURCES:
        text = open(file, "rb").read().decode("latin-1")
        # comments become spaces, so an @optional in a comment is not one and every offset stays where it was
        SOURCES[file] = re.sub(r"//[^\n]*|/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text,
                               flags=re.S)
    return SOURCES[file]


def members_of(node):
    return [inner for inner in node.get("inner", [])
            if (inner.get("kind") == "ObjCMethodDecl" and not inner.get("isImplicit"))
            or inner.get("kind") == "ObjCPropertyDecl"]


def shape(node):
    return sorted((m["kind"], m.get("name"), m.get("instance") is True, m.get("class") is True)
                  for m in members_of(node))


def defines(node):
    """A node is a definition when it has members, or, for a protocol with none, when the source after its name
    is not the ; or , of a forward declaration."""
    if members_of(node):
        return True
    file, offset = place(node["loc"])
    after = source(file)[offset + len(node["name"]):].lstrip()
    return not after.startswith((";", ","))


def gather(path):
    """Every ObjCProtocolDecl declaration node per name, and the class and typedef names, from one dump. A
    node with no range is a reference to a protocol (a base, a type), not a declaration of it."""
    protocols, classes, types = defaultdict(list), set(), set()
    located = Located()

    def visit(node):
        located(node)
        kind = node.get("kind")
        if kind == "ObjCInterfaceDecl" and node.get("name"):
            classes.add(node["name"])
        elif kind in ("TypedefDecl", "EnumDecl", "RecordDecl") and node.get("name"):
            types.add(node["name"])
        elif kind == "ObjCProtocolDecl" and node.get("name") and "range" in node:
            protocols[node["name"]].append(node)

    for document in documents(open(path).read()):
        walk(document, visit)
    return protocols, classes, types


def section_of(member, begin):
    """@optional or @required: the last of the two between the protocol definition's start and the member,
    read from the header, since clang's JSON carries it for a property (control) and not for a method."""
    file, offset = place(member["loc"])
    if file != begin[0] or offset < begin[1]:
        sys.exit("%s is at %s:%d, outside the definition at %s:%d" % (member.get("name"), file, offset, begin[0], begin[1]))
    found = re.findall(r"@(optional|required)\b", source(file)[begin[1]:offset])
    return found[-1] if found else "required"


def definition(name, nodes):
    """The members from the one node that has them, the bases from that node (or from any node when none has
    members: a marker protocol)."""
    full = [node for node in nodes if members_of(node)]
    if len({json.dumps(shape(node)) for node in full}) > 1:
        sys.exit("%s: %d declarations with differing member sets" % (name, len(full)))
    chosen = full[0] if full else nodes[0]
    bases = [b.get("referencedDecl", {}).get("name") or b.get("name") for b in chosen.get("protocols", [])]
    members = []
    if full:
        begin = place(chosen["range"]["begin"])
        for inner in members_of(chosen):
            section = section_of(inner, begin)
            if inner["kind"] == "ObjCPropertyDecl" and inner.get("control", section) != section:
                sys.exit("%s.%s: the header says @%s and clang says %s" % (name, inner["name"], section, inner["control"]))
            members.append((section == "optional", inner))
    return [b for b in bases if b], members


# one dump per SDK: the 26.2 that declares the protocols, and the gate's 16.4 that has to compile what is
# written, so the two class sets are the ones a header is actually written against
dump(sdk26, frameworks, "arm64-apple-ios26.2", "ast26.json")
dump(sdk16, frameworks, "armv7-apple-ios6.1.3", "ast16.json")

protocols26, classes26, _ = gather(os.path.join(out, "ast26.json"))
decls = {name: definition(name, nodes) for name, nodes in protocols26.items()}
protocols16, interfaces16, types16 = gather(os.path.join(out, "ast16.json"))
classes16 = interfaces16 | types16
# a protocol the 16.4 SDK already defines, as the armv7 build sees it, is not declared a second time: the
# umbrella import supplies it, and a second body is a duplicate definition clang ignores
defined16 = {name for name, nodes in protocols16.items() if any(defines(node) for node in nodes)}

BUILTIN = {"id", "SEL", "Class", "BOOL", "instancetype", "IMP", "NSInteger", "NSUInteger", "CGFloat", "double",
           "float", "int", "unsigned", "long", "char", "void", "NSString", "NSData", "NSArray", "NSDictionary",
           "NSError", "NSNumber", "NSTimeInterval", "NSUInteger", "CGRect", "CGPoint", "CGSize", "NSUInteger",
           "objc_AssociationPolicy", "dispatch_queue_t", "CFStringRef", "CFTypeRef", "NSRange", "NSInteger"}


KEYWORDS = {"struct", "enum", "union", "signed", "short", "bool", "_Bool", "const", "volatile", "_Nullable_result"}


def names_of(qual):
    """Every type name a qualType spells, with nullability, __kindof, the ownership qualifiers and the
    protocols of id<...> taken out: a block's parameters are types the header has to be able to name too."""
    text = re.sub(r"\b_Nullable_result\b|\b_Nullable\b|\b_Nonnull\b|\b_None\b|\b_Null_unspecified\b|\b_null_unspecified\b"
                  r"|\b__kindof\b|\b__strong\b|\b__weak\b|\b__unsafe_unretained\b|\b__autoreleasing\b", "", qual)
    text = re.sub(r"\bid\s*<[^<>]*>", "id", text)
    return [p for p in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text) if p not in KEYWORDS]


def type_of(member):
    return (member.get("returnType") if member["kind"] == "ObjCMethodDecl" else member.get("type", {})).get("qualType", "")


per_library, refusals, missing = defaultdict(list), [], []
for name, (framework, introduced) in wanted.items():
    if name in defined16 or name in have:
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
    typed, refused = set(), []
    for optional, member in members:
        types = [type_of(member)] + [p.get("type", {}).get("qualType", "") for p in member.get("inner", [])
                                     if p.get("kind") == "ParmVarDecl"]
        for qual in types:
            for base in names_of(qual):
                if base in BUILTIN or base in classes16:
                    continue
                if base in classes26:
                    typed.add(base)
                    continue
                refused.append("%s.%s needs %s, which %s does not declare"
                               % (name, member["name"], base, os.path.basename(sdk16.rstrip("/"))))
                break
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


ATTRIBUTES = ("class", "nonatomic", "atomic", "readonly", "readwrite", "copy", "strong", "weak", "assign", "retain",
              "unsafe_unretained", "null_resettable")


def declarator(qual, name):
    """A property's type and name: a block or a function pointer holds its name inside its own parentheses."""
    spelled = spelled_of(qual)
    found = re.search(r"\((\^|\*)", spelled)
    if not found:
        return "%s %s" % (spelled, name) if not spelled.endswith("*") else "%s%s" % (spelled, name)
    depth, index = 0, found.start()
    while index < len(spelled):
        depth += {"(": 1, ")": -1}.get(spelled[index], 0)
        if depth == 0:
            return spelled[:index] + name + spelled[index:]
        index += 1
    sys.exit("%s: no closing parenthesis in %s" % (name, qual))


def render_property(member):
    attributes = [key for key in ATTRIBUTES if member.get(key) is True]
    for key in ("getter", "setter"):
        if key in member:
            attributes.append("%s=%s" % (key, member[key]["name"]))
    return "@property (%s) %s;" % (", ".join(attributes), declarator(member["type"]["qualType"], member["name"]))


def render_method(member):
    selector = member["name"]
    params = [p for p in member.get("inner", []) if p.get("kind") == "ParmVarDecl"]
    if ":" in selector:
        keywords = selector.split(":")[:-1]
        if len(keywords) != len(params):
            sys.exit("%s: %d pieces and %d parameters" % (selector, len(keywords), len(params)))
        text = " ".join("%s:(%s)%s" % (piece, spelled_of(param["type"]["qualType"]), param.get("name") or "")
                        for piece, param in zip(keywords, params))
    else:
        text = selector
    if member.get("variadic"):
        text += ", ..."
    return "%s (%s)%s;" % ("-" if member.get("instance") else "+", spelled_of(type_of(member)), text)


def render(members, prefix):
    lines, optional_now = [], False
    for optional, member in members:
        if optional != optional_now:
            lines.append("@optional" if optional else "@required")
            optional_now = optional
        lines.append(render_property(member) if member["kind"] == "ObjCPropertyDecl" else render_method(member))
    return lines


for (folder, framework), entries in sorted(per_library.items()):
    lines = ["// Charon%sProtocols.h — the %s protocols the generated protocol sources name, written by"
             % (folder, framework),
             "// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a",
             "// header of this folder does, is forward-declared and its body comes from that import; any other is",
             "// transcribed from the SDK that declares it: the base list, each member with its kind and types,",
             "// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.",
             "#import <%s/%s.h>" % (framework, framework),
             "#import <Foundation/Foundation.h>",
             "#import <objc/NSObject.h>"]
    # a protocol a header of the library's own folder defines is supplied by that header, which the generated
    # source reaches through the folder on its include path; a forward declaration alone gives @protocol() an
    # empty protocol, with no base and no member
    folder_path = os.path.join(worktree, "packages", "a", "apple-backports", folder)
    for header in sorted({have[entry[0]] for entry in entries if len(entry) == 2 and entry[0] not in defined16}):
        if os.path.dirname(os.path.abspath(header)) != os.path.abspath(folder_path):
            sys.exit("%s defines a protocol of %s from outside its folder" % (header, folder))
        lines.append('#import "%s"' % os.path.basename(header))
    lines.append("")
    for entry in entries:
        name, introduced = entry[0], entry[1]
        if len(entry) == 2:
            lines.append("@protocol %s;" % name)
            lines.append("")
            continue
        _, _, bases, members, typed = entry
        for one in sorted(typed):
            lines.append("@class %s;" % one)
        lines.append("API_AVAILABLE(ios(%s))" % introduced)
        lines.append("@protocol %s <%s>" % (name, ", ".join(bases) if bases else "NSObject"))
        lines.extend(render(members, folder))
        lines.append("@end")
        lines.append("")
    path = os.path.join(out, "Charon%sProtocols.h" % folder)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write("\n".join(lines))
    print("%-24s %2d protocols (from %s) -> %s" % (folder, len(entries), framework, path))
