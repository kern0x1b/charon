import json
import os
import re
import subprocess
import sys
import tempfile
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


AVAILABILITY = re.compile(r"^(?:(?:API|NS)_[A-Z_]+|__attribute__)\s*(?:\((?:[^()]|\([^()]*\))*\)\s*)*")


def bare(qualified):
    text = qualified.replace("__kindof", "").replace("_Nonnull", "").replace("_Nullable", "").replace("*", "").replace("const", "")
    text = re.sub(r"<.*?>", "", text)
    text = text.strip()
    # An availability macro in front of the name. clang writes it into the qualType of a reference to a
    # class the SDK marks unavailable for the target being built for: `[UIScreen mainScreen]` under Mac
    # Catalyst reads as `API_UNAVAILABLE UIScreen *`, so this returned "API_UNAVAILABLE UIScreen". Every
    # name this function returns is looked up in carried, in the superclass chain or among the protocols,
    # so a name with the macro still on it matches nothing and the send is left exactly as written.
    # Measured on traits13: `-[UIScreen traitCollection]` was renamed in UIScreen+TraitEnvironment.m, which
    # defines it, and at none of its uses - so charon_current_base() reached the SYSTEM's UIScreen trait
    # collection, the port's +traitCollectionWithTraitsFromCollections: was handed a UITraitCollection that
    # is not a CharonHostUITraitCollection, and it raised where the class rename had moved its own check.
    # Only a leading run of these is dropped, and the argument list may nest one level, as
    # API_AVAILABLE(ios(13.0)) does. A qualType whose name is not preceded by one keeps what it always had.
    while True:
        stripped = AVAILABILITY.sub("", text, count=1).strip()
        if stripped == text:
            return text
        text = stripped


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


def declared(text):
    """A type as this tool is willing to write into a declaration. A declaration here only has to make the
    rewritten file compile - the send passes what the source passes it, and the receiver is untyped - which
    is what send_declaration() below has always said, so where a real type will not parse, `id` will:

      - a struct, union or enum BY VALUE. clang writes `struct CGPoint` for the type of
        -updateInteractiveMovementTargetPosition:(struct CGPoint)targetPosition, and neither that nor the
        parenthesised spelling compiles here: measured on listactions, whose CharonLists.m carries that send
        and whose UILayoutGuide category carries -charon_pinFrame:(struct CGRect)frame,
        "error: expected a type" at each.
      - a leading nullability keyword. clang writes `nullable NSData *` for a deprecated NSURLConnection
        method's result, and `+ (nullable NSData *)...` is not a type.
      - a type that is one of the PORT's own classes. The declarations header force-includes
        <UIKit/UIKit.h> and nothing else, and it is read by every file of the group, so a name the port
        declares in one of them is unknown to the rest: measured on listactions, whose CharonLists.m reads
        -charon_movement, whose type UICollectionView+InteractiveMovement.m declares and this header does
        not, and the group stopped on "error: expected a type". Charon is the port's own prefix by
        construction - no SDK type has it - so a base name that starts with it is one of ours.
    """
    if re.match(r"(?:struct|union|enum)\s+[A-Za-z_]", text):
        return "id"
    text = re.sub(r"^(?:_Nullable|_Nonnull|__nullable|__nonnull|nullable|nonnull|null_unspecified)\s+", "", text)
    base = re.sub(r"[^A-Za-z0-9_].*$", "", text.replace("*", " ").strip())
    if base.startswith("Charon"):
        return "id"
    return text


def declaration(sign, node, prefix):
    keywords = node["name"].split(":")
    parameters = [item for item in node.get("inner", []) if item.get("kind") == "ParmVarDecl"]
    head = "%s (%s)" % (sign, declared(spelled(node["returnType"])))
    if not parameters:
        return head + prefixed(node["name"], prefix)
    parts = []
    for index, parameter in enumerate(parameters):
        keyword = prefixed(keywords[index], prefix) if index == 0 else keywords[index]
        parts.append("%s:(%s)%s" % (keyword, declared(spelled(parameter["type"])), parameter.get("name", "value%d" % index)))
    return head + " ".join(parts)


