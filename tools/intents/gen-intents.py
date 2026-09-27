#!/usr/bin/env python3
"""Emit the Intents backport's data classes from the SDK's own declarations.

The Intents surface of SDK 26.2 is 3440 rows for the port, 308 of them classes.
Writing them by hand would take a month and get most of them wrong in the same
way, so they are generated from what the compiler itself says a class is: the
Objective-C AST of the SDK the port compiles against, which is the one
description of the contract that cannot be a guess.

What is generated:

  * one object file per release the release caches measure a class symbol first
    exported in, because an object carries API of exactly one release
    (modules/apple/backports.lua's check_releases). The release is read from the
    file the caller passes, which tools/intents/measure-intents.lua measured
    against the real caches; the header's own availability annotation is not used
    for it, and it is wrong where the two disagree (INPaymentStatusResolutionResult
    is exported by iOS 10.3, and the header says 10.0).
  * for each class: an ivar per stored property, the synthesised properties, the
    setters with the ownership the header declares, every declared initialiser,
    NSSecureCoding and NSCopying where the header asks for them, the resolution
    result's value / values to disambiguate / value to confirm, and a body for
    every other method the header declares.
  * the properties a conformed protocol requires and the class does not declare
    itself, so a class really conforms (INSpeakable's spokenPhrase and the rest).

What is not generated, because a generated body would be the silent fake the
rules forbid: INIntent's identifier and its image parameters, INInteraction's
donation and deletion, INVocabulary's store, INPreferences' answers for a
release with no Siri, INImage's ways of being made, INPaymentMethod's Apple Pay
method, INRideCompletionStatus' derived answers, and INIntentResolutionResult's
needsValue / notRequired / unsupported. Those are hand written in
CharonIntents100.m and this generator leaves their classes out.

A member whose type is an Intents class of a group this delivery does not carry
is left out with `@dynamic` and takes a registry entry of its own that says so,
rather than answering nil or zero: the mark stays on the header, so a port
cannot call it, and respondsToSelector: says no instead of crashing.

Usage:
    tools/intents/gen-intents.py --sdk <iPhoneOS*.sdk> --dump <ast.json> \\
        --classes <file> --release <measured> --out <file.m>

    --dump is
        clang -target arm64-apple-ios<ver> -isysroot <sdk> -fsyntax-only
              -x objective-c -Wno-everything -Xclang -ast-dump=json umbrella.m
    where umbrella.m holds `#import <Intents/Intents.h>`, and --classes is one
    class name per line, the classes of exactly one release.
"""

import argparse
import json
import re
import sys

# The ten classes whose bodies are hand written in CharonIntents100.m.
HAND_WRITTEN = {
    "INParameter",
    "INIntent",
    "INIntentResolutionResult",
    "INInteraction",
    "INImage",
    "INSpeakableString",
    "INVocabulary",
    "INPreferences",
    "INExtension",
    "INPaymentMethod",
    "INRideCompletionStatus",
}

# The base every resolution result shares, and the factories that fill it.
RESOLUTION_BASE = "INIntentResolutionResult"

# Where an initialiser parameter goes when the header's own names differ. Each line names the
# class, the selector part and the property or properties the value belongs in, with the header's
# own words for why; a parameter not in this table and not named after a property stops the
# generator rather than being dropped. Every line was read off the header of iPhoneOS16.4 and is
# repeated in facts/Intents/Intents.md.
PARAMETER_PROPERTIES = {
    # INBillPayee and INPaymentAccount take the number of an account and expose it as
    # accountNumber; the class has exactly one NSString property, which is that one.
    ("INBillPayee", "initWithNickname:number:organizationName:", "number"): ["accountNumber"],
    ("INPaymentAccount", "initWithNickname:number:accountType:organizationName:", "number"): ["accountNumber"],
    ("INPaymentAccount",
     "initWithNickname:number:accountType:organizationName:balance:secondaryBalance:",
     "number"): ["accountNumber"],
    # INPriceRange: "the lowest of the two prices used to construct this range" is the header's
    # own comment on minimumPrice, and the highest is maximumPrice, and initWithPrice: gives one
    # price that is both ends of the range.
    ("INPriceRange", "initWithRangeBetweenPrice:andPrice:currencyCode:", "firstPrice"): ["minimumPrice"],
    ("INPriceRange", "initWithRangeBetweenPrice:andPrice:currencyCode:", "secondPrice"): ["maximumPrice"],
    ("INPriceRange", "initWithPrice:currencyCode:", "price"): ["minimumPrice", "maximumPrice"],
    # INInteraction's designated initialiser spells the response intentResponse.
    ("INInteraction", None, "response"): ["intentResponse"],
}


