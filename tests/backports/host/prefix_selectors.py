import json
import re
import subprocess
import sys


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
    names = subprocess.run(["xcrun", "nm", *objects], capture_output=True, text=True, check=True).stdout
    found = set()
    for kind, owner, selector in re.findall(r"([-+])\[([A-Za-z0-9_]+)\(Charon[A-Za-z0-9_]*\) ([A-Za-z0-9_:]+)\]", names):
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
    for family in FAMILIES:
        rest = keyword[len(family):]
        if keyword.startswith(family) and (not rest or rest[0].isupper()):
            return family + prefix[0].upper() + prefix[1:].rstrip("_") + rest
    return prefix + keyword


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
        if qualified in ("instancetype", "id") and context:
            target = inner
            while target.get("kind") == "ImplicitCastExpr" and target.get("inner"):
                target = target["inner"][0]
            if target.get("kind") == "DeclRefExpr" and target.get("referencedDecl", {}).get("name") == "self":
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
        kind = node.get("kind")
        if kind == "ObjCCategoryImplDecl":
            owner = node.get("interface", {}).get("name")
            for item in node.get("inner", []):
                self.walk(item, ("-", owner))
            return
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
                self.unresolved.append((node["range"]["begin"]["offset"], selector))
        if kind == "ObjCPropertyRefExpr" and node.get("property", {}).get("name"):
            name = node["property"]["name"]
            accessors = []
            if node.get("isMessagingGetter"):
                accessors.append(name)
            if node.get("isMessagingSetter"):
                accessors.append("set" + name[0].upper() + name[1:] + ":")
            receiver = node.get("inner", [{}])[0].get("type", {}).get("qualType", "")
            receiver = context[1] if bare(receiver) in ("id", "instancetype") and context else bare(receiver)
            for accessor in accessors:
                if self.owns("-", receiver, accessor):
                    self.unresolved.append((node["range"]["begin"]["offset"], accessor + " through dot syntax"))
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
    for offset, selector in sorted(set(rewriter.unresolved)):
        line = source.count("\n", 0, offset) + 1
        print("%s:%d: a carried selector %s whose receiver the rewrite cannot place" % (source_path, line, selector), file=sys.stderr)
    if rewriter.unresolved:
        sys.exit(1)
    rewritten = rewriter.result(prefix)
    open(output_path, "w", encoding="utf-8").write(rewritten)
    if declarations:
        with open(declarations, "a", encoding="utf-8") as header:
            for owner, sign, node in rewriter.signatures:
                header.write("@interface %s ()\n%s;\n@end\n" % (owner, declaration(sign, node, prefix)))


main()