def named(qualified):
    """The name a type names, whether clang wrote it bare or wrapped: an id-typed receiver is written
    id<UIContextMenuInteractionDelegate> and a protocol-typed one UIContextMenuInteractionDelegate, and both
    name the protocol."""
    inner = re.search(r"<([^<>]+)>", qualified)
    if inner:
        return inner.group(1).strip()
    return bare(qualified)


FAMILIES = ("mutableCopy", "copy", "init", "new", "alloc")


def nodes(text):
    """Every node of an AST dump, top level and nested."""
    def walk(node):
        if isinstance(node, list):
            for item in node:
                yield from walk(item)
        elif isinstance(node, dict):
            yield node
            for value in node.values():
                yield from walk(value)
    for document in documents(text):
        yield from walk(document)


def ported_classes(objects):
    """The classes the objects define, which a category's owner is not among: those are the host's own."""
    names = subprocess.run(["xcrun", "nm", *objects], capture_output=True, text=True, check=True).stdout
    return {line.split()[2][len("_OBJC_CLASS_$_"):] for line in names.splitlines()
            if len(line.split()) == 3 and line.split()[1] != "U" and line.split()[2].startswith("_OBJC_CLASS_$_")}


def framework_headers(flags):
    """Every header of every framework on the include path. Each framework's Headers directory is read with
    scandir and not by walking the tree: the include path names the whole SDK and a walk of it takes minutes,
    while the headers are one directory deep inside each framework."""
    roots = set()
    for index, word in enumerate(flags):
        if word in ("-iframework", "-F") and index + 1 < len(flags):
            roots.add(flags[index + 1])
        elif word == "-isysroot" and index + 1 < len(flags):
            roots.add(os.path.join(flags[index + 1], "System", "Library", "Frameworks"))
    for root in sorted(roots):
        try:
            entries = list(os.scandir(root))
        except OSError:
            continue
        for entry in entries:
            headers = os.path.join(entry.path, "Headers")
            if os.path.isdir(headers):
                try:
                    for header in os.scandir(headers):
                        if header.name.endswith(".h"):
                            yield header.path
                except OSError:
                    continue