# Properties whose ownership is copy: the setter copies, the rest retain.
COPIED = re.compile(
    r"^(NSString|NSAttributedString|NSMutableString|NSDictionary|NSMutableDictionary|NSArray|"
    r"NSMutableArray|NSSet|NSMutableSet|NSOrderedSet|NSMutableOrderedSet|NSIndexSet|NSData|"
    r"NSDate|NSURL|NSUUID|NSCharacterSet|NSLocale|NSDateComponents|NSRegularExpression|"
    r"INSpeakableString|INImage|NSError)$")

# The SDK writes its macros in front of, after, or inside a type: API_AVAILABLE, API_UNAVAILABLE,
# NS_REFINED_FOR_SWIFT, API_DEPRECATED_WITH_REPLACEMENT, NS_SWIFT_NAME and the rest are all one
# word of capitals and underscores, and one of them carries a parenthesised argument. Every one
# is removed wherever it stands, because a type spelled with a macro in it does not compile.
MACRO = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b")


def clean(text):
    """A type as the compiler spells it, without the SDK's macros or its nullability."""
    text = re.sub(r"_\s*(Nonnull|Nullable)\b", "", text or "")
    while True:
        found = MACRO.search(text)
        if not found:
            return text.strip()
        end = found.end()
        if text[end:end + 1] == "(":
            depth, index = 0, end
            while index < len(text):
                if text[index] == "(":
                    depth += 1
                elif text[index] == ")":
                    depth -= 1
                    if depth == 0:
                        index += 1
                        break
                index += 1
            end = index
        text = text[:found.start()] + " " + text[end:]


def objects(text):
    """Every top-level JSON object of a clang -ast-dump=json stream, in order."""
    decoder = json.JSONDecoder()
    index, length, out = 0, len(text), []
    while index < length:
        while index < length and text[index] in " \t\r\n":
            index += 1
        if index >= length:
            break
        node, index = decoder.raw_decode(text, index)
        out.append(node)
    return out


def top_level(path):
    """The translation unit's own declarations, in order.

    clang writes one JSON object for the whole translation unit, so the declarations are its
    `inner`, one entry per header.
    """
    found = []
    for node in objects(open(path, "r", errors="replace").read()):
        if node.get("kind") == "TranslationUnitDecl":
            found.extend(node.get("inner") or [])
        else:
            found.append(node)
    return found


def base_type(qual):
    """The name a type is written with, its pointers and qualifiers off."""
    text = spelled(qual)
    if text.startswith("void (^") or text.startswith("block"):
        return "block"
    text = re.sub(r"\bvoid\s*\(\s*\^[^)]*\)\s*\([^)]*\)", "block", text)
    text = re.sub(r"<[^<>]*>", "", text)
    text = text.replace("*", "")
    text = re.sub(r"\([^()]*\)", "", text)
    text = text.replace("const", "").replace("volatile", "").replace("struct", "").strip()
    return text.split()[0] if text.split() else text


def spelled(qual):
    """A type as a definition spells it: the macros off, nullability kept, spacing even."""
    return re.sub(r"\s*\*\s*", " * ", re.sub(r"\s+", " ", clean(qual))).replace("* ", "*").strip() or "id"


def has_attr(node, kind):
    """Whether a declaration carries an attribute: Unavailable, Designated, Optional, ..."""
    return any(child.get("kind") == kind for child in node.get("inner") or [])


def type_of(member):
    return (member.get("type") or {}).get("qualType") or "id"


def returns_of(method):
    return (method.get("returnType") or {}).get("qualType") or "id"


def parameters_of(method):
    return [(type_of(c), c.get("name") or "value")
            for c in method.get("inner") or [] if c.get("kind") == "ParmVarDecl"]


def setter_name(name):
    return "set" + name[0].upper() + name[1:] + ":"


def is_copy(member, kind):
    if member.get("copy"):
        return True
    if member.get("retain") or member.get("strong"):
        return False
    return bool(COPIED.match(base_type(kind)))


class Interface:
    """One @interface as the compiler sees it, and everything it declares."""

    def __init__(self, node):
        self.node = node
        self.name = node.get("name")
        self.file = (node.get("loc") or {}).get("file") or ""
        self.superclass = (node.get("super") or {}).get("name")
        self.protocols = [p.get("name") for p in node.get("protocols") or [] if p.get("name")]
        self.properties = [c for c in node.get("inner") or [] if c.get("kind") == "ObjCPropertyDecl"]
        self.methods = [c for c in node.get("inner") or [] if c.get("kind") == "ObjCMethodDecl"]

    def declared(self, name):
        return name in {p.get("name") for p in self.properties}

    def method(self, selector):
        for candidate in self.methods:
            if candidate.get("name") == selector:
                return candidate
        return None

    def spelled_selector(self, method):
        parts, index = [], 0
        parameters = parameters_of(method)
        for part in (method.get("name") or "").split(":")[:-1]:
            kind, parameter = parameters[index] if index < len(parameters) else ("id", "value")
            parts.append("%s:(%s)%s" % (part, spelled(kind), parameter))
            index += 1
        return " ".join(parts)


