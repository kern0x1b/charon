import json
import os
import re
import subprocess
import sys
import hashlib


def documents(text):
    decoder = json.JSONDecoder()
    index = 0
    while True:
        index = text.find("{", index)
        if index < 0:
            return
        node, index = decoder.raw_decode(text, index)
        yield node


def ported(objects):
    """The selectors the objects' Charon categories carry, and the classes the objects themselves define.
    A member of a class the port defines is not carried: the class is renamed, so nothing of it can reach
    the host's class of the same name, and a member the port adds to its own class is the one the device
    builds - UIAction (CharonFourteen)'s -sender lands on the port's own UIAction there, and on the port's
    renamed class here. Prefixing it as well would leave the test calling a name only the host's class has."""
    names = subprocess.run(["xcrun", "nm", *objects], capture_output=True, text=True, check=True).stdout
    own, found = set(), set()
    for line in names.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] != "U" and parts[2].startswith("_OBJC_CLASS_$_"):
            own.add(parts[2][len("_OBJC_CLASS_$_"):])
    for kind, owner, selector in re.findall(r"([-+])\[([A-Za-z0-9_]+)\(Charon[A-Za-z0-9_]*\) ([A-Za-z0-9_:]+)\]", names):
        if owner not in own:
            found.add((kind, owner, selector))
    return found


def runtime_superclasses():
    import ctypes
    ctypes.CDLL("/System/Library/Frameworks/Foundation.framework/Foundation")
    runtime = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
    runtime.objc_getClass.restype = ctypes.c_void_p
    runtime.objc_getClass.argtypes = [ctypes.c_char_p]
    runtime.class_getSuperclass.restype = ctypes.c_void_p
    runtime.class_getSuperclass.argtypes = [ctypes.c_void_p]
    runtime.class_getName.restype = ctypes.c_char_p
    runtime.class_getName.argtypes = [ctypes.c_void_p]

    class Chain(dict):
        def get(self, name, default=None):
            if name not in self:
                found = runtime.objc_getClass(name.encode())
                parent = runtime.class_getSuperclass(found) if found else None
                self[name] = runtime.class_getName(parent).decode() if parent else None
            return dict.get(self, name, default)
    return Chain()


def bare(qualified):
    text = qualified.replace("__kindof", "").replace("_Nonnull", "").replace("_Nullable", "").replace("*", "").replace("const", "")
    text = re.sub(r"<.*?>", "", text)
    return text.strip()


FAMILIES = ("mutableCopy", "copy", "init", "new", "alloc")


def prefixed(keyword, prefix):
    # A prefix that ends in "_" is a separator and is kept as it is, so the keyword keeps its own
    # spelling (charonHost_ + nativeBounds -> charonHost_nativeBounds). A prefix without one is glued
    # to the keyword as the first half of a camel-cased name, so the keyword's first letter is raised
    # (charonHost + nativeBounds -> charonHostNativeBounds).
    for family in FAMILIES:
        rest = keyword[len(family):]
        if keyword.startswith(family) and (not rest or rest[0].isupper()):
            return family + prefix[0].upper() + prefix[1:].rstrip("_") + rest
    if prefix.endswith("_"):
        return prefix + keyword
    return prefix + keyword[0].upper() + keyword[1:]


def spelled(type_node):
    qualified = type_node.get("qualType", "")
    if qualified.startswith("instancetype"):
        return qualified
    return type_node.get("desugaredQualType", qualified)


def declaration(sign, node, prefix):
    keywords = node["name"].split(":")
    parameters = [item for item in node.get("inner", []) if item.get("kind") == "ParmVarDecl"]
    head = "%s (%s)" % (sign, spelled(node["returnType"]))
    if not parameters:
        return head + prefixed(node["name"], prefix)
    parts = []
    for index, parameter in enumerate(parameters):
        keyword = prefixed(keywords[index], prefix) if index == 0 else keywords[index]
        parts.append("%s:(%s)%s" % (keyword, spelled(parameter["type"]), parameter.get("name", "value%d" % index)))
    return head + " ".join(parts)


