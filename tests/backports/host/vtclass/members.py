"""WHAT A CLASS HAS, derived once.

    members_of("VTMotionBlurConfiguration") -> {"entries": {(kind, registry name), …}, "accessors": {…}}

TWO FILES DISAGREEING ON ONE FACT IS THE FAILURE THIS SERIES HAS PRODUCED FOUR TIMES: the store line and
the expectation both derived a key wrongly and the check read green; the global rename map and the
header disagreed about a property's name; the availability rule was written twice and failed in opposite
directions; and the registry's rows and the value file's accessors disagreed about
`VTSuperResolutionScalerConfiguration.precomputedFlow`, whose GETTER is `usesPrecomputedFlow`. So there
is one derivation, here, and the emitter and the stand-in both call it - the emitter reading back the
text it just wrote, the stand-in reading the same files from disk.

FOUR THINGS IT GETS RIGHT, each of which cost a wrong answer before:

  A PROPERTY WITH A getter= REGISTERS UNDER ITS PROPERTY NAME. SDK 26.2 declares
  `@property (nonatomic, readonly, getter=usesPrecomputedFlow) BOOL precomputedFlow;` - so the registry
  row says precomputedFlow, and `usesPrecomputedFlow` is the ACCESSOR of that property, not a member of
  its own. A row named after the getter records a member the file does not implement.

  AN INHERITED PROPERTY THE CLASS RESTATES IS THE CLASS'S. A class states its protocol's properties
  again in its own body, because a protocol's properties are not on the runtime property list of a class
  that conforms, and the value walk reads that list. So the accessors exist and a row is owed for them.

  AN ACCESSOR IS NOT A SEPARATE MEMBER. `- (CVPixelBufferRef)buffer` and
  `CHARON_VALUE_PROPERTY(CVPixelBufferRef, buffer)` both implement the property `buffer`; reading either
  as a method is how sixteen properties were reported missing while a row for each existed.

  THE CLASS ITSELF IS A ROW, and its initialisers are rows named the SDK spells them. The pattern accepts
  whatever the header puts between the parens and the selector - SDK 26.2 writes
  `- (nullable instancetype)initWith…` - because a pattern insisting the return type comes first finds
  NO initialiser at all, and then the registry has seventeen classes, no method rows, and a stand-in
  that AGREES with it because both sides come from here. One derivation removes disagreement and can hide
  a shared omission; check-registered.py counts initialisers a second way and fails when the two differ.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
VT_DIR = os.path.join(WORKTREE, "packages", "a", "apple-backports", "VideoToolbox")
HEADER = os.path.join(VT_DIR, "CharonVideoToolbox.h")

# The template's class lives in the file that carries the protocols, hand-written, with its initialiser
# already in it. Every other class has a generated file of its own.
TEMPLATE_CLASS = "VTMotionBlurConfiguration"
TEMPLATE_FILE = "VideoToolboxValue26.m"

INITIALISER = re.compile(r'^[+-]\s*\([^)]*instancetype[^)]*\)([^;]*);', re.M)
SELECTOR_KEYWORD = re.compile(r'(\w+):')


def selector_of(declaration_span):
    """The whole selector: every keyword between the return type and the ';'."""
    return "".join(k + ":" for k in SELECTOR_KEYWORD.findall(declaration_span))
PROPERTY_ROW = re.compile(r'@property\s*\(([^)]*)\)\s*[^;]*?\s(\w+)\s*(?:[A-Z_][A-Z_0-9]*\s*(?:\([^)]*\))?)?;', re.S)
METHOD_DECL = re.compile(r'^([+-])\s*\(([^)]*)\)\s*(\w*[:\w]*)', re.M)


def joined_declarations(text):
    """Every declaration, as one string, from its first line to the ';' that ends it.

    A selector is NOT one line. SDK 26.2 writes

        - (nullable instancetype)initWithFrameWidth:(NSInteger)frameWidth
                               frameHeight:(NSInteger)frameHeight
                      numberOfInterpolatedFrames:(NSInteger)numberOfInterpolatedFrames;

    and matching the first line captures initWithFrameWidth: - the HEAD of every selector and not the
    whole of any. That put sixteen truncated selectors in the registry and collapsed two of the seventeen
    real ones into one string, because a SET cannot hold the same truncated head twice. The join is
    applied to every declaration here, not only to initialisers, and the same fact is a shape the
    availability rule met on VT_EXPORT.
    """
    out, buffer, start = [], None, 0
    for index, line in enumerate(text.split("\n"), start=1):
        if buffer is None and not line.strip():
            continue
        if buffer is None:
            start = index
            buffer = line
        else:
            buffer += " " + line.strip()
        if ";" in buffer:
            out.append((start, " ".join(buffer.split())))
            buffer = None
    if buffer is not None:
        out.append((start, " ".join(buffer.split())))
    return out
MACRO_ACCESSOR = re.compile(r'CHARON_\w+_PROPERTY\((.*)\)', re.S)
HAND_ACCESSOR = re.compile(r'([-+])\s*\([^)]*\)\s*(\w+)')
INITIALISER_KEYWORD = re.compile(r'@"(charon\.private\.)?(\w+)"')


def _value_file_for(class_name):
    return os.path.join(VT_DIR, TEMPLATE_FILE if class_name == TEMPLATE_CLASS else class_name + ".m")


def _registry_name(kind, class_name, member):
    if kind == "class":
        return class_name
    if kind == "method":
        return "-[%s %s]" % (class_name, member)
    return "%s.%s" % (class_name, member)


def members_of(class_name):
    """(kind, registry name) for everything this class implements, and the accessor map beside it.

    Returns {"entries": {(kind, registry name), …}, "accessors": {selector: property or None}} so a
    caller can tell an accessor of a property from a method of its own.
    """
    header = open(HEADER).read()
    source = open(_value_file_for(class_name)).read()

    block = re.search(r'@interface\s+%s\b.*?@end' % re.escape(class_name), header, re.S)
    if not block:
        raise ValueError("%s: the port's header declares no such class" % class_name)
    body = block.group(0)

    entries = {("class", _registry_name("class", class_name, class_name))}
    accessors = {}
    joined_body = [d for _n, d in joined_declarations(body)]
    # properties: the PROPERTY name, with its getter if it has one
    for attrs, name in PROPERTY_ROW.findall(";\n".join(joined_body)):
        entries.add(("property", _registry_name("property", class_name, name)))
        getter = re.search(r'getter\s*=\s*(\w+)', attrs)
        accessors[getter.group(1) if getter else name] = name
    # initialisers, as the SDK spells the selector - WHOLE, after the join AND after reading every
    # keyword in the span, because a character class cannot cross the '(' of an argument's type
    for span in INITIALISER.findall("\n".join(joined_body)):
        selector = selector_of(span)
        entries.add(("method", _registry_name("method", class_name, selector)))
        accessors[selector] = None
    # the accessors the value file actually implements, and the properties they belong to
    for call in MACRO_ACCESSOR.findall("\n".join(d for _n, d in joined_declarations(source))):
        last = call.split(",")[-1].strip()
        if re.match(r'^\w+$', last):
            accessors[last] = accessors.get(last)
    for _sign, selector in HAND_ACCESSOR.findall("\n".join(d for _n, d in joined_declarations(source))):
        if selector in accessors or re.match(r'^(init|initWith)', selector):
            continue
        accessors[selector] = None
    return {"entries": entries, "accessors": accessors}


def accessors_of_class(class_name):
    """Just the accessor map, for a caller that has the entries already."""
    return members_of(class_name)["accessors"]