def conformed_by(interface, interfaces):
    """The protocols a class really conforms to, its own and its superclasses'.

    A subclass of INIntent writes `<NSCopying, NSSecureCoding>` nowhere: the conformance is
    inherited, so reading the class's own protocol list alone would have every subclass of a
    conforming base left without the coding and copying the header promises for it.
    """
    found, seen, name = [], set(), interface
    while name and name not in seen:
        seen.add(name)
        for protocol in name.protocols:
            if protocol not in found:
                found.append(protocol)
        name = interfaces.get(name.superclass)
    return found


SYNTHESISED = re.compile(r"^\s*@synthesize ([A-Za-z_][\w_]*)\s*=")
DYNAMIC = re.compile(r"^\s*@dynamic ([A-Za-z_][\w_]*)\s*;")
DEFINITION = re.compile(r"^\s*([-+]) \(([^)]*)\)(.*)$")
SELECTOR_PART = re.compile(r"([A-Za-z_][\w_]*):\(")


def definitions(lines):
    """The method definitions of a block, each one line, whether or not it spans several.

    A definition the SDK's own header is long for is written over several lines
    (-initWithType:name:identificationHint:icon:), and a reader that took one line at a time would
    see only its first keyword and report a selector no caller ever writes.
    """
    joined, current = [], None
    for line in lines:
        if current is not None:
            current += " " + line.strip()
            if line.rstrip().endswith("{") or line.rstrip().endswith(";"):
                joined.append(current)
                current = None
            continue
        if DEFINITION.match(line) and not line.rstrip().endswith("{"):
            current = line.strip()
    if current is not None:
        joined.append(current)
    return joined


def answer_of(lines, name):
    """What the emitted @implementation of one class carries, read back out of the text.

    The registry is written from this, not from the declarations the generator read, so an entry
    can never say a member is implemented when the file does not implement it.
    """
    properties, dynamic, methods = set(), set(), set()
    for line in lines + definitions(lines):
        found = SYNTHESISED.match(line)
        if found:
            properties.add(found.group(1))
            continue
        found = DYNAMIC.match(line)
        if found:
            dynamic.add(found.group(1))
            continue
        found = DEFINITION.match(line)
        if found:
            spelled = found.group(3)
            selector = "".join(part.group(1) + ":" for part in SELECTOR_PART.finditer(spelled)) \
                or spelled.strip()
            if selector:
                methods.add("%s[%s %s]" % (found.group(1), name, selector))
    return {
        "properties": sorted(properties),
        "dynamic": sorted(dynamic),
        "methods": sorted(methods),
    }


def collect(path):
    """Every real @interface, @protocol and typedef name in a dump.

    A category on a class is part of that class's surface, not a class of its own: INPerson's
    aliases and suggestionType are declared in `INPerson (INInteraction)` and the corpus counts
    them as INPerson's properties, so they are folded into the class here. A category carries no
    class symbol of its own, so folding it in does not put two names in the same object file.
    """
    interfaces, protocols, typedefs, categories, forward = {}, {}, set(), {}, set()
    for node in top_level(path):
        kind, name = node.get("kind"), node.get("name")
        if not name:
            continue
        if kind in ("TypedefDecl", "EnumDecl"):
            typedefs.add(name)
        elif kind == "ObjCInterfaceDecl":
            if not (node.get("inner") or []):
                forward.add(name)   # an @class declaration: no definition of it anywhere
            elif name not in interfaces or len(node["inner"]) > len(interfaces[name].node["inner"]):
                interfaces[name] = Interface(node)
        elif kind == "ObjCProtocolDecl":
            if name not in protocols or len(node.get("inner") or []) > len(protocols[name].get("inner") or []):
                protocols[name] = node
        elif kind == "ObjCCategoryDecl":
            owner = (node.get("interface") or {}).get("name")
            if owner:
                categories.setdefault(owner, []).append(node)
    for owner, found in categories.items():
        interface = interfaces.get(owner)
        if not interface:
            continue
        for node in found:
            for member in node.get("inner") or []:
                if member.get("kind") == "ObjCPropertyDecl":
                    # A property a category declares cannot be synthesised in the class's own
                    # @implementation ("property declared in category cannot be implemented in
                    # class implementation"), so it is marked and given a category of its own.
                    member = dict(member)
                    member["category"] = node.get("name")
                    interface.properties.append(member)
                elif member.get("kind") == "ObjCMethodDecl":
                    interface.methods.append(member)
    return interfaces, protocols, typedefs, forward