class Rewriter:
    def __init__(self, source, carried, superclasses):
        self.source = source
        self.carried = carried
        self.superclasses = superclasses
        self.inserts = set()
        self.unresolved = []
        self.candidates = []
        self.signatures = []

    def owns(self, kind, receiver, selector):
        while receiver:
            if (kind, receiver, selector) in self.carried:
                return True
            receiver = self.superclasses.get(receiver)
        return False

    def keyword_after(self, offset):
        match = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)").match(self.source, offset)
        return match.start(1) if match else None

    def receiver_class(self, node, context):
        kind = node.get("receiverKind")
        if kind == "class":
            return "+", bare(node["classType"]["qualType"])
        if kind in ("super_instance", "super_class") or not node.get("inner"):
            return None, None
        inner = node["inner"][0]
        qualified = bare(inner["type"]["qualType"])
        if qualified in ("instancetype", "id"):
            # an id-typed receiver names no class: only self, and only inside a method, is placeable. Outside
            # one - in a C function - even self is not, and a receiver left as the type name would be silently
            # skipped, which is how a send ends up unrenamed and unrecognized at run time.
            target = inner
            while target.get("kind") in ("ImplicitCastExpr", "CStyleCastExpr") and target.get("inner"):
                target = target["inner"][0]
            if context and target.get("kind") == "DeclRefExpr" and target.get("referencedDecl", {}).get("name") == "self":
                return ("+" if context[0] == "+" else "-"), context[1]
            if target.get("kind") == "ObjCMessageExpr" and target.get("selector") == "alloc":
                owner = self.receiver_class(target, context)[1]
                return "-", owner
            return "-", None
        if qualified == "Class":
            return "+", context[1] if context else None
        return "-", qualified

    def walk(self, node, context):
        if isinstance(node, list):
            for item in node:
                self.walk(item, context)
            return
        if not isinstance(node, dict):
            return
        # A node from an included header carries offsets into that header, which mean nothing in this source:
        # every offset here indexes this file's text. Such a node and everything under it is left alone.
        if "includedFrom" in node.get("range", {}).get("begin", {}):
            return
        kind = node.get("kind")
        if kind in ("ObjCCategoryImplDecl", "ObjCCategoryDecl"):
            owner = node.get("interface", {}).get("name")
            for item in node.get("inner", []):
                self.walk(item, ("-", owner))
            return
        if kind == "ObjCSelectorExpr" and node.get("selector"):
            # @selector(aCarriedSelector:) names the same method the definition declares, and the port's own
            # code hands it to a runtime that sends it, so it has to move with the definition
            begin = node.get("range", {}).get("begin", {}).get("offset")
            if begin is not None and any(entry[2] == node["selector"] for entry in self.carried):
                self.inserts.add(self.source.index("(", begin) + 1)
        if kind == "ObjCMethodDecl" and context and node.get("range", {}).get("begin", {}).get("offset") is not None:
            sign = "-" if node.get("instance", True) else "+"
            if (sign, context[1], node["name"]) in self.carried:
                begin = node["range"]["begin"]["offset"]
                close = self.source.index("(", begin)
                depth = 0
                while True:
                    depth += {"(": 1, ")": -1}.get(self.source[close], 0)
                    if depth == 0:
                        break
                    close += 1
                self.inserts.add(self.keyword_after(close + 1))
                self.signatures.append((context[1], sign, node))
            for item in node.get("inner", []):
                self.walk(item, (sign, context[1]))
            return
        if kind == "ObjCMessageExpr":
            selector = node["selector"]
            sign, receiver = self.receiver_class(node, context)
            if sign and receiver and self.owns(sign, receiver, selector):
                if node.get("receiverKind") == "class":
                    start = self.source.index("[", node["range"]["begin"]["offset"]) + 1
                    token = re.compile(r"\s*[A-Za-z_][A-Za-z0-9_]*").match(self.source, start)
                    self.inserts.add(self.keyword_after(token.end()))
                else:
                    inner = node["inner"][0]["range"]["end"]
                    self.inserts.add(self.keyword_after(inner["offset"] + inner["tokLen"]))
            elif sign and not receiver and any(entry[2] == selector for entry in self.carried):
                # A receiver of no class: the send may still be the port's own method, which the host's class
                # of that name does not answer. Whether the host declares the selector at all decides, and
                # that is asked of the headers below rather than guessed from the superclass chain - a host
                # subclass instance reaches the owner in the chain and would be renamed wrongly.
                inner = node["inner"][0]["range"] if node.get("inner") else None
                keyword = self.keyword_after(inner["end"]["offset"] + inner["end"]["tokLen"]) if inner else None
                if keyword is not None:
                    self.candidates.append((keyword, selector))
        if kind == "ObjCPropertyRefExpr" and node.get("property", {}).get("name"):
            name = node["property"]["name"]
            accessors = []
            if node.get("isMessagingGetter"):
                accessors.append(name)
            if node.get("isMessagingSetter"):
                accessors.append("set" + name[0].upper() + name[1:] + ":")
            receiver = node.get("inner", [{}])[0].get("type", {}).get("qualType", "")
            receiver = context[1] if bare(receiver) in ("id", "instancetype") and context else bare(receiver)
            if any(self.owns("-", receiver, accessor) for accessor in accessors):
                # Dot syntax names the accessor itself, so a read is rewritten like a message send's keyword.
                # A write cannot be: clang derives the setter from the property name it reads, so `self.foo = x`
                # asks for -setFoo: under the property name -charonHostFoo:, and one identifier cannot stand
                # for both. That is reported rather than half done; such a write has to be spelled out as a send.
                if node.get("isMessagingSetter"):
                    # A write cannot be renamed at all: clang derives the setter from the property name it
                    # reads, so `self.foo = x` asks for -setFoo: under the name -charonHostFoo:, and one
                    # identifier cannot be both. Spelling the write out as a send is the only way.
                    self.unresolved.append((node["range"]["end"]["offset"], "a write to %s through dot syntax" % name))
                else:
                    self.inserts.add(node["range"]["end"]["offset"])
        for value in node.values():
            if isinstance(value, (list, dict)):
                self.walk(value, context)

    def result(self, prefix):
        text = self.source
        for offset in sorted((offset for offset in self.inserts if offset is not None), reverse=True):
            keyword = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, offset).group(0)
            renamed = prefixed(keyword, prefix)
            text = text[:offset] + renamed + text[offset + len(keyword):]
        return text