def header_conformers(flags, classes):
    """{class: [protocol, ...]} for the classes given, read out of the frameworks' headers and cached beside the
    build: the answer is the same for every file of a group and the scan is the whole SDK."""
    import hashlib
    import tempfile
    wanted = sorted(classes)
    key = hashlib.sha256(("\\0".join([f for f in flags if f.startswith("-")] + wanted)).encode()).hexdigest()[:16]
    cache = os.path.join(tempfile.gettempdir(), "charon-prefix-headers-" + key + ".json")
    try:
        with open(cache, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        pass
    found = {}
    for header in framework_headers(flags):
        try:
            text = open(header, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for name in wanted:
            for match in re.finditer(r"@interface\s+" + re.escape(name) + r"\b[^@{;]*", text, re.S):
                line = match.group(0)
                opened = line.find("<")
                if opened < 0:
                    continue
                names = [p.strip() for p in line[opened + 1:line.find(">", opened)].split(",") if p.strip()]
                if names:
                    found.setdefault(name, []).extend(names)
    try:
        with open(cache, "w", encoding="utf-8") as handle:
            json.dump(found, handle)
    except OSError:
        pass
    return found


def conformers(sources, flags, classes):
    """{protocol: {class, ...}} for the classes given: the ones that adopt it.

    Two sources, because clang's JSON records the protocols a declaration adopts only for the declarations the
    file itself makes - UIControl's own adoption of UIContextMenuInteractionDelegate is in the SDK's header and
    nowhere in a dump - so the port's own classes come from the AST and the classes the port only extends come
    from the headers those declarations sit in.

    The tool runs once per file and a group is twenty files, and the answer depends on the group's sources and
    not on the file, so it is cached beside the build and paid once for the group."""
    import hashlib
    import tempfile
    key = hashlib.sha256(("\\0".join(sorted(sources) + [f for f in flags if f.startswith("-")] + sorted(classes)))
                         .encode()).hexdigest()[:16]
    cache = os.path.join(tempfile.gettempdir(), "charon-prefix-conformers-" + key + ".json")
    try:
        with open(cache, encoding="utf-8") as handle:
            return {name: set(values) for name, values in json.load(handle).items()}
    except (OSError, ValueError, AttributeError):
        pass
    owners = {}

    def adopt(name, protocol):
        if name and protocol:
            owners.setdefault(named(protocol), set()).add(name)

    for path in sources:
        dump = subprocess.run(["xcrun", "clang", *flags, "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json",
                                "-Xclang", "-ast-dump-filter=haron", path],
                              capture_output=True, text=True, check=True).stdout
        for node in nodes(dump):
            if node.get("kind") not in ("ObjCInterfaceDecl", "ObjCCategoryDecl"):
                continue
            if node["kind"] == "ObjCInterfaceDecl":
                name = node.get("name")
            else:
                # A category adopts what its own protocol list says, and the class it extends is the conformer.
                name = (node.get("interface") or {}).get("name")
            for protocol in node.get("protocols", []):
                adopt(name, protocol.get("name") or protocol.get("qualType"))
    for name, protocols in header_conformers(flags, classes).items():
        for protocol in protocols:
            adopt(name, protocol)
    try:
        with open(cache, "w", encoding="utf-8") as handle:
            json.dump({name: sorted(values) for name, values in owners.items()}, handle)
    except OSError:
        pass
    return owners


def send_declaration(sign, node, prefix):
    """The declaration of a selector a *send* now names, which a definition's declaration cannot be: a send
    carries its keywords in `selector` and not in `name`.

    The parameters are typed `id` and the return is `id`, which is all a declaration has to be for the
    rewritten file to compile: the send passes the arguments the source passes it and the receiver is typed by
    the protocol, so nothing narrower is wanted or checked here. The colons are the part that matters - a
    prototype without them does not parse at all."""
    keywords = [keyword for keyword in node["selector"].split(":") if keyword]
    parts = ["%s:(id)value0" % prefixed(keywords[0], prefix)]
    parts += ["%s:(id)value%d" % (keyword, index) for index, keyword in enumerate(keywords[1:], start=1)]
    return "%s (id)%s" % (sign, " ".join(parts))


def text_after(source, offset):
    """Whether there is a receiver between the `[` and the keyword at all, which a send to a class does not
    have - `[Foo bar:]` - and which therefore takes no cast."""
    return source[offset + 1:offset + 2] not in ("]", "")


class Rewriter:
    def __init__(self, source, carried, superclasses, protocol_owners=None, ported_classes=None, prefix="charonHost"):
        self.source = source
        # The prefix this rewrite is for. It is a parameter because the send rewritten as an explicit
        # message below has to spell the renamed selector itself, and spelling it needs the prefix;
        # before this, result() was the only place that had it.
        self.prefix = prefix
        self.carried = carried
        self.superclasses = superclasses
        self.ported_classes = ported_classes or set()
        # literal insertions, for a rewrite that is not a rename: the cast a protocol-typed receiver needs
        self.protocol_owners = protocol_owners or {}
        self.inserts = set()
        self.unresolved = []
        self.candidates = []
        self.signatures = []
        # literal insertions, for a rewrite that is not a rename: the cast a receiver of no class needs, see
        # main() and the note there
        self.replacements = {}

    def owns(self, kind, receiver, selector):
        while receiver:
            if (kind, receiver, selector) in self.carried:
                return True
            if receiver in self.protocol_owners:
                # A receiver typed as a protocol names no class, and the spelling a send to it needs is the
                # one its conformers carry. A receiver typed id<P> is one of P's conformers and the tool
                # cannot know which, so the send is only placeable when EVERY conformer carries the
                # selector: then each answers the prefixed name and the rewrite is right whichever the
                # receiver turns out to be. A conformer the port itself defines is already isolated by the
                # class rename and no member of it is ever carried, so it counts as one that does not --
                # which is the listmenus case, where the receiver is the port's own delegate while UIControl,
                # the SDK's other conformer, does carry the selector. One carrying it and one not is
                # ambiguity, and the send keeps the name the port gives it.
                conformers = self.protocol_owners[receiver]
                owners = {name for name in conformers
                          if (kind, name, selector) in self.carried and name not in self.ported_classes}
                # owners and conformers both empty is not agreement: there is nothing to place, so the
                # send is left alone.
                if not owners or owners != conformers:
                    return False
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
        # named(), not bare(): an id-typed receiver is written id<UIContextMenuInteractionDelegate> and
        # bare() strips the <...> whole, which leaves "id" -- the type, not the protocol this send is about.
        qualified = named(inner["type"]["qualType"])
        if qualified in self.protocol_owners and qualified not in self.superclasses:
            # A protocol-typed receiver: owns() places the send from the conformers, and the receiver is
            # named by the protocol here so the walk reports the send rather than dropping it silently.
            return "-", qualified
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
                    # The prefix goes at the **first keyword** of the send, found from the message
                    # expression's own range. A message expression's range does not reliably begin at the
                    # receiver - in UIContextMenuInteraction.m it begins five characters into it - so the
                    # end of `inner[0]` is the end of a *token*, not of the receiver, and a prefix inserted
                    # from there lands inside the keyword. The `[` is the anchor, the receiver is what
                    # follows it, and the keyword is the first occurrence of the selector's own first
                    # keyword from there.
                    #
                    # AND THE RANGE MAY BEGIN AT THAT `[`, which is what this file's
                    # `if ([self date:cursor matchesComponents:comps])` does: clang reports its begin one
                    # column before the keyword, ON the bracket. rfind's end is exclusive, so the bracket
                    # that opens THIS send is not a candidate and the anchor became the `[` of an earlier
                    # subscript - `given & units[i]` - and the search from there found the first `date` in
                    # the file, which is the parameter of the enclosing method four lines up. The rewrite
                    # then inserted `charonHost_` into a plain identifier and the compile failed with
                    # "use of undeclared identifier 'charonHost_date'" (measured, foundation2, on main).
                    # The bracket the expression begins on is its own, so it is taken first, and the
                    # search is bounded by the expression's end so a keyword can never be found past the
                    # send it belongs to.
                    offset = node["range"]["begin"]["offset"]
                    if self.source[offset:offset + 1] == "[":
                        begin = offset + 1
                    else:
                        opened = self.source.rfind("[", 0, offset)
                        begin = opened + 1 if opened >= 0 else offset
                    first = selector.split(":")[0]
                    # The window ends at the END of the expression's last token, not at where that token
                    # begins: clang reports `end` as the token's own offset with its length beside it, so
                    # stopping there excluded the keyword itself whenever the keyword IS the last token -
                    # `BOOL wasPaused = self.isPaused;` in NSProgress+State7.m:73, whose isPaused the
                    # rewrite then could not find and reported as unrenamable, and foundationbatch died on
                    # it. The same two fields are read this way a few lines below for the receiver.
                    stop = node["range"]["end"]["offset"] + node["range"]["end"].get("tokLen", 1)
                    match = re.compile(r"\b" + re.escape(first) + r"\b").search(self.source, begin, stop)
                    if match:
                        rewritten_as_send = False
                        if receiver in self.protocol_owners and node.get("inner"):
                            # A protocol-typed receiver, placed by owns() from its conformers. The prefixed
                            # name it now sends is declared on the CLASS the port's category defines it on -
                            # `-charonHostTraitCollection` in @interface UIScreen () - and a receiver typed
                            # id<UITraitEnvironment> sees nothing of that, so the rewritten file did not
                            # compile:
                            #   UITraitCollection.m:137:41: error: property 'charonHostTraitCollection' not
                            #   found on object of type 'const __strong id<UITraitEnvironment>'
                            # A protocol cannot be given the member either: @protocol P () carrying a method
                            # is not valid Objective-C, and send_declaration() above is dead code because that
                            # was the shape it wrote. So the receiver is cast to id, which accepts a selector
                            # declared anywhere - the same move, and for the same reason, as the candidate
                            # case further down. owns() has already established that every conformer carries
                            # the selector, so what is lost is the compiler's check of a call that holds.
                            # The cast is in the rewritten copy only; the port's own source is untouched.
                            #
                            # The receiver is inner[0]'s own range and NOT the bracket the send's begin offset
                            # leads to. clang reports a message expression's range at the enclosing send when
                            # the receiver is dot syntax, so `[previous addObject:environment.traitCollection]`
                            # put the inner send's begin one character into the OUTER `[`, and anchoring there
                            # produced `[(id)(previous addObject:environment.)charonHostTraitCollection]`. The
                            # receiver expression is a real sub-expression with a range of its own.
                            span = node["inner"][0]["range"]
                            start = span["begin"]["offset"]
                            receiver_end = start + span["end"].get("tokLen", 1)
                            if receiver_end < len(self.source) and self.source[receiver_end] == ".":
                                # Dot syntax needs the whole send rewritten, not only the receiver cast:
                                # clang resolves `x.p` on an `id` by looking up a DECLARED property, and there
                                # is none to find, so it still answered
                                #   error: property 'charonHostTraitCollection' not found on object of type 'id'
                                # with the receiver correctly typed as id. Dot syntax IS this send, so the
                                # copy spells it the way it means it.
                                whole_end = node["range"]["end"]["offset"] + node["range"]["end"].get("tokLen", 1)
                                self.replacements[start] = (
                                    whole_end, "[(id)(%s) %s]" % (self.source[start:receiver_end],
                                                                 prefixed(selector, self.prefix)))
                                rewritten_as_send = True
                            else:
                                self.replacements[start] = (receiver_end, "((id)%s)" % self.source[start:receiver_end])
                        if not rewritten_as_send:
                            self.inserts.add(match.start())
                    else:
                        self.unresolved.append(
                            (offset, "%s, whose first keyword the rewrite cannot find" % selector))
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
        # One pass, from the back, over the renames and the literals together: a rename below a literal shifts
        # its offset, so the two cannot be applied one set after the other.
        edits = [(offset, "rename") for offset in self.inserts if offset is not None]
        edits += [(offset, "literal") for offset in self.replacements]
        text = self.source
        for offset, kind in sorted(edits, reverse=True):
            if kind == "literal":
                end, literal = self.replacements[offset]
                text = text[:offset] + literal + text[end:]
            else:
                keyword = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, offset).group(0)
                text = text[:offset] + prefixed(keyword, prefix) + text[offset + len(keyword):]
        return text


def sdk_key(flags):
    """What the declarations below belong to: the SDK the sources are compiled against."""
    for index, flag in enumerate(flags):
        if flag == "-isysroot" and index + 1 < len(flags):
            return flags[index + 1]
    return ""


def sdk_owners(flags):
    """selector -> the classes that declare it, for everything UIKit and Foundation declare.

    One empty translation unit per SDK, imported and dumped whole, because -ast-dump-filter applies to the
    top-level declaration and so never reaches the method declarations inside a host's @interface. The map is a
    property of the SDK and not of the file, so it is built once and cached by the SDK's own path; a group
    then only looks a selector up."""
    key = hashlib.sha256(sdk_key(flags).encode()).hexdigest()[:16]
    folder = os.path.join(os.getenv("CHARON_HOME", os.path.join(os.getenv("HOME"), ".charon")), "cache")
    cached = os.path.join(folder, "sdk-objc-owners-" + key + ".json")
    if os.path.isfile(cached):
        with open(cached) as stream:
            return {name: set(owners) for name, owners in json.load(stream).items()}
    with tempfile.TemporaryDirectory() as work:
        empty = os.path.join(work, "sdk.m")
        with open(empty, "w") as stream:
            stream.write("#import <UIKit/UIKit.h>\n#import <Foundation/Foundation.h>\n")
        dump = subprocess.run(["xcrun", "clang", *flags, "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json", empty],
                              capture_output=True, text=True)
    owners = {}
    for document in documents(dump.stdout):
        collect(document, None, owners)
    if not owners:
        print("%s: the SDK's own declarations could not be read; %s says why" % (sdk_key(flags), dump.stderr.strip()[:200]),
              file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(folder):
        os.makedirs(folder)
    with open(cached, "w") as stream:
        json.dump({name: sorted(classes) for name, classes in owners.items()}, stream)
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
    if kind in ("ObjCInterfaceDecl", "ObjCCategoryDecl", "ObjCImplementationDecl", "ObjCCategoryImplDecl",
                "ObjCProtocolDecl"):
        named = node.get("interface", {}).get("name") or node.get("name")
        for item in node.get("inner", []):
            collect(item, named, owners)
        return
    if kind == "ObjCMethodDecl" and owner and node.get("name"):
        owners.setdefault(node["name"], set()).add(owner)
    if kind == "ObjCPropertyDecl" and owner and node.get("name"):
        name = node["name"]
        owners.setdefault(name, set()).add(owner)
        owners.setdefault("set" + name[0].upper() + name[1:] + ":", set()).add(owner)
    for value in node.values():
        if isinstance(value, (list, dict)):
            collect(value, owner, owners)


FIXTURE = """#import <Foundation/Foundation.h>
@protocol CharonWidgetDelegate <NSObject>
- (void)widgetSaysHello;
- (NSString *)widgetGreeting;
@end
@interface CharonWidget : NSObject <CharonWidgetDelegate>
- (void)widgetSaysHello;
- (NSString *)widgetGreeting;
@end
@implementation CharonWidget
- (void)widgetSaysHello
{
}
- (NSString *)widgetGreeting
{
    return @"hello";
}
- (void)greet:(id<CharonWidgetDelegate>)delegate
{
    [delegate widgetSaysHello];
}
@end
@interface CharonGreeting : NSObject
@end
@implementation CharonGreeting
- (void)collect:(id<CharonWidgetDelegate>)delegate into:(NSMutableArray *)out
{
    // The spelling that made this rewrite fail to compile, read off UITraitCollection.m: a property read
    // through a protocol-typed receiver. clang records it as a message expression whose range begins at the
    // ENCLOSING send, so neither the begin offset nor a search backwards for `[` finds this send's own
    // bracket - the receiver expression's own range is the only thing that does.
    [out addObject:delegate.widgetGreeting ?: @"none"];
}
@end
"""


def selftest():
    """A protocol-typed receiver, placed from the conformers that carry the selector -- and the same run
    without the map, which must NOT place it. The second case is the point: it is what this tool did before
    the conformers existed, and an assertion that holds in both cases would be testing the fixture, not the
    mechanism. One file, one AST dump, no build."""
    import subprocess
    import tempfile
    handle, path = tempfile.mkstemp(suffix=".m")
    with os.fdopen(handle, "w", encoding="utf-8") as out:
        out.write(FIXTURE)
    try:
        dump = subprocess.run(["xcrun", "clang", "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json",
                               "-Xclang", "-ast-dump-filter=haron", path],
                              capture_output=True, text=True, check=True).stdout
        carried = {("-", "CharonWidget", "widgetSaysHello"), ("-", "CharonWidget", "widgetGreeting")}
        # the expected spelling comes from prefixed(), the function the rewrite itself uses, so the assertion
        # is about whether the send was placed and not about how this tool spells a prefixed selector
        renamed = prefixed("widgetSaysHello", "charonHost")

        def rewrite(owners):
            rewriter = Rewriter(FIXTURE, carried, {}, owners, set(), "charonHost")
            for document in documents(dump):
                rewriter.walk(document, None)
            return rewriter.result("charonHost")

        placed = rewrite({"CharonWidgetDelegate": {"CharonWidget"}})
        print("ok   the send to id<CharonWidgetDelegate> is placed: %s"
              % ("yes" if renamed in placed else "NO -- the conformers did not place it"))
        control = rewrite({})
        # the control has to show the send UNCHANGED as well as unprefixed: a rewrite that dropped the body
        # would pass "the prefixed name is absent" for the wrong reason
        quiet = renamed not in control and "[delegate widgetSaysHello]" in control
        print("%s   the same send with no conformer map is left exactly as written, which is what proves"
              % ("ok  " if quiet else "FAIL"))
        print("     the first line is about the mechanism and not about the fixture")
        if renamed not in placed or not quiet:
            print("FAIL the protocol-typed send is not placed from its conformers, or the control placed it too",
                  file=sys.stderr)
            sys.exit(1)
        # A property read through a protocol-typed receiver, which is what UITraitCollection.m does and what
        # the first case above does not cover. Two things have to hold and neither holds because of the
        # other: the dot becomes the send it stands for, because clang resolves a property on an `id` by
        # looking up a DECLARED property and there is none to find; and the receiver is cast to id, because
        # the prefixed name is declared on the class the port's category defines it on, which id<P> cannot
        # see. A rewrite that did the first and not the second compiled to
        # "error: property 'charonHostTraitCollection' not found on object of type 'id'".
        as_send = "[(id)(delegate) charonHostWidgetGreeting]"
        spelled = as_send in placed and "[out addObject:delegate.widgetGreeting" not in placed
        print("%s   a protocol-typed property read is rewritten as the send it stands for: %s"
              % ("ok  " if spelled else "FAIL",
                 as_send if spelled else next((line.strip() for line in placed.splitlines()
                                               if "addObject" in line), "<no addObject line>")))
        if not spelled:
            print("FAIL the protocol-typed property read was not rewritten as a send on an id receiver",
                  file=sys.stderr)
            sys.exit(1)
    finally:
        os.unlink(path)


def main():
    source_path, output_path, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    declarations = None
    if sys.argv[4].startswith("--declarations="):
        declarations = sys.argv.pop(4).split("=", 1)[1]
    group_sources = None
    if sys.argv[4].startswith("--sources="):
        group_sources = [p for p in sys.argv.pop(4).split("=", 1)[1].split(",") if p]
    flags = sys.argv[4:sys.argv.index("--")]
    objects = sys.argv[sys.argv.index("--") + 1:]
    carried = ported(objects)
    dump = subprocess.run(["xcrun", "clang", *flags, "-fsyntax-only", "-w", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter=haron", source_path],
                          capture_output=True, text=True, check=True).stdout
    superclasses = runtime_superclasses()
    source = open(source_path, encoding="utf-8").read()
    # The group is one release: the conformers of a protocol are the same for every file of it, so they are
    # read once for the group and handed to the rewriter, which cannot answer for a protocol receiver
    # without them. A caller that names no --sources gets no map, and a protocol-typed send is then left
    # alone rather than placed against a guess.
    classes = ported_classes([*objects, *superclasses.values()])
    owners = conformers(group_sources or [source_path], flags, classes) if group_sources else {}
    rewriter = Rewriter(source, carried, superclasses, owners, classes, prefix)
    for document in documents(dump):
        rewriter.walk(document, None)
    if rewriter.candidates:
        wanted = {selector for _, selector in rewriter.candidates}
        owners = sdk_owners(flags)
        wanted.discard("")
        port = {entry[2] for entry in carried}
        for offset, selector in sorted(set(rewriter.candidates)):
            others = owners.get(selector) or set()
            # the port alone defines it: no header in the SDK declares this selector, and the class that does
            # define it here is the one the category adds it to - a host class of the same name answering would
            # be the host's own method, and renaming the send would call that instead
            ours = {owner for _, owner, named in carried if named == selector}
            if selector not in port or (others - ours):
                # the host declares it, or the port does not define it here: the send stays as it is written
                rewriter.unresolved.append((offset, "%s, which the host's %s declares"
                                             % (selector, ", ".join(sorted(others)) or "headers")))
            else:
                # A receiver the port alone defines, and the receiver is not a class this rewrite can name, so
                # the renamed selector is one the receiver does not declare. A receiver of type `id` accepts any
                # selector declared anywhere, so the receiver is cast in the rewritten copy - which is the only
                # place it changes, and the port's own source is untouched.
                begin = rewriter.source.rfind("[", 0, offset)
                begin = begin + 1 if begin >= 0 else offset
                selector_first = selector.split(":")[0]
                renamed_first = prefixed(selector_first, prefix)
                found = re.compile(re.escape(renamed_first)).search(rewriter.source, begin)
                if found is not None and found.start() < offset:
                    rewriter.replacements[begin] = (offset, "(id)(%s)" % rewriter.source[begin:offset].strip())
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


if "--selftest" in sys.argv:
    selftest()
else:
    main()