def property_names(members):
    """The names a property answers to: its own, and the getter the header gives it.

    INPerson's contactSuggestion is declared `getter=isContactSuggestion`, and the initialiser
    that sets it spells the parameter isContactSuggestion:, so matching only the property's own
    name would leave that value with nowhere to go.
    """
    found = {}
    for member in members:
        name = member.get("name")
        if not name or member.get("class"):
            continue
        found[name] = name
        getter = (member.get("getter") or {}).get("name")
        if getter and getter != name:
            found[getter] = name
    return found


def required_properties(protocol):
    """The properties a protocol requires, so a conformer really conforms."""
    return {member["name"]: member for member in protocol.get("inner") or []
            if member.get("kind") == "ObjCPropertyDecl" and member.get("name")
            and not has_attr(member, "OptionalAttr")}


# The frameworks the release itself carries, whose classes a backport may use. EventKit is not one
# of them: libIntentsBackports does not link it, so a type of its name that the headers only
# forward declare is a class this package does not carry.
SYSTEM = re.compile(r"^(NS|CL|CF|CG|UI|WK|CA|AV|SK|MK|QL|AL|SCN|PH|MP)[A-Z]")

def deferred_type(qual, known, carried, forward=()):
    """The class a type names that this delivery does not carry.

    Two ways a type names a class that is not here: an Intents class of a group this delivery
    does not carry, and a class the SDK's headers only @class forward declare and no header of
    the port's own SDK defines - INDateComponentsRange's EKRecurrenceRule, which is EventKit's
    and which the Intents header of iPhoneOS 16.4 names where iPhoneOS 26.2 names an
    INRecurrenceRule. A body that stored one would not compile against a forward declaration.
    """
    name = base_type(qual)
    if name in known and name not in carried:
        return name
    if name in forward and name not in carried and not SYSTEM.match(name):
        return name
    return None


def designated(interface, interfaces):
    """The initialiser the header marks as the class's own, and its parameters.

    A subclass's own designated initialiser is not what a subclass chains to: it chains to the
    one its *superclass* declares, which is where the state the superclass keeps is set.
    """
    seen, name = set(), interfaces.get(interface.superclass)
    while name and name.name not in seen:
        seen.add(name.name)
        for method in name.methods:
            if has_attr(method, "ObjCDesignatedInitializerAttr") and ":" in (method.get("name") or ""):
                return method
        name = interfaces.get(name.superclass)
    return None


def ancestor_property(interface, property, interfaces):
    """Where a property of a superclass is declared, and whether it can be written."""
    seen, name = set(), interfaces.get(interface.superclass)
    while name and name.name not in seen:
        seen.add(name.name)
        for member in name.properties:
            if member.get("name") == property:
                return member
        name = interfaces.get(name.superclass)
    return None


def zero_of(qual):
    kind = spelled(qual)
    if kind.rstrip().endswith("*") or kind == "id" or kind == "instancetype":
        return "nil"
    if kind == "BOOL":
        return "NO"
    return "0"


def own_init_unavailable(interface, interfaces):
    """Whether the -init a [super init] would reach is marked unavailable in the SDK's header.

    The whole chain is walked, not the class and its direct superclass: a resolution result three
    levels up the chain is what declares it, and a [super init] one level below that is refused
    for the same reason.
    """
    seen, name = set(), interface
    while name is not None and name.name not in seen:
        seen.add(name.name)
        declared = name.method("init")
        if declared is not None and has_attr(declared, "UnavailableAttr"):
            return True
        name = interfaces.get(name.superclass)
    return False


def resolution_result(name, interfaces):
    """Whether a class name is a resolution result, by the superclass the SDK gives it."""
    seen = set()
    while name and name not in seen:
        if name == RESOLUTION_BASE:
            return True
        seen.add(name)
        found = interfaces.get(name)
        name = found.superclass if found else None
    return False