def host_owners(selectors, source, flags):
    """(owner, selector) for every declaration of these selectors in the headers the source includes - the
    host's own, and the port's, since both are in the same tree. One clang run, filtered to the selectors in
    question, and cached by their names under $CHARON_HOME/cache: the answer is a property of the SDK, not of
    the file, and a group asks about the same handful of selectors in every one of its files."""
    key = hashlib.sha256(",".join(sorted(selectors)).encode()).hexdigest()[:16]
    folder = os.path.join(os.getenv("CHARON_HOME", os.path.join(os.getenv("HOME"), ".charon")), "cache")
    cached = os.path.join(folder, "prefix-selector-owners-" + key + ".json")
    if os.path.isfile(cached):
        with open(cached) as stream:
            return json.load(stream)
    dump = subprocess.run(["xcrun", "clang", *flags, "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json",
                           "-Xclang", "-ast-dump-filter=" + ",".join(sorted(selectors)), source],
                          capture_output=True, text=True)
    owners = []
    for node in documents(dump.stdout):
        collect(node, None, owners)
    if not os.path.isdir(folder):
        os.makedirs(folder)
    with open(cached, "w") as stream:
        json.dump(owners, stream)
    return owners


def collect(node, owner, owners):
    """Every (owner, selector) the tree declares, walking into interfaces, categories and properties."""
    if isinstance(node, list):
        for item in node:
            collect(item, owner, owners)
        return
    if not isinstance(node, dict):
        return
    kind = node.get("kind")
    if kind in ("ObjCInterfaceDecl", "ObjCCategoryDecl", "ObjCImplementationDecl", "ObjCCategoryImplDecl"):
        named = node.get("interface", {}).get("name") or node.get("name")
        if kind in ("ObjCCategoryDecl", "ObjCCategoryImplDecl"):
            named = node.get("interface", {}).get("name") or node.get("name")
        for item in node.get("inner", []):
            collect(item, named, owners)
        return
    if kind == "ObjCMethodDecl" and owner and node.get("name"):
        owners.append([owner, node["name"]])
    if kind == "ObjCPropertyDecl" and owner and node.get("name"):
        name = node["name"]
        owners.append([owner, name])
        owners.append([owner, "set" + name[0].upper() + name[1:] + ":"])
    for value in node.values():
        if isinstance(value, (list, dict)):
            collect(value, owner, owners)


def main():
    source_path, output_path, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    declarations = None
    if sys.argv[4].startswith("--declarations="):
        declarations = sys.argv.pop(4).split("=", 1)[1]
    flags = sys.argv[4:sys.argv.index("--")]
    objects = sys.argv[sys.argv.index("--") + 1:]
    carried = ported(objects)
    dump = subprocess.run(["xcrun", "clang", *flags, "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter=haron", source_path],
                          capture_output=True, text=True, check=True).stdout
    superclasses = runtime_superclasses()
    source = open(source_path, encoding="utf-8").read()
    rewriter = Rewriter(source, carried, superclasses)
    for document in documents(dump):
        rewriter.walk(document, None)
    if rewriter.candidates:
        wanted = {selector for _, selector in rewriter.candidates}
        declared = host_owners(wanted, source_path, flags)
        owners = {}
        for owner, selector in declared:
            owners.setdefault(selector, set()).add(owner)
        port = {entry[2] for entry in carried}
        for offset, selector in sorted(set(rewriter.candidates)):
            others = owners.get(selector, set())
            # the port alone defines it: no header in the SDK declares this selector, and the class that does
            # define it here is the one the category adds it to - a host class of the same name answering would
            # be the host's own method, and renaming the send would call that instead
            ours = {owner for _, owner, named in carried if named == selector}
            if selector not in port or (others - ours):
                # the host declares it, or the port does not define it here: the send stays as it is written
                rewriter.unresolved.append((offset, "%s, which the host's %s declares"
                                             % (selector, ", ".join(sorted(others)) or "headers")))
            else:
                rewriter.inserts.add(offset)
    for offset, selector in sorted(set(rewriter.unresolved)):
        line = source.count("\n", 0, offset) + 1
        print("%s:%d: a carried selector the rewrite cannot rename: %s" % (source_path, line, selector), file=sys.stderr)
    if rewriter.unresolved:
        sys.exit(1)
    rewritten = rewriter.result(prefix)
    open(output_path, "w", encoding="utf-8").write(rewritten)
    if declarations:
        with open(declarations, "a", encoding="utf-8") as header:
            for owner, sign, node in rewriter.signatures:
                header.write("@interface %s ()\n%s;\n@end\n" % (owner, declaration(sign, node, prefix)))


main()