def initialiser(interface, method, states, spellings, interfaces):
    """The body of an initialiser: every parameter kept, in the state the class really has.

    A parameter that names a property of this class goes in that class's own ivar. One that
    names a writable property of a superclass goes through its setter, after the class's own
    state is in place. One that names a *read-only* property of a superclass - INRestaurantGuest's
    nameComponents, which is INPerson's - can only be kept by the superclass's own designated
    initialiser, so that is what is called, with the values this initialiser has and nil or zero
    for the arguments it does not: a subclass initialiser that does not offer them has no values
    for them, and that is what the object then holds.

    A parameter that names nothing the class or a superclass declares is looked up in
    PARAMETER_PROPERTIES, and if it has no line there the generator stops: a value silently not
    kept is the failure this whole package exists to avoid.
    """
    selector = method.get("name") or ""
    lines = ["- (instancetype)%s" % interface.spelled_selector(method), "{"]

    given, after, adopt, chained = {}, [], [], False
    for kind, parameter in parameters_of(method):
        # A parameter that is itself a resolution result is the whole state of this one: the class
        # answers what the result it was given answers, which is what a payee or a currency
        # amount that may be unsupported for a reason is asking for.
        if resolution_result(base_type(kind), interfaces):
            adopt.append(parameter)
            continue
        name = spellings.get(parameter, parameter)
        given[name] = (kind, parameter)
        if ("_" + name) in states:
            continue
        member = ancestor_property(interface, name, interfaces)
        if member is None:
            named = PARAMETER_PROPERTIES.get((interface.name, selector, parameter)) or \
                PARAMETER_PROPERTIES.get((interface.name, None, parameter)) or []
            if not named:
                raise SystemExit("%s: the parameter %s of %s names no property of the class or of"
                                 " a superclass, and PARAMETER_PROPERTIES says nowhere it goes, so"
                                 " this generator stops rather than drop it"
                                 % (interface.name, parameter, selector))
            for property_name in named:
                if ("_" + property_name) not in states:
                    raise SystemExit("%s: PARAMETER_PROPERTIES sends the parameter %s of %s to %s,"
                                     " which is not a property of the class"
                                     % (interface.name, parameter, selector, property_name))
                given.setdefault(property_name, (kind, parameter))
            continue
        if not member.get("readonly"):
            after.append((name, kind, parameter))
            continue
        chained = True

    if chained:
        parent = designated(interface, interfaces)
        if not parent:
            raise SystemExit("%s: %s keeps a value its superclass declares read-only and the"
                             " superclass has no designated initialiser to keep it in"
                             % (interface.name, selector))
        pieces = []
        keywords = (parent.get("name") or "").split(":")[:-1]
        for index, (kind, parameter) in enumerate(parameters_of(parent)):
            supplied = given.get(parameter)
            # A keyword is not a parameter name: INPriceRange's second keyword is andPrice for
            # a parameter called secondPrice, and a call has to spell the keyword.
            pieces.append("%s:%s" % (keywords[index] if index < len(keywords) else parameter,
                                     supplied[1] if supplied else zero_of(kind)))
        lines.append("    if ((self = [super %s])) {" % " ".join(pieces))
    elif own_init_unavailable(interface, interfaces):
        lines.append("    // The header marks this class's -init unavailable, so the superclass's own")
        lines.append("    // -init is called through CharonIntentsCoding.h's one definition of it.")
        lines.append("    if ((self = charon_intents_super_init(self, [%s class]))) {"
                     % interface.superclass)
    else:
        lines.append("    if ((self = [super init])) {")

    for name, (kind, parameter) in sorted(given.items()):
        if ("_" + name) not in states:
            continue
        copied = spelled(kind).rstrip().endswith("*")
        lines.append("        _%s = %s;" % (name, "[%s copy]" % parameter if copied else parameter))
    # What the class takes over from the result it was given is taken after this class's own
    # state is in place, so the inner one's answer is the answer of the object.
    for parameter in adopt:
        lines.append("        [self charon_adoptResolutionOf:%s];" % parameter)
    lines += ["    }"]
    for name, kind, parameter in after:
        copied = spelled(kind).rstrip().endswith("*")
        lines.append("    self.%s = %s;" % (name, "[%s copy]" % parameter if copied else parameter))
    lines += ["    return self;", "}"]
    return lines


def own_init_unavailable(interface, interfaces):
    """Whether the -init a [super init] would reach is marked unavailable in the SDK's header.

    The whole chain is walked, not the class and its direct superclass: a resolution result three
    levels up the chain is what declares it, and a [super init] one level below that is refused
    for the same reason.
    """
    seen, name = set(), interface
    while name is not None and name.name not in seen:
        seen.add(name.name)
        declared = name.method("init")
        if declared is not None and has_attr(declared, "UnavailableAttr"):
            return True
        name = interfaces.get(name.superclass)
    return False


def resolution_result(name, interfaces):
    """Whether a class name is a resolution result, by the superclass chain the SDK gives it."""
    seen = set()
    while name and name not in seen:
        if name == RESOLUTION_BASE:
            return True
        seen.add(name)
        found = interfaces.get(name)
        name = found.superclass if found else None
    return False


def render(interface, protocols, carried, intents, interfaces, forward=()):
    """The @implementation of one generated class, and what it answers of the class's surface.

    The second value is what the registry is written from: the members with a body, the members
    left dynamic because their type is a class of a later group, and the initialisers left out
    for the same reason. Nothing here is claimed that the emitted code does not carry.
    """
    out, report = implementation(interface, protocols, carried, intents, interfaces, forward)
    return out, report or answer_of(out, interface.name)


def implementation(interface, protocols, carried, intents, interfaces, forward=()):
    resolution = resolution_result(interface.superclass, interfaces)
    conformed = conformed_by(interface, interfaces)
    own = {p.get("name"): p for p in interface.properties
           if p.get("name") and not p.get("class")}

    # clang dumps a property's accessors as declarations of their own, so every method in an
    # @interface is a declaration: the ones that are a property's getter or setter are never
    # given a body here, and the property is synthesised instead.
    accessors = set()
    for method in interface.methods:
        selector = method.get("name") or ""
        if selector in own and not parameters_of(method):
            accessors.add(selector)
        else:
            match = re.match(r"^set(%a[%w_]*):$", selector)
            if match and setter_name(match.group(1)) in own and len(parameters_of(method)) == 1:
                accessors.add(selector)

    stored, synthesised, dynamic, setters, skipped, members = [], [], [], [], [], []
    for name, member in sorted(own.items()):
        kind = type_of(member)
        if deferred_type(kind, intents, carried, forward):
            dynamic.append((name, member.get("category")))
            continue
        stored.append(("_" + name, spelled(kind), name))
        members.append((name, spelled(kind), member))
        if not member.get("category"):
            synthesised.append("    @synthesize %s = _%s;" % (name, name))
        if not member.get("readonly") and setter_name(name) not in accessors:
            setters.append((name, kind, member))

    inherited = []
    for protocol_name in conformed:
        protocol = protocols.get(protocol_name)
        # NSObject's own properties are the root superclass's and are not this class's to
        # synthesise: doing it would replace description, hash and the rest with ivars.
        if not protocol or protocol_name == "NSObject":
            continue
        for name, member in sorted(required_properties(protocol).items()):
            if member.get("class") or name in own or name in accessors or \
                    deferred_type(type_of(member), intents, carried, forward):
                continue
            kind = type_of(member)
            stored.append(("_" + name, spelled(kind), name))
            synthesised.append("    @synthesize %s = _%s;" % (name, name))
            inherited.append((name, kind, member))
            setters.append((name, kind, member))

    # A property a category of the class declares is carried by a category of Charon's own,
    # because clang will not let a class implementation synthesise one.
    by_category = {}
    for name, kind, member in members:
        if member.get("category"):
            by_category.setdefault(member["category"], []).append((name, kind, member))
    flat = [(name, kind) for name, kind, member in members if not member.get("category")]

    # Every ivar of the class, the ones a category declared included, is in one class extension
    # in this file, so the class's own initialisers can reach all of them and a category
    # implementation has a place to synthesise the properties a category declared.
    out = []
    if stored:
        out.append("@interface %s ()" % interface.name)
        out.append("{")
        width = max(len(kind) for _, kind, _ in stored)
        for ivar, kind, name in sorted(stored, key=lambda item: item[0]):
            out.append("    %-*s %s;  // %s" % (width, kind, ivar, name))
        out.append("}")
        out.append("@end")
        out.append("")
    out += ["@implementation %s" % interface.name] + synthesised
    for name, category in dynamic:
        if not category:
            out.append("    @dynamic %s;  // a class of a later group: see registry/Intents" % name)

    if interface.name in HAND_WRITTEN:
        return out + ["", "@end", ""], None

    out.append("")
    deferred_names = {name for name, _ in dynamic}
    states = {}
    for ivar, kind, name in stored:
        member = own.get(name)
        states[ivar] = "copy" if member and is_copy(member, kind) else "retain"
    spellings = property_names(interface.properties)

    for name, kind, member in setters:
        kind = spelled(kind)
        copied = is_copy(member, kind) and kind.rstrip().endswith("*")
        assigned = "[%s copy]" % name if copied else name
        out += ["- (void)set%s:(%s)%s" % (name[0].upper() + name[1:], kind, name), "{",
                "    _%s = %s;" % (name, assigned), "}", ""]

    for method in interface.methods:
        selector = method.get("name") or ""
        if method.get("instance") is False or has_attr(method, "UnavailableAttr"):
            continue
        if not selector.startswith("init") or ":" not in selector:
            continue
        if re.match(r"^(initWithCoder:)$", selector):
            continue
        # An initialiser is not given a body when it takes a value this delivery does not carry:
        # one whose name is a member left dynamic, or one whose type is a class the headers only
        # forward declare (INDateComponentsRange's initWithEKRecurrenceRule: takes EventKit's
        # class, where the property of the same name takes the INRecurrenceRule of iOS 11). A body
        # that dropped the value would answer with a class that looks filled and is not.
        if any(parameter in deferred_names or
               deferred_type(kind, intents, carried, forward)
               for kind, parameter in parameters_of(method)):
            # An initialiser that takes a value this delivery does not carry cannot be given a
            # body without dropping that value, so it is left out and the registry says so; the
            # header's mark stays on it, so a port cannot call it and nothing crashes.
            skipped.append(selector)
            continue
        out += initialiser(interface, method, states, spellings, interfaces)
        out.append("")

    for method in interface.methods:
        out += factory(interface, method, resolution)
        out.append("")

    if "NSSecureCoding" in conformed:
        # A class whose header marks -init unavailable - its own, or the one [super init] would
        # reach, which is the superclass's - cannot spell [super init] in a file that reads that
        # header, so the superclass's own -init is called by name instead.
        parent = interfaces.get(interface.superclass)
        blocked = [interface, parent]
        own_init = next((candidate.method("init") for candidate in blocked
                         if candidate is not None and candidate.method("init") is not None
                         and has_attr(candidate.method("init"), "UnavailableAttr")), None)
        if own_init is not None:
            start = ["    // The header marks this class's -init unavailable, so the superclass's own",
                     "    // -init is called through CharonIntentsCoding.h's one definition of it.",
                     "    if ((self = charon_intents_super_init(self, [%s class])))" % interface.superclass]
        else:
            start = ["    if ((self = [super init]))"]
        out += ["+ (BOOL)supportsSecureCoding", "{", "    return YES;", "}", "",
                "- (instancetype)initWithCoder:(NSCoder *)coder", "{"] + start + \
               ["        charon_intents_decode(self, coder);",
                "    return self;", "}", "",
                "- (void)encodeWithCoder:(NSCoder *)coder", "{",
                "    charon_intents_encode(self, coder);", "}"]
        out.append("")
    if "NSCopying" in conformed:
        out += ["- (id)copyWithZone:(NSZone *)zone", "{",
                "    %s *copy = [[[self class] allocWithZone:zone] init];" % interface.name,
                "    charon_intents_copy(copy, self);", "    return copy;", "}"]
        out.append("")
    out += ["@end", ""]
    # A property the SDK declares in a category of the class is answered by accessors in a
    # category of Charon's own: clang will not synthesise such a property in the class's own
    # @implementation, nor in a category's, so the accessors are written and read the class
    # extension's ivars, which are declared in this same file.
    for category, found in sorted(by_category.items()):
        out.append("@implementation %s (Charon%s%s)" % (interface.name, interface.name, category))
        for name, where in dynamic:
            if where == category:
                out.append("    @dynamic %s;  // a class of a later group: see registry/Intents" % name)
        for name, kind, member in sorted(found, key=lambda item: item[0]):
            getter = (member.get("getter") or {}).get("name") or name
            out += ["", "- (%s)%s" % (kind, getter), "{", "    return _%s;" % name, "}"]
            if not member.get("readonly"):
                copied = is_copy(member, kind) and kind.rstrip().endswith("*")
                out += ["", "- (void)set%s:(%s)%s" % (name[0].upper() + name[1:], kind, name), "{",
                        "    _%s = %s;" % (name, "[%s copy]" % name if copied else name), "}"]
        out += ["", "@end", ""]
    return out, None


# +successWithResolved…:, +successWithResolvedValue:, +disambiguationWith…ToDisambiguate:,
# +confirmationRequiredWith…ToConfirm: — the three answers a resolution result gives.
SUCCESS = re.compile(r"^successWithResolved(.*):$")
SUCCESS_VALUE = "successWithResolvedValue:"
DISAMBIGUATION = re.compile(r"^disambiguationWith(.*)ToDisambiguate:$")
DISAMBIGUATION_VALUE = "disambiguationWithValueToDisambiguate:"
CONFIRMATION = re.compile(r"^confirmationRequiredWith(.*)ToConfirm:$")
CONFIRMATION_VALUE = "confirmationRequiredWithValueToConfirm:"


def factory(interface, method, resolution):
    """The body of a resolution result's class method, or nothing."""
    selector = method.get("name") or ""
    if not resolution or has_attr(method, "UnavailableAttr"):
        return []
    parameters = parameters_of(method)
    if not parameters or len(parameters) != 1:
        return []
    returns = spelled(returns_of(method))
    if returns not in ("instancetype", interface.name, interface.name + " *"):
        return []
    kind, name = parameters[0]
    if spelled(kind).rstrip().endswith("*"):
        value = "[%s copy]" % name
    elif spelled(kind) == "BOOL":
        value = "@(%s)" % name
    elif spelled(kind) in ("NSInteger", "NSUInteger", "int", "long", "short", "unsigned"):
        value = "[NSNumber numberWithInteger:(NSInteger)%s]" % name
    elif spelled(kind) in ("double", "float", "NSTimeInterval", "CGFloat"):
        value = "[NSNumber numberWithDouble:(double)%s]" % name
    else:
        value = "[NSNumber numberWith%s:%s]" % ({"char": "Char", "unsigned char": "UnsignedChar",
                                                 "long long": "LongLong"}.get(spelled(kind), "Integer"), name)
    if SUCCESS.match(selector) or selector == SUCCESS_VALUE:
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionSuccess"
                " resolvedValue:%s valuesToDisambiguate:nil valueToConfirm:nil];" % value, "}"]
    if DISAMBIGUATION.match(selector) or selector == DISAMBIGUATION_VALUE:
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionDisambiguation"
                " resolvedValue:nil valuesToDisambiguate:%s valueToConfirm:nil];" % value, "}"]
    if selector in ("unsupportedForReason:", "unsupportedWithReason:"):
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionUnsupported"
                " resolvedValue:nil valuesToDisambiguate:nil valueToConfirm:nil"
                " unsupportedReason:%s];" % name, "}"]
    if CONFIRMATION.match(selector) or selector == CONFIRMATION_VALUE:
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionConfirmationRequired"
                " resolvedValue:nil valuesToDisambiguate:nil valueToConfirm:%s];" % value, "}"]
    return []


def banner(name, classes, release, deferred):
    return """//
//  %(name)s
//  Intents
//
//  Generated by tools/intents/gen-intents.py from the Objective-C declarations of the
//  SDK's own headers, for the %(count)d classes the armv7 release caches measure as first
//  exported in iOS %(release)s. Do not edit: change the generator and run it again.
//
//  Every method the header declares here has a body that stores or returns the class's own
//  state, the coding and copying helpers walk the whole ivar chain so a subclass keeps its
//  parent's state, and %(deferred)d member(s) whose type is a class of a later group are
//  left dynamic and answered in registry/Intents instead of with nil.
//
//  The classes whose behaviour is more than storage are hand written in
//  CharonIntents%(release)s.m, and the generator leaves them out.
//

#import <Intents/Intents.h>
#import "CharonIntentsCoding.h"
#import "CharonIntentsResolution.h"

// The SDK marks each class's initialiser as the designated one, in a header this package does not
// own and cannot add a marking to, so clang reads the -initWithCoder: and -copyWithZone: every
// class carries here as convenience initialisers of a class that has a designated one. The
// warning is about a convention and not about behaviour: the chain below is the header's own.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
""" % {"name": name, "count": classes, "release": release, "deferred": deferred}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--dump", required=True)
    parser.add_argument("--classes", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--carried", required=True,
                        help="a file of every class name this delivery carries, all groups")
    parser.add_argument("--intents", required=True,
                        help="a file of every Intents class name of SDK 26.2")
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", help="a JSON file of what the emitted code answers")
    options = parser.parse_args()

    interfaces, protocols, _, forward = collect(options.dump)
    names = [line.strip() for line in open(options.classes) if line.strip()]
    carried = {line.strip() for line in open(options.carried) if line.strip()}
    intents = {line.strip() for line in open(options.intents) if line.strip()}
    missing = [name for name in names if name not in interfaces]
    if missing:
        print("not in the SDK's headers: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    generated = [name for name in names if name not in HAND_WRITTEN]
    out = [banner(options.out.rsplit("/", 1)[-1], len(generated), options.release, 0)]
    answered, deferred = {}, 0
    for name in generated:
        interface = interfaces[name]
        body, report = render(interface, protocols, carried, intents, interfaces, forward)
        out.append("")
        out.extend(body)
        answered[name] = report
        deferred += len(report["dynamic"])
    out[0] = banner(options.out.rsplit("/", 1)[-1], len(generated), options.release, deferred)
    squeezed = []
    for line in out:
        if line == "" and squeezed and squeezed[-1] == "":
            continue
        squeezed.append(line)
    with open(options.out, "w") as handle:
        handle.write("\n".join(squeezed).rstrip("\n") + "\n")
    if options.report:
        with open(options.report, "w") as handle:
            json.dump(answered, handle, indent=1, sort_keys=True)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
