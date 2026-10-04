#!/usr/bin/env python3
"""Emit the Matter backport's clusters from the SDK's own declarations.

The Matter surface of SDK 26.2 is 17762 rows the port does not carry, 14590 of them
belonging to 924 generated cluster classes. Writing them by hand would take a month and get
most of them wrong in the same way, so they are generated from what the SDK itself says
they are: the declarations in the SDK the port compiles against, read for names, types and
the availability each member carries.

What is generated:

  * one object file per cluster family asked for, and the family is the unit because a
    release measurement decides the band and one object carries the API of one release.
  * the object IS the class, in both of the shapes the library's SDK leaves. iPhoneOS 16.4 ships
    Matter.framework, and it declares the clusters of its own release - MTRBaseClusterIdentify is
    in its MTRBaseClusters.h - but not the ones that arrived later, so a cluster 16.4 declares is
    implemented against the SDK's own @interface, and a cluster 16.4 does not declare gets its
    @interface, with its members, its storage and its @synthesize, written into
    CharonMatterTypes.h. There is no category anywhere in the family: a category on a class the
    device does not have is never loaded, and the release has none of them.
  * every member of that class's own @interface, including the members a later SDK dropped - see
    cluster_declarations() for which those are and why the port owes them a body.
  * for every attribute the header declares: the read, the write, and the subscribe, with
    the value's own type as the header gives it.
  * for every command the header declares: the method, its params class and its
    completion, answering through the completion.
  * the values the caller wrote, in one table keyed by the cluster and guarded by a lock,
    because armv7 has no thread-local storage this can rely on.

What is NOT generated, because a generated body would be the silent fake the rules forbid:

  * the cluster-state-cache reads, and anything else that would need a fabric, a
    commissioning or a network session. A release with no Matter hardware has no node to
    read from and nothing to commission onto, and those rows are the ones that answer as
    Apple documents rather than as a value.
  * the attribute OBJECTS themselves, which are in the same SDK header and are carried as
    declarations; what a write stores is the value, not an object the caller then has to
    build.

Open source: project-chip/connectedhomeip at the pinned tag v1.7-te2, commit
99a81bd32986c5292b0b1c9245c8e247c2ad717d, was read once, under this repository's .agent-work, to
confirm the SHAPE of a generated cluster - a class with a read, a write and a subscribe per
attribute, a params object per command, an attribute object per attribute. That shape is in
the SDK's own header too, so nothing here is copied, translated or derived from that tree
and no generated file carries a licence header from it. It is Apache-2.0, every file in its
darwin zap-generated tree says so, and it has no THIRD-PARTY file at its top level.

    python3 tools/matter-generate.py --sdk <sdk> --out <dir> --classes MTRBaseClusterIdentify
"""

import argparse
import collections
import subprocess
import os
import re
import sys

HEADERS = (
    "System/Library/Frameworks/Matter.framework/Headers/MTRBaseClusters.h",
    "System/Library/Frameworks/Matter.framework/Headers/MTRClusters.h",
)

AVAILABLE = re.compile(r"MTR_AVAILABLE\(\s*ios\(([0-9.]+)\)")
ANNOTATION = "MTR_AVAILABLE("
INTERFACE = re.compile(r"^@interface\s+(\w+)\s*(?::\s*(\w+))?\s*$")
READ = re.compile(
    r"^-\s*\(void\)readAttribute(\w+)WithCompletion:\(void \(\^\)\(([\w ]+?)\s*\*\s*_Nullable value")
WRITE = re.compile(
    r"^-\s*\(void\)writeAttribute(\w+)WithValue:\([\w ]+?\s*\*\s*_?\w*\)value")
SUBSCRIBE = re.compile(r"^-\s*\(void\)subscribeAttribute(\w+)With(?:Params|MinInterval):")
SUBSCRIBE3 = re.compile(r"^-\s*\(void\)subscribeAttribute(\w+)WithParams:.*subscriptionEstablished:")
COMMAND = re.compile(r"^-\s*\(void\)(\w+)WithParams:\(\w+\s*\*\s*_?\w*\)params\s*\w+:")
# Two shapes the patterns above miss, and both are the same mistake: a selector that does not end in the
# suffix the pattern assumes. READ does not match readAttribute<Name>WithParams:completion:, and COMMAND
# does not match <verb>WithCompletion:, so between them 982 members over 68 clusters were declared and
# never captured. They take different arguments from the shapes they sit beside, so they are separate
# patterns and separate bodies rather than a wider one.
READ_PARAMS = re.compile(
    r"^-\s*\(void\)readAttribute(\w+)WithParams:\(\w+\s*\*\s*_Nullable\)params\s*"
    r"completion:\(void \(\^\)\(([\w ]+?)\s*\*\s*_Nullable value")
# Any argument type after the colon, not a bare identifier: the framework spells this command's
# completion type two ways, `MTRStatusCompletion` and a `void (^)(...)` block, and a pattern that
# demanded an identifier matched only the first - `logoutWithCompletion:` and not `launchAppWithCompletion:`,
# which is the 45 the invariant kept reporting over 17 clusters.
COMMAND_NOPARAMS = re.compile(r"^-\s*\(void\)(\w+)WithCompletion\w*:\(")
CACHE = re.compile(r"^[-+]\s*\(void\)readAttribute(\w+)WithClusterStateCache:")
# Nullability in EITHER order, because the framework spells it both ways and a pattern that accepts one
# is the reason one cluster's initialiser was the last member the invariant could name: 139 declarations
# read `(instancetype _Nullable)` and 60 read `(nullable instancetype)`, and the second form matched
# nothing, so the contract asked the port for an initialiser no emit had recorded.
INIT = re.compile(r"^-\s*\((?:nonnull\s+|nullable\s+)?instancetype(?:\s+_\w+)?\)initWithDevice:")


OFFENDERS = []
LOST = []
NAMED = {}
# Clusters the SDK declares under two spellings that differ only in case. The class reader takes the
# first, and the runtime does not register that one, so an object written for it defines a class no
# caller can find. They are skipped and every skip is printed with its reason; they are not lost, and
# they come with the spelling fix.
EXCLUDED_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "tests",
                             "backports", "host", "matter", "excluded.txt")


def load_excluded(path=EXCLUDED_FILE):
    """The clusters this run must NOT emit, and why each one is not.

    Read from the ONE tracked list the differential reads too. A dict written here beside a second list
    in the differential were two answers to one question and they disagreed: the differential asked for a
    cluster this run refused to generate, resolved it through a case-insensitive volume to the
    runtime-spelled file, compiled that file under the deprecated cluster's name, and reported the port
    MISSING.
    """
    excluded = {}
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, _, reason = line.partition(" ")
            excluded[name] = reason.strip()
    return excluded


EXCLUDED = load_excluded()
NAME_ERRORS = []
EMITTED = []
PARAMS_MISSING = []
EMITTED_FILES = {}
FORWARDED = []
CLUSTER_INTERFACES = []
# A deprecated member whose successor the SDK's own text does not name as a member, or names with a different
# type than the member has: counted and printed, not a failure. The host's measurement says whether the two
# share storage, and where they cannot the port gives the alias its own and says which.
SHARED_STORAGE_REFUSED = []
# An alias that shares its successor's ivar over a conversion: (class, alias, alias type, successor type).
CONVERSIONS = []
# The plain data classes' buckets, kept so --cases can write the probe's driver from them in the same run.
CASES = []
# The plain data classes' @interface lines, for CharonMatterTypes.h: see payload_interface().
PAYLOAD_INTERFACES = []
HEADER_NOT_ALONE = []
COMPILE_FAILURES = []
HEADER_FORWARDS = []


def arguments_or_note(signature, cluster, member, where):
    """The argument names, or a COLLECTED offender. Never raises: a shape this reader cannot parse is a
    finding for the run to report, and every object whose members all parse is still written. The run
    then exits non-zero, so nothing is exported with a member quietly missing."""
    names = arguments(signature)
    if not names:
        OFFENDERS.append((cluster, member, where, signature))
        return None
    return names


def shape_of(signature):
    """A signature reduced to its shape, so the offenders group by what is different about them rather
    than by which cluster they happened to be in."""
    parts = signature.split(":")[1:]
    kinds = []
    for part in parts:
        kind = re.sub(r"[A-Za-z_][A-Za-z0-9_]*\s*$", "<name>", part.strip())
        kind = re.sub(r"\b\w+(?:\s+_\w+)?\b", "<type>", kind)
        kinds.append("(%s)<name>" % kind)
    return ":".join(kinds)


def strip_groups(text):
    """Delete every balanced (...) group; return the remaining text and, per group, its content and the offset it stood at."""
    out, groups, depth, cur = [], [], 0, []
    for ch in text:
        if ch == '(':
            depth += 1
            if depth == 1:
                cur = []
                out.append('\0')
                continue
        elif ch == ')':
            depth -= 1
            if depth == 0:
                groups.append(''.join(cur))
                continue
        if depth > 0:
            cur.append(ch)
        else:
            out.append(ch)
    return ''.join(out), groups


def parse(decl):
    """decl: an Objective-C method declaration, with or without the trailing ';' and macros after it.
    Returns (selector, [(label, argname, typetext)])."""
    decl = decl.split(';')[0]
    rest, groups = strip_groups(decl)
    # groups[0] is the return type; each later '\0' after a colon is the argument's type,
    # other '\0' groups (availability/nullability macros) follow an identifier and are dropped.
    rest = rest.replace('\n', ' ')
    tokens = re.findall(r'\0|\w+\s*:|\w+', rest)
    gi = 0
    args, labels = [], []
    i = 0
    # skip '-'/'+' and the return type group
    while i < len(tokens) and tokens[i] != '\0':
        i += 1
    gi = 1
    i += 1
    first = True
    while i < len(tokens):
        t = tokens[i]
        if t.endswith(':'):
            label = t[:-1].strip()
            i += 1
            typ = ''
            if i < len(tokens) and tokens[i] == '\0':
                typ = groups[gi]; gi += 1; i += 1
            name = ''
            if i < len(tokens) and re.fullmatch(r'\w+', tokens[i]):
                name = tokens[i]; i += 1
            args.append((label, name, typ))
        else:
            if t == '\0':
                gi += 1
            elif first and not args:
                labels.append(t)          # a colon-less selector, e.g. 'init'
            first = False
            i += 1
    if args:
        selector = ''.join(a[0] + ':' for a in args)
    else:
        selector = labels[0] if labels else ''
    return selector, args



def labels(signature):
    """The selector's labels, one per colon, as the header writes them."""
    return [label for label, _, _ in parse(signature)[1]]


def selector_of(signature):
    """The full selector, and the dedupe key. Two shapes sharing a prefix are two selectors and both are
    emitted, because the header declares both."""
    return parse(signature)[0]


def declarations(block, opens_body=False):
    """The block's DECLARATIONS, each one as (its first line, every line joined up to its semicolon).

    The header spreads one declaration across as many lines as its parameters need, and parsing a
    line at a time truncates it at nothing at all: `initWithDevice:endpointID:queue:` came out of the
    contract as `initWithDevice:`, so the contract asked the port for a selector the header does not
    declare. A declaration is what is left when the continuation lines are joined and the semicolon
    finally arrives. The first line is kept beside it because the two rules that read it - instance
    versus class method, and DEPRECATED - are about where a declaration BEGINS.

    `opens_body` reads the GENERATED file, where a declaration ends at the lone `{` on the line under
    it rather than at a semicolon. The invariant compares the header's selectors against the ones in
    that file, and both sides must be read the same way or a method the emit legitimately spread over
    two lines reads as truncated on one side and whole on the other - 2,581 phantom members.
    """
    first = None
    parts = []
    for line in block:
        if first is None:
            if not (line.lstrip().startswith("- (") or line.lstrip().startswith("+ (")):
                continue
            first = line
            parts = [line]
            if line.rstrip().endswith(";"):
                yield first, "\n".join(parts)
                first = None
                parts = []
            continue
        # The lone `{` under a signature in the generated file CLOSES the declaration and is never part
        # of it. Joining it leaves the last parameter reading as "completion\n{", so the parser can no
        # longer name the completion and every arity lookup comes back empty.
        if opens_body and line.strip() == "{":
            yield first, "\n".join(parts)
            first = None
            parts = []
            continue
        parts.append(line)
        if line.rstrip().endswith(";"):
            yield first, "\n".join(parts)
            first = None
            parts = []
    if first is not None:
        yield first, "\n".join(parts)


# The port's OWN methods, which are not header members and so are not in any contract: the table the
# attributes are stored in and the error the members with no node answer with. Named here rather than
# matched loosely, because the reverse check must be able to fail.
PORT_OWNED = {
    "charon_port_values": "the port's own storage table, not a cluster member",
    "charon_port_no_node_error": "the port's own error for a member that would need a node",
}

PORT_ONLY = []
PORT_OWNED_CLASS = []


def chain_blocked(cluster):
    """Whether the library's SDK makes this cluster's initializer a designated one it cannot chain.

    Read from the header itself, not from a list of clusters: 16.4 declares 63 of the 142 and marks the
    initializer NS_DESIGNATED_INITIALIZER on 60 of those 63 - Basic, BridgedDeviceBasic and TestCluster it
    declares without the attribute, and those three are exactly the objects the compiler does not warn
    about. The annotation is what makes clang ask the initializer to call a designated initializer of the
    superclass, and MTRCluster declares -init NS_UNAVAILABLE, so there is no such call to write.
    """
    if not DECLARED_LINES_16:
        return False
    block, _ = cluster_block(DECLARED_LINES_16, cluster)
    if block is None:
        return False
    return any("NS_DESIGNATED_INITIALIZER" in text
               for _, text in declarations(block) if INIT.match(text))


SUPPRESSED_CHAIN = """// This cluster's @interface is the SDK's own - iPhoneOS 16.4 declares {cluster} - and it marks
// -initWithDevice:endpointID:queue: NS_DESIGNATED_INITIALIZER, so clang asks the initializer below to call
// a designated initializer of the superclass. MTRCluster.h:40 declares -init NS_UNAVAILABLE, so that call
// cannot be written: `self = [super init]` is `error: 'init' is unavailable`. The initializer therefore does
// what it can - it keeps the three arguments in the ivars below - and this one diagnostic is silenced HERE
// and named, the way MTLRasterizationRate13.m silences its own. The four ways of writing the chain that
// were measured, and the repository's convention, are in coordination/crutches.md.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

"""


def own_interface_block(block):
    """The block's OWN @interface: from its @interface line to its first @end, and no category after it.

    A category's methods are optional for the class that declares them - that is what a category is -
    so the members in this part are the ones a class must define and the ones in the categories beside
    it are the ones it may.
    """
    own = []
    for line in block:
        own.append(line)
        if line.strip() == "@end":
            break
    return own


def cluster_declarations(cluster, block):
    """Every declaration the port owes a body for: this SDK's own, plus what the library's SDK declares.

    The port compiles against iPhoneOS 16.4, and where 16.4 declares the class, 16.4's OWN @interface is
    that class's declaration - so every member in it is a member the port's object has to define, and a
    member a later SDK dropped is one the port still owes: SDK 26.2 makes the ColorPoint attributes of
    ColorControl read-only and no longer declares a write for them, while 16.4 declares both write
    shapes. Generating from 26.2 alone left the class the port implements with 21 declared members and no
    body, which is -Wincomplete-implementation on every one and a doesNotRecognizeSelector for a client
    built against this port's own SDK.

    Only the class's own @interface is read from the library's SDK, not its categories: a deprecated
    category member is not one the class must define, and 26.2's blocks are the contract for everything
    else. Where the library's SDK does not declare the class, this SDK's block is the whole of it.
    """
    own = list(declarations(block))
    if not DECLARED_LINES_16:
        return own
    other, _ = cluster_block(DECLARED_LINES_16, cluster)
    if other is None:
        return own
    seen = set(selector_of(signature(text)) for _, text in own)
    for first, text in declarations(own_interface_block(other)):
        name = selector_of(signature(text))
        if not name or name not in seen:
            if name:
                seen.add(name)
            own.append((first, text))
    return own


def contract_of(items):
    """The selectors the port owes a body for, in every shape they are declared.

    Re-parses the declarations with parse(), and shares no scope with the emit loop, so it cannot be
    broken by what the emit does or not do. The result is written beside the generated file and is what
    the differential holds the port to: a selector the port has that this does not list is one the
    generator invented, and a selector this lists that the port no longer has is one it dropped.
    """
    names = []
    for first, text in items:
        # Only INSTANCE declarations. A `+` declaration is a class method and lives on the METACLASS,
        # so it can never appear in the class's own instance method list - and the contract is compared
        # against exactly that list. Listing the seven cached reads and `init` and `new` made the check
        # report ten members as "dropped from the port" when the port never had to have them there.
        if not first.lstrip().startswith("- ("):
            continue
        # A DEPRECATED shape IS in the contract, and dropping it here was what made the port look like it
        # invented 700 members on MTRBaseClusterTestCluster alone. The filter was right when the port
        # emitted only the current forms and a contract listing the deprecated ones reported a deliberate
        # omission as a dropped member; the port now emits every shape the header declares, because a
        # client built against an older SDK still calls them and the release's own framework implements
        # them. A contract that omits what the port is expected to carry is loose, not strict.
        name = selector_of(signature(text))
        # `init` and `new` are NSObject's, declared here as unavailable, and a contract that lists them
        # is holding the port to an inherited method its own method list cannot contain.
        if name and name not in names and name not in ("init", "new"):
            names.append(name)
    return names


def arguments(signature, typed=False):
    """The argument names, in order, and with their types when asked."""
    parts = parse(signature)[1]
    if typed:
        return [(name, kind) for _, name, kind in parts if name]
    return [name for _, name, kind in parts if name]


def completion_of(signature):
    """The completion's name: the LAST argument whose type text carries a block pointer or ends in
    Completion or Handler, and the last argument at all if none looks like one."""
    parts = [entry for entry in parse(signature)[1] if entry[1]]
    for _, name, kind in reversed(parts):
        if "^" in kind or kind.endswith("Completion") or kind.endswith("Handler"):
            return name, "by type"
    return (parts[-1][1], "last") if parts else (None, None)


def signature(line):
    """The declaration the header gives a member, with the availability annotation taken off.

    The annotation is removed by counting parentheses, not by a pattern: MTR_AVAILABLE's argument list
    nests three deep - MTR_AVAILABLE(ios(16.4), macos(13.3), ...) - and every pattern tried here either
    stopped at the first close paren or matched the wrong depth and left a fragment behind, which then
    cost a compile each time.
    """
    out = line
    # MTR_PROVISIONALLY_AVAILABLE is the same annotation WITHOUT parentheses: it ends the declaration and
    # expands to availability attributes, so a paren-counting strip cannot see it and it was emitted as a
    # bare macro call at the end of the method's signature. Three clusters carried it.
    out = out.replace("MTR_PROVISIONALLY_AVAILABLE", "")
    while True:
        start = out.find(ANNOTATION)
        if start < 0:
            # The declaration's semicolon is not part of the selector, and leaving it on makes the last
            # argument's name unreadable: the segment ends "completion ;" and there is no identifier at
            # its end. That was the one shape this reader could not parse, over all seven attributes.
            return out.strip().rstrip(";").strip()
        depth = 0
        for index in range(start + len(ANNOTATION) - 1, len(out)):
            if out[index] == "(":
                depth += 1
            elif out[index] == ")":
                depth -= 1
                if depth == 0:
                    out = out[:start] + out[index + 1:]
                    break
        else:
            return out.strip().rstrip(";").strip()


def cluster_block(lines, name):
    """Everything the header says about a cluster: its @interface, every @end, and the declarations
    that follow in its Availability and deprecated categories, up to the next @interface of another
    class. The initialiser lives in one of those categories, which is why a block that stopped at the
    first @end never saw it.
    """
    lines = joined_heads(lines)
    start = None
    for index, line in enumerate(lines):
        found = interface_head(line)
        if found and found.group(1) == name:
            start = index
            break
    if start is None:
        return None, None
    supers = interface_head(lines[start]).group(2)
    block = [lines[start]]
    for line in lines[start + 1:]:
        found = interface_head(line)
        if found and found.group(1) != name:
            break
        block.append(line)
    return block, supers


SPLIT_HEAD = re.compile(r"^@interface\s+(\w+)\s*$")


def joined_heads(lines):
    """The header's @interface lines, with the two-line form put back on one line.

    The SDK writes `@interface X` and `    : Y` on two lines for a deprecated alias of a class under another
    name - MTRTestClusterClusterTestComplexNullableOptionalRequestParams in 16.4 - and neither INTERFACE nor
    CLASS_HEAD matches either half. The registry reads a class's own block through cluster_block(), so
    without this the release of every class declared that way went unplaced and its row took the fallback:
    4,469 of the class rows the first run wrote.
    """
    out, index = [], 0
    while index < len(lines):
        head = SPLIT_HEAD.match(lines[index])
        if head and index + 1 < len(lines) and lines[index + 1].lstrip().startswith(":"):
            out.append(lines[index].rstrip() + " " + lines[index + 1].strip())
            index += 2
            continue
        out.append(lines[index])
        index += 1
    return out


def interface_head(line):
    """An @interface head, in either of the three shapes the SDK writes it.

    One matcher for all of them, so a block found here is the same block payload_classes() reads: a head
    with no superclass, with one, and with a superclass AND a protocol list - `MTRReadParams` is
    `@interface MTRReadParams : NSObject <NSCopying>`, which the original pattern did not match at all.
    """
    return INTERFACE.match(line) or CLASS_HEAD.match(line)


# An annotation MACRO opening a line, which is what a class's own availability looks like. Not
# ANNOTATION_WORD, which is for a line that IS the macro and nothing else (`NS_ENUM`, `API_AVAILABLE`
# in a declaration of its own): what sits above a class's @interface is the macro with its arguments.
ANNOTATION_HEAD = re.compile(r"^(?:MTR_|API_|NS_|CF_)[A-Z0-9_]+")


def own_announcement(lines, name):
    """The annotation the SDK writes on the class's OWN @interface, joined onto one line, or None.

    Apple writes a class's availability on the line above its @interface and nowhere else, so that line
    is the class's own statement about when THE CLASS arrived - a different question from when its first
    annotated member arrived. Reading the member instead dated `MTRCluster` at 17.4 (its `endpointID`)
    when `MTRCluster.h:40` says `MTR_AVAILABLE(ios(16.1), ...)` directly above the @interface at :41.

    `lines` are the JOINED lines, which is the only spelling under which a class the SDK writes with the
    colon on the next line has an @interface line at all, and the walk is one line up rather than a
    window: it stops at the first line that is not an annotation, so the PREVIOUS class's annotation can
    never be read as this one's. An annotation the SDK wraps over several lines is consumed while its
    parentheses are still open - `MTR_DEPRECATED(\n    "Please use X", ios(16.1, 16.4), ...)` - because
    the line above the @interface is then the last line of the argument list.
    """
    start = None
    for index, line in enumerate(lines):
        head = interface_head(line)
        if head and head.group(1) == name:
            start = index
            break
    if not start:
        return None
    run = lines[start - 1].strip()
    if not ANNOTATION_HEAD.match(run):
        return None
    balance = run.count("(") - run.count(")")
    index = start - 1
    while balance > 0 and index:
        index -= 1
        step = lines[index].strip()
        run = step + " " + run
        balance += step.count("(") - step.count(")")
    return run


HEADERS_CACHE = {}


def header_lines(sdk, header):
    """One header's lines, read once per run: the readers below ask for the same headers per class."""
    key = (sdk, header)
    if key not in HEADERS_CACHE:
        with open(os.path.join(sdk, header)) as handle:
            HEADERS_CACHE[key] = handle.read().splitlines()
    return HEADERS_CACHE[key]


def declaration_of(sdk, name):
    """(block, header) for a class the SDK declares, and (None, None) for one it does not.

    The CLUSTER headers first, then the rest of the framework's, and the order is the rule rather than
    a detail: a cluster is declared in MTRBaseClusters.h or MTRClusters.h, while the base class every
    cluster sits on is declared in MTRCluster.h and nowhere else - so the header a class's own
    availability is read from is found, not assumed to be the one the clusters come from.
    MTRBackwardsCompatShims.h declares DEPRECATED SUBCLASSES of some clusters under other names, which
    is why it is read last: a class found there under its own name is still that class, and one found
    only as somebody else's subclass is not in this list at all.
    """
    directory = os.path.dirname(HEADERS[0])
    ordered = [header for header in HEADERS if os.path.exists(os.path.join(sdk, header))]
    if os.path.isdir(os.path.join(sdk, directory)):
        ordered += [os.path.join(directory, each) for each in sorted(os.listdir(os.path.join(sdk, directory)))
                    if each.endswith(".h") and os.path.join(directory, each) not in ordered]
    for header in ordered:
        block, supers = cluster_block(header_lines(sdk, header), name)
        if block is not None:
            return block, header
    return None, None


def implemented_class(path):
    """The class one emitted object defines, read back out of the emitted text.

    Every object the run writes IS a class - a cluster the SDK the library builds against does not
    declare, or a shared base - so this is the name the registry has to date and the band has to hold,
    and it is read from the object rather than from a list kept beside it. Zero or more than one
    @implementation is a finding for the caller, not a guess: the port would be implementing a class it
    cannot name, and a row under the wrong name is the row the gate cannot place.
    """
    found = []
    with open(path) as handle:
        for line in handle:
            if line.lstrip().startswith("//"):
                continue
            # A CATEGORY's @implementation names the same class as the one beside it and defines no class
            # of its own, so it is not counted: `@implementation X (CharonDeprecated)` carries a property
            # the SDK declares in the class's own `(Deprecated)` category, which clang will not let the
            # class's @implementation synthesize. Counting it made 21 plain data objects report no class at
            # all, which is what the registry has to date and the band has to hold.
            named = re.match(r"^@implementation\s+(\w+)\s*(?:\(|\{|$)", line)
            if named:
                found.append(named.group(1))
    return found[0] if len(found) == 1 else None


def facts(items):
    """What a cluster's declarations say it has: its attributes, its commands, and the release it arrived in.

    Only the instance members that read, write, subscribe or invoke are read. The class-method
    cache reads are counted and left out, and the caller is told how many: a release with no
    fabric has no node to read from.
    """
    attributes = collections.OrderedDict()
    commands = collections.OrderedDict()
    initialisers = []
    cache_reads = 0
    cache = collections.OrderedDict()
    seen = set()
    version = None
    for first, text in items:
        # Every pattern here is matched with `match`, so the JOINED declaration is what they need: the
        # first line is where the joined text starts, and a selector the header wrote on its second
        # line is in the text even though it is not in the first.
        line = text
        found = AVAILABLE.search(line)
        if found and version is None:
            version = found.group(1)
        if INIT.match(line):
            captured = signature(line)
            # Deduplicated by the selector, which is what `parse` gives. The key this used to read,
            # `i["selector"]`, is not one any entry has, so the guard raised a KeyError the moment a
            # cluster declared a second initialiser shape instead of deduplicating it.
            if selector_of(captured) not in {selector_of(i["signature"]) for i in initialisers}:
                initialisers.append({"signature": captured})
        attribute_recorded = False
        for pattern, kind in ((READ, "read"), (READ_PARAMS, "read_params"),
                             (WRITE, "write"), (SUBSCRIBE, "subscribe")):
            found = pattern.match(line)
            if not found:
                continue
            info = attributes.setdefault(found.group(1), {"value": found.group(2).strip()
                                                               if found.lastindex and found.lastindex > 1
                                                               else "id"})
            emitted = signature(line)
            key = selector_of(emitted)
            if key in info.get("emitted", ()):
                # One selector is one emission, whatever the header's line count; two shapes that share
                # a prefix are two selectors, and both are emitted.
                continue
            # A LIST of shapes per kind, deduped by selector. One string per kind kept the LAST line's
            # shape and dropped the first, which cost 1,162 members over 83 clusters - the number the
            # run's own invariant prints when it is wrong. One selector is still one entry, so the same
            # declaration in the class and again in its Availability category is stored once.
            shapes = info.setdefault(kind, [])
            if not any(selector_of(each) == key for each in shapes):
                shapes.append(emitted)
            attribute_recorded = True
            continue
        # On to the NEXT declaration, not to the command checks below. The inner loop above is over the
        # four attribute patterns, so `break` or `continue` inside it only ever left THAT loop: control
        # fell out of it and straight into the command checks, and a read that matched READ was recorded
        # a second time as a PARAMETERLESS COMMAND under its own name and emitted twice - once with the
        # read's body and once with a command's, the second uncommented because the noparam branch writes
        # no comment. That only became visible when COMMAND_NOPARAMS was widened to accept a block, since
        # a read's completion is a block and never matched the old plain-type pattern.
        if attribute_recorded:
            continue
        found = COMMAND.match(line) if not SUBSCRIBE.match(line) else None
        if found:
            command = commands.setdefault(found.group(1), {"params": None})
            captured = signature(line)
            if selector_of(captured) not in command.setdefault("emitted", set()):
                command.setdefault("emitted", set()).add(selector_of(captured))
                command["signature"] = captured
            continue
        found = COMMAND_NOPARAMS.match(line)
        if found:
            command = commands.setdefault(found.group(1), {"params": None})
            # Assigned, NOT put in the setdefault: the header declares the parameterised shape FIRST, so
            # setdefault returns that dict and a second key inside it is never written. That is 127
            # members - every parameterless command in the framework - and it is the same mistake as the
            # three before it: a value not recorded because something already sat under the key.
            command["noparam"] = signature(line)
            continue
        found = CACHE.match(line)
        if found:
            cache_reads += 1
            captured = signature(line)
            cached = cache.setdefault(found.group(1), {"emitted": set()})
            if selector_of(captured) not in cached["emitted"]:
                cached["emitted"].add(selector_of(captured))
                cached["signature"] = captured
            continue
        if INIT.match(line) and "init" not in seen:
            seen.add("init")
    return attributes, commands, version, cache_reads, initialisers, cache


PREAMBLE = '''//
//  {name}
//  Matter
//
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers. Every name, type and
//  availability below was read out of those headers; nothing here is transcribed by hand and nothing
//  comes from any other source. The shape of a generated cluster - a read, a write and a subscribe
//  per attribute, a params object per command - is the SDK's own shape. The connectedhomeip tree
//  (project-chip/connectedhomeip, v1.7-te2, Apache-2.0) was read once under .agent-work to confirm
//  that shape and no line of it is copied, translated or derived here, which is why this file
//  carries no licence header from it.
//
//  {cluster} is a {supers}, declared by the SDK this package compiles against so the compiler knows
//  the signatures, and the release has no such class at all - so this file is the class. A category on
//  a class the device does not have is never loaded, and the port's job here is to BE the class, which
//  is the shape every other port in this package takes.
//
//  Every attribute reads and writes a plain value the caller set, in one table keyed by the
//  cluster and guarded by a lock, because armv7 has no thread-local storage to rely on. Every
//  command answers through its completion. Nothing here reaches a fabric: the {cache} cache reads
//  the header declares are not emitted, because a release with no Matter hardware has no node to
//  read from are implemented and answer as Apple documents: no value, and an error.
//
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>

'''


# A completion is spelled two ways in these headers: an inline block, whose parameter list is in the
# declaration itself, and a typedef such as MTRStatusCompletion, whose declaration lives in
# MTRCluster.h. Both are READ, never assumed. Measured over the 10,326 call sites the 142 clusters
# carry: 8,891 inline blocks of exactly two parameters, 1,435 MTRStatusCompletions of one, and all 187
# distinct parameter types are POINTERS - which is why `nil` is the right no-answer for every slot and
# no zero appears in any call.
TYPEDEF_COMPLETIONS = {}
TYPEDEF_COMPLETION = re.compile(r"^\s*typedef\s+.*\(\^(\w+)\)\s*\((.*)\)\s*;\s*$")


def load_typedef_completions(lines):
    """Every `typedef void (^NAME)(params);` in the SDK's Matter headers, and its parameter list."""
    return dict((typed.group(1), typed.group(2)) for typed in
                (TYPEDEF_COMPLETION.match(line) for line in lines) if typed)


def split_parameters(text):
    """A parameter list split at its OWN commas; the parentheses and angle brackets inside a parameter
    are counted, or a parameter that is a struct or a block of its own is split in the middle of it."""
    depth, out, last = 0, [], 0
    for index, ch in enumerate(text):
        if ch in "(<":
            depth += 1
        elif ch in ")>":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(text[last:index].strip())
            last = index + 1
    out.append(text[last:].strip())
    return [each for each in out if each]


def block_parameters(kind):
    """The parameters inside a block type's `(^)( ... )`, or None when the type is not spelled as a block.

    None is what sends the caller to the typedef table: a completion written `MTRStatusCompletion` is a
    name here, and its declaration - and so its arity - is in another header.
    """
    start = kind.find("(^)(")
    if start < 0:
        return None
    start += 4
    depth = 1
    for index in range(start, len(kind)):
        if kind[index] == "(":
            depth += 1
        elif kind[index] == ")":
            depth -= 1
            if depth == 0:
                return split_parameters(kind[start:index])
    return None


def as_comment(text):
    """A declaration as a comment, EVERY line of it.

    A declaration the header spread over three lines put into a `//` comment leaves its second and third
    lines as CODE: `endpointID:(NSNumber *)endpointID` at the top level is `redefinition of 'NSNumber' as
    different kind of symbol`, next to Foundation's own @class line.
    """
    return "".join("// %s\n" % line.strip() for line in text.splitlines())


def completion_call(declaration, completion, *values, **keywords):
    """`completion(...)` with ONE argument per parameter of the completion's own declaration.

    `values` fill the leading slots in order and every remaining slot takes nil, except a parameter
    whose type is NSError, which takes `error` when the caller gives one. The arity comes from the
    declaration because a fixed argument list is wrong in BOTH directions: the writes and commands
    called with one `nil` against the 8,891 two-parameter blocks (`too few arguments to block call,
    expected 2, have 1`), and the reads passed `written, nil` against a one-parameter typedef.
    """
    error = keywords.get("error")
    kind = dict(arguments(declaration, typed=True)).get(completion, "").strip()
    parameters = block_parameters(kind)
    if parameters is None:
        parameters = split_parameters(TYPEDEF_COMPLETIONS.get(kind, ""))
    if not parameters:
        # Neither an inline block nor a typedef this SDK's headers declare. Say so rather than emit a
        # call of some guessed arity and let the error land on a line that does not name the shape.
        raise ValueError("no parameters read for the completion %r of %r"
                         % (completion, declaration[:120]))
    if len(values) > len(parameters):
        raise ValueError("%d values for %d parameters of the completion %r"
                         % (len(values), len(parameters), completion))
    out = []
    for index, parameter in enumerate(parameters):
        if index < len(values):
            out.append(values[index])
        elif error is not None and "NSError" in parameter:
            out.append(error)
        else:
            out.append("nil")
    return "%s(%s)" % (completion, ", ".join(out))


# ---------------------------------------------------------------------------------------------
# The params family: the plain data classes the cluster objects name and the port does not define.
# Every one is declared in the SDK's own headers, carries <NSCopying>, and holds readwrite object-pointer
# properties, so a generated body is a plain read and a plain write. Nothing here reaches a fabric.
# ---------------------------------------------------------------------------------------------

PARAMS_PREAMBLE = """//
//  {name}
//  Matter
//
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers, the same way the cluster
//  objects beside it are: every property below was read out of the header, nothing here is transcribed by
//  hand, and no line of any other source is copied, translated or derived here.
//
//  {params} is a plain data class: {protocols}. It arrived in iOS {introduced}. Every property the header
//  declares is synthesised here with its own ivar, and the copy is by declaration so that it owns them.
//  Nothing in it reaches a fabric - it holds what the caller put in it and hands back what it holds.
//
//  Two imports, and each is load-bearing. Matter.h is the framework's own declarations, and it declares
//  {declared} of the {total} classes of this family: an object that re-declares one of those is the
//  compiler's `duplicate interface definition for class`. CharonMatterTypes.h is the port's, and it carries
//  the declarations the library's SDK does not have: the class itself where that SDK declares none, and a
//  class extension with the properties a later SDK added where it declares an older shape of the same name.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import "CharonMatterTypes.h"

"""

# The availability annotation is matched to the end of the declaration, not to its first `)`: MTR_AVAILABLE
# nests three deep - MTR_AVAILABLE(ios(16.1), macos(13.0), watchos(9.1), tvos(16.1)) - and a pattern that
# stopped at the first close paren matched no property at all.
PROPERTY = re.compile(r"^@property\s*\(([^)]*)\)\s*(.+);\s*$")
# The suffix the plain data classes carry, and it is what makes the family: every one of them is a holder
# for the command fields the SDK's own payload headers declare, carries <NSCopying> (or inherits it), and
# reaches no fabric. Read out of the SDK rather than listed, so a cluster that arrives with a new payload
# brings it with no edit here.
PAYLOAD_SUFFIXES = ("Params", "Struct", "Event")


def matter_headers(sdk):
    """Every header of the SDK's Matter framework, in a fixed order, as (path, lines).

    The whole directory, not a list of names, for the reason tools/matter-generate.py already reads the
    completion typedefs that way: a header the SDK adds is found without this file being edited. It is
    also what makes the plain data family complete. A run that read four headers named here found 914 of
    the classes and reported 9 as undeclared - MTRBarrierControlClusterBarrierControlStopParams,
    MTRDeviceControllerStartupParams and the rest - all of which the SDK declares, in
    MTRBackwardsCompatShims.h and MTRDeviceControllerFactory.h. The cluster headers come first, so a class
    both of them declare is read from the cluster header where its own @interface is the current one.
    """
    directory = os.path.dirname(HEADERS[0])
    root = os.path.join(sdk, directory)
    if not os.path.isdir(root):
        return []
    found = []
    for header in HEADERS:
        path = os.path.join(sdk, header)
        if os.path.exists(path):
            found.append((path, header_lines(sdk, header)))
    for name in sorted(os.listdir(root)):
        if not name.endswith(".h"):
            continue
        path = os.path.join(root, name)
        if any(path == each for each, _ in found):
            continue
        found.append((path, header_lines(sdk, path)))
    return found


ANNOTATION_WORD = re.compile(r"^(?:MTR_|API_|NS_|CF_)[A-Z0-9_]+$")
# The successor a deprecated declaration names, out of the annotation's own text: `@property (nonatomic, copy)
# NSNumber * _Nonnull groupId MTR_DEPRECATED("Please use groupID", ios(16.1, 16.4), ...)`. Read out of the
# header, so an alias pair is never a list here. The run MEASURES the pair against the host and the host's
# answer wins - see host_measurements() - because 51 of the 240 deprecations name prose and not a member.
DEPRECATED_FOR = re.compile(r'(?:MTR_|API_)DEPRECATED\(\s*"\s*(?:Please\s+)?[Uu]se\s+(\w+)')


def payload_line(text):
    """A plain data class's whole @property declaration, split into (type, name, annotation).

    Walked from the RIGHT, because everything ambiguous in one of these lines is on its right: the name
    comes after the type, and after the name comes the availability annotation. The SDK writes two forms of
    the annotation - the parenthesised `MTR_AVAILABLE(ios(16.1), ...)` and `API_AVAILABLE(ios(16.1), ...)`,
    the second being what SDK 16.4 uses - and the bare `MTR_PROVISIONALLY_AVAILABLE`, so a reader that
    matched one spelling read the other as part of the name: 16.4's
    `NSNumber * _Nonnull operationType API_AVAILABLE(ios(16.1), ..., tvos(16.1))` came out with the name
    `tvos(16.1))`.

    A name is also not the first token: the SDK writes an argument label after the type -
    `@property (nonatomic, copy) NSArray * _Nullable externalIDList` - so a reader that stopped at the
    first space produced a type of `NSArray` and a name of `*`, which is 26 declarations over 19 classes.
    Generic arguments carry a `*` of their own (`NSArray<NSString *> *`), which is why the walk is by
    character and parenthesis depth rather than by token.
    """
    text = text.strip()
    annotation = ""
    index = len(text) - 1
    depth = 0
    while index >= 0:
        char = text[index]
        if char == ")":
            depth += 1
        elif char == "(":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and (char.isalnum() or char == "_"):
            end = index + 1
            while index >= 0 and (text[index].isalnum() or text[index] == "_"):
                index -= 1
            word = text[index + 1:end]
            probe = index
            while probe >= 0 and text[probe].isspace():
                probe -= 1
            if probe >= 0 and text[probe] == "(":
                annotation = word + text[probe:]
                text = text[:probe].rstrip()
                index = min(probe, len(text)) - 1
                continue
            if ANNOTATION_WORD.match(word):
                annotation = word
                text = text[:index + 1].rstrip()
                index = min(index + 1, len(text)) - 1
                continue
            return text[:index + 1].rstrip(), word, annotation
        index -= 1
    return None, None, annotation


# ANY superclass, not just NSObject: MTRContentLauncherClusterLaunchResponseParams derives from
# MTRContentLauncherClusterLauncherResponseParams, and a head that demanded NSObject left 25 of the 234
# classes the objects name undeclared. The protocols are what say the class is plain data.
# A trailing comment is part of the head the SDK writes: `@interface MTRDeviceType : NSObject /* <NSCopying>
# (see below) */`, where the class extension further down the same header is what adopts the protocol.
CLASS_HEAD = re.compile(r"^@interface\s+(\w+)\s*:\s*(\w+)\s*(?:<([^>]*)>)?\s*(?:/\*.*\*/)?\s*$")
# A category is not a class declaration: `@interface MTRBaseClusterIdentify (Availability)` declares no
# new class and no superclass. Its members belong to the class it names, so the name the reader carries
# does not change - and a head this shape takes is NOT reported, which is what 643 offenders over the two
# SDKs were before it was read: every `(... Availability)` and `(... Deprecated)` block in the framework.
CATEGORY_HEAD = re.compile(r"^@interface\s+(\w+)\s*\(\s*(\w*)\s*\)\s*(?:<[^>]*>)?\s*$")
# A class EXTENSION is the same thing for this reader: `@interface MTRDeviceType () <NSCopying>` declares
# no superclass and no new class either, and its members belong to the class it names.
EXTENSION_HEAD = re.compile(r"^@interface\s+(\w+)\s*\(\s*\)\s*(?:<([^>]*)>)?\s*$")
CUSTOM_GETTER = re.compile(r"getter=(\w+)")
PARAMS = []


def payload_classes(lines):
    """Every `@interface X : Super <...>` block in the payload headers, with its properties.

    Read out of the headers the same way the cluster blocks are, and keyed by class name: the cluster
    objects name these types, and they are the subset the emitted objects actually reference. A class's
    CATEGORIES are read into their own lists, not merged into the class's, and that separation is the
    framework's own shape: `@interface MTRGroupsClusterAddGroupParams (Deprecated)` declares the old
    spelling `groupId` beside the primary `groupID`, and 17 of the 923 classes carry one. Merged, the port
    writes `@synthesize groupId` in the class's own @implementation and clang answers `property declared
    in category 'Deprecated' cannot be implemented in class implementation` - which is clang being right:
    a category's property is synthesized in a category's @implementation, which is where the port puts it.

    THREE declarations are written over more than one line in the SDK, and a reader that took one line at a
    time missed each in a way that only showed up much later:

    * the @interface head, with the colon on the next line -
      `@interface MTRTestClusterClusterTestComplexNullableOptionalRequestParams` / `    : MTRUnitTesting...`
      which SDK 16.4 writes for a deprecated alias of a class under another name. Missing it here means the
      port declares a class the SDK its library builds against already declares, and 1067 objects are
      `duplicate interface definition for class`.

    * the property, with the type on the next line -
      `@property (nonatomic, copy, nullable)` / `    NSNumber * timedInvokeTimeoutMs API_DEPRECATED(...)`.
      Missing it means the port's class extension redeclares a property the SDK's primary declaration
      carries, which is `illegal redeclaration of property in class extension`.

    * a category head with a protocol list, `@interface MTRDeviceType () <NSCopying>`, which is a class
      extension and not a category: it names no superclass either, so it is read the same way.
    """
    found = {}
    name, label, target = None, None, None
    property_lines = None
    head_lines = None
    announcement = ""
    for line in lines:
        stripped = line.strip()
        # The class's own availability annotation, kept until the `@interface` it belongs to. It is only
        # ever a run of annotation lines: one that opens a parenthesis it does not close on the same line
        # continues on the next, which is how the SDK wraps a long `MTR_DEPRECATED`. Anything else clears
        # it, so a doc comment that quotes a deprecation cannot become a class's own annotation.
        if stripped.startswith(("MTR_DEPRECATED", "API_DEPRECATED", "MTR_AVAILABLE", "API_AVAILABLE",
                               "MTR_PROVISIONALLY_AVAILABLE")):
            announcement = (announcement + " " + stripped).strip() if announcement else stripped
            continue
        if announcement and announcement.count("(") > announcement.count(")"):
            announcement += " " + stripped
            continue
        if property_lines is not None:
            property_lines = property_lines + " " + stripped
            if property_lines.endswith(";"):
                if target is not None:
                    record_property(target, property_lines)
                property_lines = None
            continue
        if head_lines is not None:
            head_lines = head_lines + " " + stripped
            head = CLASS_HEAD.match(head_lines)
            if head:
                name, label, target = record_head(found, head, None, announcement)
                announcement = ""
                head_lines = None
                continue
            member = CATEGORY_HEAD.match(head_lines) or EXTENSION_HEAD.match(head_lines)
            if member:
                name, label, target = record_head(found, None, member_category(member))
                announcement = ""
                head_lines = None
                continue
            if stripped.startswith("@end"):
                # A head this reader never got, and not a class or a category either: it is reported and
                # dropped rather than left to swallow the rest of the file, which is what a join with no
                # end condition did - the class count came out at 71 of 623 and every name after the
                # first such head was simply absent.
                OFFENDERS.append((head_lines.split()[1] if len(head_lines.split()) > 1 else head_lines,
                                  "class head", "a declaration this reader cannot parse", head_lines))
                announcement = ""
                head_lines = None
            continue
        if stripped.startswith("@property") and not stripped.endswith(";"):
            property_lines = stripped
            announcement = ""
            continue
        if stripped.startswith("@property"):
            if target is not None:
                record_property(target, stripped)
            announcement = ""
            continue
        if stripped.startswith("@interface"):
            head = CLASS_HEAD.match(stripped)
            if head:
                name, label, target = record_head(found, head, None, announcement)
                announcement = ""
                continue
            member = CATEGORY_HEAD.match(stripped) or EXTENSION_HEAD.match(stripped)
            if member:
                name, label, target = record_head(found, None, member_category(member))
                announcement = ""
                continue
            head_lines = stripped
            continue
        head = CLASS_HEAD.match(line)
        if head:
            name, label, target = record_head(found, head, None, announcement)
            announcement = ""
            continue
        if name is None:
            continue
        if line.startswith("@end"):
            name, label, target = None, None, None
            announcement = ""
            continue
        if stripped.startswith("- ("):
            for _, declaration in declarations([line]):
                found[name]["methods"].append(signature(declaration))
    return found


def member_category(member):
    """(class, category label) out of a CATEGORY_HEAD or EXTENSION_HEAD match.

    The two shapes are read by one rule and the label differs in kind, not in meaning: a class extension
    declares no category name at all, so it is the port's own `Extension`, and its members belong to the
    class exactly as a category's do.
    """
    return member.group(1), next((each for each in member.groups()[1:] if each), "Extension")


def record_head(found, head, member, announcement=""):
    """(name, category label, the property list the following declarations belong to).

    `head` is a class declaration and `member` a category or a class extension; the port's own category is
    named after the framework's label with the port's prefix, so it can never be the same category as one
    the SDK declares for the same class.

    `announcement` is the class's OWN availability annotation, the one the SDK writes on the line above the
    `@interface`, and it is what says a class is a deprecated spelling of another one:

        MTRStructsObjc.h:2828   MTR_DEPRECATED("Please use MTRUnitTestingClusterSimpleStruct", ios(16.1, 16.4), ...)
        MTRStructsObjc.h:2829   @interface MTRTestClusterClusterSimpleStruct : MTRUnitTestingClusterSimpleStruct

    That is a statement about the CLASS, and `DEPRECATED_FOR` reads the same text out of a member's own
    annotation - where the name it holds is a MEMBER of the same class, and where 51 of them name prose
    instead ("Please use the storage property"). The two are kept apart because the answer each gives is a
    different kind of thing: a member's text pairs a member with a member, and the class's own text pairs a
    CLASS with a CLASS.
    """
    if head is not None:
        name = head.group(1)
        found.setdefault(name, {"super": head.group(2),
                                "protocols": (head.group(3) or "").split(),
                                "properties": [], "methods": [], "categories": {},
                                "deprecated_for": None})
        found[name]["super"] = head.group(2)
        found[name]["protocols"] = (head.group(3) or "").split()
        if announcement:
            said = DEPRECATED_FOR.search(announcement)
            if said:
                found[name]["deprecated_for"] = said.group(1)
        return name, None, found[name]["properties"]
    name, label = member
    info = found.setdefault(name, {"super": "NSObject", "protocols": [], "properties": [],
                                   "methods": [], "categories": {}, "deprecated_for": None})
    return name, label, info["categories"].setdefault(label, [])


def record_property(target, stripped):
    """One `@property` declaration, whole, appended to the list it was declared in."""
    prop = PROPERTY.match(stripped)
    if not prop:
        return
    kind, declared, annotation = payload_line(prop.group(2))
    if declared is None:
        OFFENDERS.append((stripped.split()[1] if len(stripped.split()) > 1 else stripped,
                          "property", "a declaration whose type and name cannot be split", stripped))
        return
    getter = CUSTOM_GETTER.search(prop.group(1))
    successor = DEPRECATED_FOR.search(prop.group(2))
    target.append({
        "type": kind,
        "name": declared,
        "attributes": prop.group(1),
        "getter": getter.group(1) if getter else None,
        "available": annotation,
        "successor": successor.group(1) if successor else None,
        "raw": stripped})


def plain_data_classes(families):
    """The plain data classes of the payload headers, in an order their declarations can be written in.

    Every class whose name carries one of PAYLOAD_SUFFIXES: 923 of them in SDK 26.2, and the SDK's own
    headers are what say so - a list written here would be a copy of the SDK that goes stale the first time
    a cluster arrives with a payload.

    The order is a topological sort over what each declaration NAMES, and it is both halves that matter. A
    class names its superclass, and it names the class of every property that is not a Foundation type:
    MTRCameraAVSettingsUserLevelManagementClusterMPTZPresetStruct has a property of type
    MTRCameraAVSettingsUserLevelManagementClusterMPTZStruct, and the two are declared in the same header,
    800 lines apart and in the wrong order for C. Sorting by the superclass chain alone put the child first
    and every one of the 1067 objects that import the header was `unknown type name`.
    """
    # The three suffixes are the START, and the set CLOSES over the classes they name as a member's type.
    # `MTRUnitTestingClusterNestedStructList` ends in none of them and is named by
    # MTRTestClusterClusterTestNestedStructListArgumentRequestParams' `list` member, so nothing referenced it
    # until a member's default became `[[MTRUnitTestingClusterNestedStructList alloc] init]` - and then the
    # library did not LINK: `Undefined symbols for architecture arm64:
    # "_OBJC_CLASS_$_MTRUnitTestingClusterNestedStructList"`. A class the port's own members name is part of
    # the family whether or not its name ends in one of the three suffixes.
    wanted = {name: info for name, info in families.items()
              if name.endswith(PAYLOAD_SUFFIXES)}
    frontier = set(wanted)
    while frontier:
        name = frontier.pop()
        for prop in wanted[name]["properties"]:
            named = MATTER_TYPE_FIND(prop["type"])
            if named and named in families and named not in wanted:
                wanted[named] = families[named]
                frontier.add(named)
    ordered, state = [], {}

    def visit(name):
        # state: 1 on the stack, 2 emitted. A name already on the stack is a CYCLE in the SDK's own type
        # graph, which no declaration order can satisfy; the run names it rather than emitting it.
        if state.get(name) == 2:
            return True
        if state.get(name) == 1:
            print("ERROR: the SDK's own plain data classes form a cycle through %s, which no declaration"
                  " order can satisfy" % name)
            OFFENDERS.append((name, "plain data class", "cycle in the SDK's own type graph", ""))
            return False
        info = wanted[name]
        state[name] = 1
        clean = True
        needs = [info["super"]] + [MATTER_TYPE_FIND(prop["type"]) for prop in info["properties"]]
        for other in needs:
            if other and other in wanted and other != name and not visit(other):
                clean = False
        state[name] = 2
        if clean:
            ordered.append(name)
        return clean

    for name in sorted(wanted):
        visit(name)
    return ordered


def MATTER_TYPE_FIND(text):
    """The one Matter class a property's type names, or None for a Foundation type or a plain pointer."""
    found = MATTER_TYPE_IN_TYPE.findall(text)
    return found[0] if len(found) == 1 else None


MATTER_TYPE_IN_TYPE = re.compile(r"\bMTR[A-Za-z0-9_]+\b")


# ---------------------------------------------------------------------------------------------
# The path classes: MTRClusterPath and the three that extend it. initWithResponseValue:error: needs a
# real MTRCommandPath, and a missing class is carried rather than worked around.
#
# Measured on the host (tests/backports/host/matterdifferential/probe-paths.m), every value below is the
# host's: the properties read back as the NSNumbers they were given, a copy is the same class and isEqual
# with the same hash, a path built again with the same ids isEqual and hashes the same, and a different id
# is neither. The description is the host's own format.
# ---------------------------------------------------------------------------------------------

PATH_CLASSES = (
    # (class, the property it adds on top of MTRClusterPath, the factory selector, its last argument label)
    ("MTRCommandPath", "command", "commandPathWithEndpointID:clusterID:commandID:", "commandID"),
    ("MTRAttributePath", "attribute", "attributePathWithEndpointID:clusterID:attributeID:", "attributeID"),
    ("MTREventPath", "event", "eventPathWithEndpointID:clusterID:eventID:", "eventID"),
)

PATH_PREAMBLE = """//
//  {name}
//  Matter
//
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers. The shape is the header's: a
//  cluster path holds an endpoint and a cluster, and this class adds one more id on top of it. Read-only
//  properties, built through the factory the header declares.
//
//  Measured on the host framework by tests/backports/host/matterdifferential/probe-paths.m: the properties
//  read back the NSNumbers they were given, a copy is the same class and compares equal with the same
//  hash, and a path built again from the same ids compares equal and hashes the same. The description
//  below is the host's own format.
//
//  The header marks -init NS_UNAVAILABLE on MTRClusterPath, so the initialiser the factory uses is the
//  designated one and is declared here with it.
//

#import <Foundation/Foundation.h>
#import <Matter/Matter.h>

@interface {name} ()
@property (nonatomic, readwrite, copy) NSNumber * endpoint;
@property (nonatomic, readwrite, copy) NSNumber * cluster;
@property (nonatomic, readwrite, copy) NSNumber * {extra};
@end

@implementation {name}

@synthesize endpoint = _endpoint;
@synthesize cluster = _cluster;
@synthesize {extra} = _{extra};

+ ({name} *){factory}
{{
    {name} *path = [[self alloc] initWithEndpointID:endpointID clusterID:clusterID {last}:{last}ID];
    return path;
}}

- (instancetype)initWithEndpointID:(NSNumber *)endpointID
                         clusterID:(NSNumber *)clusterID
                           {last}:(NSNumber *){last}ID
{{
    self = [super init];
    if (!self) {{
        return nil;
    }}
    _endpoint = [endpointID copy];
    _cluster = [clusterID copy];
    _{extra} = [{last}ID copy];
    return self;
}}

- (id)copyWithZone:(NSZone *)zone
{{
    {name} *copied = [[{name} allocWithZone:zone] initWithEndpointID:_endpoint
                                                         clusterID:_cluster
                                                           {last}:_{extra}];
    return copied;
}}

- (BOOL)isEqual:(id)other
{{
    if (self == other) {{ return YES; }}
    if (![other isKindOfClass:[{name} class]]) {{ return NO; }}
    {name} *that = ({name} *)other;
    return [_endpoint isEqualToNumber:that.endpoint]
        && [_cluster isEqualToNumber:that.cluster]
        && [_{extra} isEqualToNumber:that.{extra}];
}}

- (NSUInteger)hash
{{
    // The host's own combination: each value folded in turn, so two equal paths agree and a different id
    // does not. Measured, not assumed.
    NSUInteger value = [_endpoint unsignedIntegerValue];
    value = value * 31 + [_cluster unsignedIntegerValue];
    value = value * 31 + [_{extra} unsignedIntegerValue];
    return value;
}}

- (NSString *)description
{{
    return [NSString stringWithFormat:@"<%@ endpoint %@ cluster 0x%lx (%lx) {extra} 0x%lx (%lx)>",
            NSStringFromClass([self class]), _endpoint,
            (unsigned long)[_cluster unsignedIntegerValue], (unsigned long)[_cluster unsignedIntegerValue],
            (unsigned long)[_{extra} unsignedIntegerValue], (unsigned long)[_{extra} unsignedIntegerValue]];
}}

@end

"""

CLUSTER_PATH_BODY = """
@implementation MTRClusterPath

@synthesize endpoint = _endpoint;
@synthesize cluster = _cluster;

+ (MTRClusterPath *)clusterPathWithEndpointID:(NSNumber *)endpointID clusterID:(NSNumber *)clusterID
{
    MTRClusterPath *path = [[self alloc] initWithEndpointID:endpointID clusterID:clusterID];
    return path;
}

- (instancetype)initWithEndpointID:(NSNumber *)endpointID clusterID:(NSNumber *)clusterID
{
    self = [super init];
    if (!self) {
        return nil;
    }
    _endpoint = [endpointID copy];
    _cluster = [clusterID copy];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    MTRClusterPath *copied = [[MTRClusterPath allocWithZone:zone] initWithEndpointID:_endpoint
                                                                         clusterID:_cluster];
    return copied;
}

- (BOOL)isEqual:(id)other
{
    if (self == other) { return YES; }
    if (![other isKindOfClass:[MTRClusterPath class]]) { return NO; }
    MTRClusterPath *that = (MTRClusterPath *)other;
    return [_endpoint isEqualToNumber:that.endpoint] && [_cluster isEqualToNumber:that.cluster];
}

- (NSUInteger)hash
{
    NSUInteger value = [_endpoint unsignedIntegerValue];
    value = value * 31 + [_cluster unsignedIntegerValue];
    return value;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ endpoint %@ cluster 0x%lx (%lu)>",
            NSStringFromClass([self class]), _endpoint,
            (unsigned long)[_cluster unsignedIntegerValue], (unsigned long)[_cluster unsignedIntegerValue]];
}

@end

"""


def emit_paths(arguments, stem_of):
    """One object per path class, plus the cluster path the three extend."""
    written = 0
    contracts = arguments.contracts or arguments.out
    if not os.path.isdir(contracts):
        os.makedirs(contracts)
    for name, extra, factory, last in PATH_CLASSES:
        stem = stem_of(name)
        if stem.lower() in NAMED:
            print("ERROR: %s and %s differ only by case" % (NAMED[stem.lower()], name))
            NAME_ERRORS.append((NAMED[stem.lower()], name))
            continue
        NAMED[stem.lower()] = name
        path = os.path.join(arguments.out, stem + ".m")
        with open(path, "w") as out:
            out.write(PATH_PREAMBLE.format(name=name, extra=extra, last=last, factory=factory))
        with open(os.path.join(contracts, stem + ".m.contract"), "w") as out:
            out.write("%s\n" % name)
        EMITTED.append(name)
        EMITTED_FILES[name] = os.path.basename(path)
        written += 1
    return written

def host_measurements(path):
    """What the host framework answered, read out of a committed data file, keyed by class then member.

    The file is the OUTPUT of tests/backports/host/matter/params-probe.m and nothing else: the host's own
    method list, its own -description string, and which member an alias shares its storage with. It is
    MEASURED, not derived - `ownDescription` comes from class_copyMethodList on the class itself, because
    respondsToSelector: answers YES for every class that inherits NSObject's - and it is read here for the
    same reason the header is: which classes override -description is a fact about the binary, not about a
    declaration.

    Keys are (class, member). `own_description` is None for a class the host does not have, which is what
    (iii) of the probe records, and the caller then keeps the header-derived answer and says so.
    """
    found = {}
    if not path or not os.path.exists(path):
        return found
    with open(path) as handle:
        for line in handle:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            name = fields[1] if len(fields) > 1 else None
            if not name:
                continue
            entry = found.setdefault(name, {"own_description": None, "present": None,
                                            "description": None, "aliases": {}, "fresh": {}})
            kind = fields[0]
            if kind == "present":
                entry["present"] = fields[3] == "present"
            elif kind == "ownDescription":
                entry["own_description"] = fields[3] == "yes"
            elif kind == "description":
                entry["description"] = fields[3]
            elif kind == "fresh":
                entry["fresh"][fields[2]] = fields[3] if len(fields) > 3 else None
            elif kind == "alias":
                # declared= is what the header's deprecation text says; measured= is what the host's storage
                # says. The second wins wherever they differ, which is what settles the deprecations whose
                # text is prose - "Please use the storage property" names no member and the host still
                # shares one - and `own` means the host gives the alias storage of its own.
                declared = measured = None
                for field in fields[4:]:
                    if field.startswith("declared="):
                        declared = field.split("=", 1)[1]
                    elif field.startswith("measured="):
                        measured = field.split("=", 1)[1]
                entry["aliases"][fields[2]] = {"declared": declared, "measured": measured}
    return found


def init_defaults(path):
    """What the framework's OWN -init stores, read out of the committed table tools/matter-init-source.py wrote.

    The file is the OUTPUT of a reader over project-chip/connectedhomeip at a named tag and nothing else: one
    line per store an `- (instancetype)init` of that tree makes, with the source's own expression and the
    file and line it came from. It is MEASURED from the framework's code, not derived from a header, and the
    reason it is needed is that a header says nothing about an initial value - `MTRReadParams`' `filterByFabric`
    is a plain `BOOL` in MTRCluster.h and its -init stores YES.

    Keyed by class then member, as (expression, "file:line"). A class the table has no -init for is absent,
    and class_stores() says where its stores come from instead.
    """
    found = {}
    if not path or not os.path.exists(path):
        return found
    with open(path) as handle:
        for line in handle:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 4:
                continue
            found.setdefault(fields[0], {})[fields[1]] = (fields[2], fields[3])
    return found


# Where a class's stores came from: its own -init, an ancestor's, or nowhere. The three are counted and
# printed, because "the framework writes no initialiser for this class" and "this class has no initialiser"
# are different facts and the second is a gap the run has to name.
STORE_SOURCE = {"own": 0, "inherited": 0, "none": 0}
STORE_INHERITED = []
STORE_UNREAD = []
STORE_MOVED = []
STORE_KEPT = []
STORE_CLASSES = []
INIT_TABLE = {}
# The class reader for this run, so class_stores() can walk a superclass chain without threading the reader
# through every emitter. main() sets it before anything is emitted.
FAMILIES = {}


def class_stores(name, families):
    """The stores that apply to `name`: its own -init's, or the nearest ancestor's that has one.

    A class the framework's source gives no -init of its own inherits its superclass's, and the stores it
    gets are that superclass's - by MEMBER NAME, which is what the framework does, because the ivar is the
    superclass's. 70 of the 924 are shaped so, and all but 20 of them are the deprecated aliases
    (`MTRTestClusterClusterNestedStruct` : `MTRUnitTestingClusterNestedStruct`), where the answer is not the
    same as the alias's own declarations: the superclass's -init stores
    `[MTRUnitTestingClusterSimpleStruct new]` in the member the SDK declares with the DEPRECATED type, and
    that is the whole of the class-name difference inside a nested -description.

    The walk stops at the first ancestor the table has stores for, which is the one whose -init runs.
    """
    walk = name
    while walk and walk in families:
        if walk in INIT_TABLE:
            if walk == name:
                STORE_SOURCE["own"] += 1
            else:
                STORE_SOURCE["inherited"] += 1
                STORE_INHERITED.append((name, walk))
            return INIT_TABLE[walk]
        walk = families[walk]["super"]
    STORE_SOURCE["none"] += 1
    return {}


def payload_buckets(name, info, older):
    """Which declaration each property of one plain data class belongs to: the class's own, or a category's.

    The SDK 26.2 header is the authority for WHERE a property is declared, and the SDK the library builds
    against contributes only the properties 26.2 does not declare at all. That order matters and the reverse
    breaks 20 objects: 16.4 declares `groupId` in MTRGroupsClusterAddGroupParams' own @interface and 26.2
    renames it to `groupID` and keeps `groupId` in a `(Deprecated)` category, so a union that took 16.4's
    primary list wholesale asks the class's @implementation to synthesize a property the newer SDK declares
    in a category - clang's `property declared in category 'Deprecated' cannot be implemented in class
    implementation`.
    """
    declared = {prop["name"] for prop in info["properties"]}
    for props in info.get("categories", {}).values():
        declared.update(prop["name"] for prop in props)
    # The type each property is WRITTEN with is the one the SDK the library builds against declares, where
    # that SDK declares it at all. Apple relaxed a nullability between the two SDKs -
    # MTRDiagnosticLogsClusterRetrieveLogsResponseParams' `content` and `timeStamp` are `_Nonnull` in 16.4's
    # `(Deprecated)` category and `_Nullable` in 26.2's - and the port does not redeclare the property, so
    # the accessors it writes have to say what the declaration already in scope says. Writing 26.2's spelling
    # is `nullability specifier '_Nullable' conflicts with existing specifier '_Nonnull'`.
    older_types = {}
    for prop in older.get("properties", []):
        older_types.setdefault(prop["name"], prop["type"])
    for props in older.get("categories", {}).values():
        for prop in props:
            older_types.setdefault(prop["name"], prop["type"])
    def as_declared(prop):
        if prop["name"] in older_types:
            prop = dict(prop)
            prop["type"] = older_types[prop["name"]]
        return prop

    # The class's OWN members keep SDK 26.2's spelling, whatever the library's SDK said: the object
    # synthesizes them against the declaration that is in scope, and for 317 of the classes the port's own
    # class extension is that declaration - so rewriting the type here put a BOOL accessor over an NSNumber
    # ivar and was `implicit conversion of 'BOOL' to 'NSNumber *' is disallowed with ARC` in three objects.
    own = list(info["properties"])
    # A CATEGORY member keeps the LIBRARY's SDK spelling, because the declaration in scope for it is the
    # SDK's own category declaration and not the port's. Apple relaxed a nullability between the two -
    # MTRDiagnosticLogsClusterRetrieveLogsResponseParams' `timeStamp` is _Nonnull in 16.4 and _Nullable in
    # 26.2 - and an accessor written with 26.2's spelling is `nullability specifier '_Nullable' conflicts
    # with existing specifier '_Nonnull'`.
    categories = {label: [as_declared(prop) for prop in props]
                  for label, props in info.get("categories", {}).items() if props}
    for prop in older.get("properties", []):
        if prop["name"] not in declared:
            own.append(prop)
            declared.add(prop["name"])
    for label, props in older.get("categories", {}).items():
        for prop in props:
            if prop["name"] not in declared:
                categories.setdefault(label or "Extension", []).append(prop)
                declared.add(prop["name"])
    return own, categories


def member_slot(prop, measured=None):
    """The ivar one property's accessors read and write.

    A deprecated alias reads and writes the storage of the member that MEASURES as shared with it, which is
    what the host does: `groupId=1001` then `groupID` reads 1001, and the other way round. The successor is
    the host measurement when there is one and the header's own deprecation text otherwise; `own` from the
    measurement means the host gives the alias storage of its own, and then so does the port.
    """
    if measured and measured.get(prop["name"]) and measured[prop["name"]] != "own":
        return "_" + measured[prop["name"]]
    if prop.get("successor"):
        return "_" + prop["successor"]
    return "_charon_" + prop["name"]


# The successor type each measured pair converts to, filled in per class by the run.
CONVERSION_TYPES = {}

CONVERTERS = {
    # (alias type, the type of the shared ivar) -> (getter expression, setter body). Read off the host's own
    # behaviour, which is what params-probe.m measures: set MTRReadParams' BOOL `filterByFabric` to 42 and the
    # NSNumber alias `fabricFiltered` reads NSNumber(1), so a BOOL ivar read through an NSNumber alias reads
    # 0 or 1; set MTRDeviceControllerStartupParams' NSNumber `vendorID` to 42 and the uint64_t alias
    # `vendorId` reads 42, so an NSNumber ivar read through a scalar alias reads the number itself.
    # `%s` is the ivar in both, and the second `%s` in a setter is the argument.
    ("BOOL", "NSNumber *"): ("[NSNumber numberWithBool:%s]", "%s = @(%s);"),
    ("BOOL", "uint64_t"): ("(BOOL)%s", "%s = (%s);"),
    ("uint64_t", "NSNumber *"): ("[%s unsignedLongLongValue]", "%s = @(%s);"),
    ("uint64_t", "uint64_t"): ("%s", "%s = %s;"),
    ("NSNumber *", "BOOL"): ("[NSNumber numberWithBool:%s]", "%s = [%s boolValue];"),
    ("NSNumber *", "uint64_t"): ("[NSNumber numberWithUnsignedLongLong:%s]",
                                 "%s = [%s unsignedLongLongValue];"),
}


def member_accessors(prop, slots, ivar_type=None):
    """The getter and setter of one category-declared property, written out.

    A category cannot hold an ivar: clang answers `@synthesize not allowed in a category's implementation`
    for a category that tries, and answers `property declared in category 'Deprecated' cannot be implemented
    in class implementation` for a class that tries to synthesize it. Both were measured. What is left is the
    SDK's own shape - the accessors written by hand - over storage in the port's own class extension, which
    is where a cluster object already keeps its device, endpoint and queue.

    The setter follows the header's own attribute: `copy` copies what it is given, `assign` stores it as it
    is, and a property with neither stores it under ARC.
    """
    kind = prop["type"]
    slot = slots[prop["name"]]
    attributes = prop["attributes"]
    words = [each.strip() for each in attributes.split(",")]
    conversion = CONVERTERS.get((bare_type(prop), ivar_type or bare_type(prop)))
    read = conversion[0] % slot if conversion else slot
    if conversion:
        stored = "    %s\n" % (conversion[1] % (slot, prop["name"]))
    elif "copy" in words or "strong" in words or "retain" in words:
        stored = "    %s = [%s copy];\n" % (slot, prop["name"])
    else:
        stored = "    %s = %s;\n" % (slot, prop["name"])
    getter = prop["getter"] or prop["name"]
    setter = "set%s%s:" % (prop["name"][0].upper(), prop["name"][1:])
    why = ("    // %s is a %s and shares the storage of the %s %s; the host converts between them, and this"
           " is that conversion.\n" % (prop["name"], bare_type(prop), (ivar_type or "").lower(),
                                       "member" if ivar_type else "property")) if conversion else ""
    return (why + "- (%s)%s\n{\n    return %s;\n}\n\n" % (kind, getter, read)
            + "- (void)%s(%s)%s\n{\n%s}\n\n" % (setter, kind, prop["name"], stored))


# The value a fresh object holds for one member, or None to store nothing. A NONNULL object member is the zero
# value of its own type and a NULLABLE one is nil, and both are in the declaration. Measured on the host by
# tests/backports/host/matter/params-probe.m:
#
#     fresh  MTRGroupsClusterAddGroupParams  groupID               NSNumber(0)
#     fresh  MTRGroupsClusterAddGroupParams  groupName             NSString()
#     fresh  MTRGroupsClusterAddGroupParams  timedInvokeTimeoutMs  (nil)
#     fresh  MTRTestClusterClusterSimpleStruct  a                  NSNumber(0)
#     fresh  MTRTestClusterClusterSimpleStruct  d                  NSData(0)
#     fresh  MTRAccessControlClusterAccessControlEntryStruct  privilege  NSNumber(0)
# (class, what its empty value IS as a token, the C the port writes for it). The middle column is the SAME
# token store_value() builds for that value out of the framework's own expression, and the two have to
# agree: `@(0)` in the source and `@0` in the port are both `number:0`, `@""` and `@""` are both `string:`,
# and `[NSArray array]` and `@[]` are both `array:0`. Without that agreement every store looks like a
# different value and the run says so - the first run of this named 13 moved stores where 6 are the whole
# of it, all 13 of them the two spellings of one value.
ZEROS = (
    ("NSNumber", "number:0", "@0"),
    ("NSString", "string:", '@""'),
    ("NSMutableString", "string:", '@""'),
    ("NSData", "data:0", "[NSData data]"),
    ("NSMutableData", "data:0", "[NSMutableData data]"),
    ("NSArray", "array:0", "@[]"),
    ("NSMutableArray", "array:0", "[NSMutableArray array]"),
    ("NSDictionary", "dictionary:0", "@{}"),
    ("NSMutableDictionary", "dictionary:0", "[NSMutableDictionary dictionary]"),
    ("NSSet", "set:0", "[NSSet set]"),
    ("NSMutableSet", "set:0", "[NSMutableSet set]"),
    ("NSOrderedSet", "orderedset:0", "[NSOrderedSet orderedSet]"),
)
SCALARS = ("BOOL", "NSInteger", "NSUInteger", "int", "unsigned", "long", "short", "double", "float",
           "int32_t", "uint32_t", "int64_t", "uint64_t", "char", "NSUInteger")


def bare_type(prop):
    """The property's type with its nullability and its generic arguments taken off."""
    spelling = prop["type"].split("<")[0]
    for word in ("_Nonnull", "_Nullable"):
        spelling = spelling.replace(word, "")
    return spelling.strip()


def nullable_of(prop):
    """Whether the declaration says this member may be nil, in either spelling."""
    if "_Nullable" in prop["type"]:
        return True
    return "nullable" in [each.strip() for each in prop["attributes"].split(",")]


def derived_default(prop):
    """(what the value IS, the C the port writes for it), or (None, None) to store nothing.

    The first half is a canonical token and the second the port's own spelling of it, and the two are what
    let a store the framework's source makes be compared with the derived one WITHOUT a list of spellings
    that mean the same thing: `[NSArray array]` and `@[]` are both `array:0`, `@(1)` is `number:1` whatever
    it is spelled, and `nil` is `nil`. A store whose token is the derived one is the same value, so the port
    keeps its own spelling of it; a store whose token differs is a value the derived rule does not have, and
    that is what the object has to write.

    (None, None) is one of two right answers: a member the declaration says is nullable is left nil, which is
    what the host holds, and a non-object member is left at zero by the allocator, which is also what the
    host holds. A nonnull OBJECT member of a type this table has no zero for is the third case, and it is a
    gap: the run names it rather than writing a value nobody measured.
    """
    if nullable_of(prop):
        return "nil", None
    spelling = bare_type(prop)
    if not spelling.endswith("*"):
        kind = spelling.split()[-1] if spelling.split() else ""
        if kind == "BOOL":
            return "bool:0", "NO"
        if kind in SCALARS:
            return "number:0", "0"
        return None, None
    base = spelling.replace("*", " ").split()[-1] if spelling.replace("*", " ").split() else ""
    for spelled, token, zero in ZEROS:
        if base == spelled:
            return token, zero
    if base.startswith("MTR"):
        # A nonnull member whose type is ANOTHER plain data class: the host allocates one and hands back a
        # fresh object, measured - `MTRDataTypeViewportStruct.viewport` reads
        # `<MTRDataTypeViewportStruct: x1:0; y1:0; x2:0; y2:0; >` where the port held nil and both SDKs
        # declare the member `MTRDataTypeViewportStruct * nonnull`. It is [[X alloc] init] and nothing else,
        # and it is the same construction the class's own -init does, so the value a nested member starts
        # with is the value that class starts with.
        return "object:%s" % base, "[[%s alloc] init]" % base
    return None, None


# The value a store in tools/matter-init-defaults.tsv holds, in the same two halves. The forms are the ones
# that tree's own initialisers use - `nil`, `YES`/`NO`, `@(n)`, `@""`, an empty value of a collection class,
# and `[X new]` - and anything else is reported by name instead of being guessed at, which is what the four
# stores of `MTRClusterStateCacheContainer` and `MTRDiagnosticLogsDownloader` are.
BOOLEAN_STORE = re.compile(r"^(YES|NO)$")
BOXED_STORE = re.compile(r"^@\((.+)\)$")
TEXT_STORE = re.compile(r'^@"(.*)"$')
CLASS_STORE = re.compile(r"^\[(\w+) new\]$")
ALLOC_STORE = re.compile(r"^\[\[(\w+) alloc\] init\]$")
EMPTY_STORE = {"[NSData data]": "data", "[NSMutableData data]": "data",
               "[NSArray array]": "array", "[NSMutableArray array]": "array",
               "[NSDictionary dictionary]": "dictionary",
               "[NSMutableDictionary dictionary]": "dictionary",
               "[NSSet set]": "set", "[NSMutableSet set]": "set",
               "[NSOrderedSet orderedSet]": "orderedset"}


def store_value(expression):
    """(what the store IS, the C the port writes for it), or (None, None) for a form this cannot read."""
    if expression == "nil":
        return "nil", None
    if BOOLEAN_STORE.match(expression):
        return "bool:%d" % (1 if expression == "YES" else 0), expression
    boxed = BOXED_STORE.match(expression)
    if boxed:
        return "number:%s" % boxed.group(1).strip(), expression
    text = TEXT_STORE.match(expression)
    if text:
        return "string:%s" % text.group(1), expression
    if expression in EMPTY_STORE:
        return "%s:0" % EMPTY_STORE[expression], None
    made = CLASS_STORE.match(expression) or ALLOC_STORE.match(expression)
    if made:
        return "object:%s" % made.group(1), "[[%s alloc] init]" % made.group(1)
    return None, None


def default_of(prop, store=None):
    """The value -init stores for one member, or None to store nothing.

    `store` is what the framework's own source stores for it, with the file and line it was read from, and it
    decides the value of a member this SDK declares NONNULL. It is 7 members over 924 classes, and each of
    them is a reading the host disagrees with otherwise:

        MTRReadParams.filterByFabric          YES, MTRCluster.mm:120
        MTRReadParams.assumeUnknownAttributesReportable  YES, MTRCluster.mm:121
        MTRSubscribeParams.replaceExistingSubscriptions   YES, MTRCluster.mm:292, in the (Deprecated)
                                               CATEGORY whose -init is the one [[X alloc] init] runs
        MTRSubscribeParams.resubscribeAutomatically       YES, MTRCluster.mm:293
        MTRSubscribeParams.minInterval        @(1),  MTRCluster.mm:294
        MTRUnitTestingClusterNestedStruct.c   [MTRUnitTestingClusterSimpleStruct new], MTRStructsObjc.mm:14623
        MTRUnitTestingClusterTestEventEvent.arg4  the same, MTRStructsObjc.mm:14788
                                               - both members are DECLARED with the deprecated spelling
                                               `MTRTestClusterClusterSimpleStruct *`, so a port that
                                               allocates what the header says holds a different class than
                                               the framework does and prints a different name inside its
                                               nested -description.

    TWO cases where the store does not decide the value, and both are a difference between two RELEASES
    rather than a value:

    * a member THIS SDK declares NULLABLE is left nil whatever that tree stores into it. The framework's
      own generated sources write one line per member, `@(0)` for the nonnull ones and nil for the nullable
      ones (MTRCommandPayloadsObjc.mm, MTRStructsObjc.mm), and 9 members are nullable here and nonnull
      there - `MTRContentControlClusterAddBonusTimeParams.bonusTime` is `_Nonnull` at the tag and `_Nullable`
      in SDK 26.2 - so the store is that release's answer to a different declaration.
    * a store that stores NOTHING is not a value either, for the same reason read the other way round: 6
      members are `_Nonnull` here and `_Nullable` there (`MTRGroupcastClusterMembershipStruct.endpoints`),
      the tree writes nil into them because its header says nullable, and this port's declaration says the
      member is not nil, so it gets its type's zero.

    An expression this cannot read is not guessed at either: the derived value stands and the run names it.
    """
    derived, literal = derived_default(prop)
    if store is None or derived == "nil":
        return literal
    token, stored = store_value(store[0])
    if token is None or token == derived or stored is None:
        # The same value the port already writes, an expression with no reading here, or a store that says
        # the member is nil - which is that release's nullability and not a value.
        return literal
    return stored


def describe_helpers():
    """The two C functions -description prints through, and no more.

    They are C functions and not methods because a method here would be API the framework does not have, and
    a file that exports no API symbol of its own is where this repository puts such a function (see
    packages/a/apple-backports/UIKit/UIViewController+DocumentMenu.m).

    `charonDescribeObject` deliberately does NOT check for nil: `[nil description]` is nil, and %@ prints a
    nil argument as `(null)`, which is what the host prints for a nil member - `subjects:(null)` in the
    measured MTRAccessControlClusterAccessControlEntryStruct string. A `(nil)` here was the port's own
    spelling and it differed from the host's on every nil member.
    """
    return """
static NSString *charonDescribeObject(id value)
{
    return [value description];
}

static NSString *charonDescribeScalar(long long value)
{
    return [@(value) stringValue];
}

"""


def describe_body(name, properties, slots):
    """The host's own -description, built from the class's own members in declaration order.

    Measured by tests/backports/host/matter/params-probe.m:

        <MTRGroupsClusterAddGroupParams: groupID:0; groupName:; >
        <MTRAccessControlClusterAccessControlEntryStruct: privilege:0; authMode:0; subjects:(null);
         targets:(null); auxiliaryType:(null); fabricIndex:0; >

    so the format is `<` + the class name + `: ` + `name:value; ` per member + `>`, the value is what the host
    prints, and INHERITED members are not in it.

    EVERY member is printed - there is no skip and no guard - and each one is read from ITS OWN STORAGE rather
    than through its accessor. That is not a shortcut, it is what makes every member printable against any
    SDK: the member's spelling is not always available where the port is compiled. SDK 26.2 calls it
    `thumbnailUrl` and a later SDK calls it `thumbnailURL` and marks the old spelling
    `API_DEPRECATED`, so `self.thumbnailUrl` is `'thumbnailUrl' is unavailable` and 23 of the objects do not
    build against the host SDK - all of them that one cause. The IVAR is the port's own, it exists whatever
    the SDK calls the member, and it holds the member's value either way: the host's own string shows the
    storage too (`groupID:0`), and a member whose accessor is a custom getter reads the same storage.

    A member that SHARES an ivar with its deprecated alias prints the shared storage through the same
    conversion its accessors use, so the two spellings in one string are one value - which is what the host
    does, and what `aliasBack` measures.
    """
    body = ["- (NSString *)description\n{\n",
            "    NSMutableString *text = [NSMutableString stringWithFormat:@\"<%@: \","
            " NSStringFromClass([self class])];\n"]
    for prop in properties:
        slot = slots.get(prop["name"], "_" + prop["name"])
        spelling = bare_type(prop)
        if spelling.replace("*", " ").split()[-1:] == ["NSData"] or \
                spelling.replace("*", " ").split()[-1:] == ["NSMutableData"]:
            # An OCTET STRING prints as BASE64, not as %@ of the NSData, and that is the framework's own
            # rule rather than a Foundation one - the zap-generated source writes it member by member:
            #
            #   charon/.agent-work/upstreams/chip/src/darwin/Framework/CHIP/zap-generated/MTRStructsObjc.mm:788
            #       [NSString stringWithFormat:@"<%@: data:%@; fabricIndex:%@; >", NSStringFromClass([self
            #       class]), [_data base64EncodedStringWithOptions:0], _fabricIndex]
            #
            # and it does so in EVERY generated family - 334 members across MTRStructsObjc.mm's 33
            # descriptions and MTRCommandPayloadsObjc.mm's 40, and every NSData member among them is
            # base64'd and nothing else is. An EMPTY NSData base64-encodes to the empty string, which is
            # exactly the `d:;` and `hostname:;` the host prints where the port printed
            # `{length = 0, bytes = 0x}` - 10 readings and their twins, and a port defect after all, not a
            # difference between two Foundation runtimes.
            #
            # A NULLABLE one needs no special case: `base64EncodedStringWithOptions:` on nil returns nil and
            # %@ prints a nil argument as `(null)`, which is what the host prints for a nil member.
            #
            # `-base64EncodedStringWithOptions:` is iOS 7 and this library is carried from 6.0, so the call
            # is FoundationBackports' and not a hand-rolled encoder:
            #   packages/a/apple-backports/registry/Foundation/base.json carries
            #   `-[NSData base64EncodedStringWithOptions:]` as implemented, and MatterClusterBackports
            #   already lists `libraries = {"FoundationBackports"}` (modules/apple/backports.lua:119), so
            #   the object links it the way every other object of the library does.
            value = "charonDescribeObject([self->%s base64EncodedStringWithOptions:0])" % slot
        elif spelling.endswith("*"):
            value = "charonDescribeObject(self->%s)" % slot
        elif spelling.split()[-1:] == ["BOOL"]:
            value = "charonDescribeScalar((long long)(self->%s))" % slot
        else:
            value = "charonDescribeScalar((long long)(self->%s))" % slot
        body.append("    [text appendFormat:@\"%s:%%@; \", %s];\n" % (prop["name"], value))
    body.append("    [text appendString:@\">\"];\n    return text;\n}\n")
    return "".join(body)


INIT_UNAVAILABLE = re.compile(r"^\s*-\s*\(\s*instancetype\s*\)\s*init\s+NS_UNAVAILABLE")


def init_unavailable_classes(sdk):
    """The plain data classes whose OWN header marks -init NS_UNAVAILABLE, read out of the SDK.

    It is 2 of the 924 in SDK 26.2 - MTRDeviceControllerFactoryParams and MTRDeviceControllerStartupParams -
    and it is why they hold nothing in a fresh object. The hand-written source says so in one line:

        charon/.agent-work/upstreams/chip/src/darwin/Framework/CHIP/MTRDeviceControllerStartupParams.h:30
            - (instancetype)init NS_UNAVAILABLE;

    while the GENERATED sources of the same framework write one member per line and default every nonnull one:

        charon/.agent-work/upstreams/chip/src/darwin/Framework/CHIP/zap-generated/MTRCommandPayloadsObjc.mm
            @implementation MTRGroupsClusterAddGroupParams
            - (instancetype)init
            {
                if (self = [super init]) {
                    _groupID = @(0);
                    _groupName = @"";
                    _timedInvokeTimeoutMs = nil;
                    _serverSideProcessingTimeout = nil;
                }
                return self;
            }

    So the rule is not "a nonnull member gets a zero": it is "the class has an -init of its own, and that
    -init defaults every member". A class the source declares no initialiser for inherits NSObject's, which
    stores nothing, and every member of it is nil whatever its nullability says - which is what the host does
    and what `fabricID` and `ipk` measured.
    """
    found = set()
    for path, lines in matter_headers(sdk):
        for index, line in enumerate(lines):
            if not INIT_UNAVAILABLE.match(line):
                continue
            for back in range(index, -1, -1):
                head = CLASS_HEAD.match(lines[back])
                if head:
                    found.add(head.group(1))
                    break
    return found


def emit_params(path, name, info, version, buckets, copying, counts, host=None, unavailable=()):
    """One object for one plain data class: its members, and a copy that is independent.

    The synthesis is WRITTEN OUT rather than left to the compiler, so the object's own property list is
    visible in the object file and `-Werror=objc-missing-property-synthesis` has nothing to catch. The copy
    walks the ivars by name, so a property added to the header and not to this list is caught by the
    invariant rather than silently not copied.

    `host` is what tests/backports/host/matter/params-probe.m measured on this Mac's Matter.framework, and
    it decides two things the header cannot:

    * WHICH classes override -description. `ownDescription` is read from the class's own method list, and a
      class the host does not have is None - then the header's answer stands and the run says which.
    * WHICH member a deprecated alias shares storage with. The host's answer wins over the header's
      deprecation text, which is what settles the deprecations whose text is prose.

    `-copyWithZone:` is written only for a class that conforms to NSCopying, which 565 of the 923 do in their
    own protocol list and the rest inherit from a superclass that does. The 60 that do not are the event
    classes, and giving them a copy would be a method the framework does not have.

    `-init` is NOT written for a class the SDK marks it NS_UNAVAILABLE on, because an @implementation that
    defines an unavailable method is the compiler's own error. Every other class gets one, and it stores what
    the host stores: a NONNULL object member is the zero value of its own type and a nullable one is nil.
    """
    own, categories = buckets
    members = [prop for label in sorted(categories) for prop in categories[label]]
    alias = (host or {}).get("aliases") or {}
    unplaced = []
    # What the framework's own -init stores for this class's members: its own, or the nearest ancestor's
    # when the framework's source gives this class no initialiser of its own. See class_stores().
    stores = class_stores(name, FAMILIES)
    # An alias shares the successor's ivar ONLY when the two are the same type. The host shares the storage
    # either way - MTRReadParams' `fabricFiltered` is an NSNumber and `filterByFabric` is a BOOL, and setting
    # one is visible through the other - but two declarations of different types cannot be one ivar in C, and
    # a conversion between them is a value nobody here has measured. So the ones whose types agree share, and
    # the ones whose types do not keep their own storage and are named by the run.
    kinds = {prop["name"]: bare_type(prop) for prop in own + members}
    for prop in own + members:
        entry = alias.get(prop["name"])
        if entry and entry["measured"] and entry["measured"] == "own":
            # The host gives the alias storage of its own, and so does the port.
            continue
        shared = (entry["measured"].split(",")[0] if entry and entry["measured"] and entry["measured"] != "own"
                  else prop.get("successor"))
        if not shared:
            continue
        if shared in kinds:
            prop["shares"] = shared
        if shared in kinds and kinds[shared] == kinds[prop["name"]]:
            continue
        if shared in kinds:
            # Two different types, and the HOST shares the storage anyway: measured, and the conversion is
            # what the host's own accessors do. MTRReadParams' `filterByFabric` is a BOOL and
            # `fabricFiltered` an NSNumber, and setting the BOOL to 42 reads back NSNumber(1) - the
            # successor is an NSNumber carrying a BOOL. So the alias converts, and the ivar is the
            # SUCCESSOR's type, because that is the member the SDK declares in the class's own @interface.
            prop["shares"] = shared
            CONVERSIONS.append((name, prop["name"], kinds[prop["name"]], kinds[shared]))
            continue
        # The deprecation names a CLASS, not a member: MTRTestClusterClusterSimpleStruct's members all say
        # "Please use MTRUnitTestingClusterSimpleStruct", the subclass this class is a deprecated alias of.
        # That is a statement about the class and not about a member, so there is nothing to share and
        # nothing to refuse. It IS reported when the host measured a shared member and the port cannot use
        # it, which is the case a reader has to know about.
        if entry and entry["measured"] and entry["measured"] != "own":
            unplaced.append((name, prop["name"], "the host shares %s with %s and the port cannot"
                             % (prop["name"], shared)))

    # One slot per property, and one per SHARED value: an alias and the member it shares with are one ivar,
    # which is what the host does and what the port must do.
    # One slot per property, and ONE slot per shared value: an alias and the member the host shares its
    # storage with are one ivar, which is what the host does. A category member has no @synthesize to give
    # it an ivar, so its slot is declared in the object's own class extension below - and when the two types
    # differ there is no shared ivar at all, and the alias keeps one of its own.
    CONVERSION_TYPES.clear()
    CONVERSION_TYPES.update({shared: kinds[shared] for prop in own + members
                             if (shared := prop.get("shares")) and shared in kinds})
    # An own member that SHARES an ivar with its successor cannot be @synthesize'd: the synthesis gives it a
    # second ivar of its own, the accessors the hand-written ones below read the shared one, and the member
    # then answers nil where its successor answers the shared value. That is what
    # `MTRApplicationBasicClusterApplicationStruct.catalogVendorId` did - 0 on the host, nil in the port,
    # with both SDKs declaring it NSNumber * nonnull - and it is the same shape as a category member, so it
    # is emitted the same way: accessors written out over the shared storage.
    shared_own = [prop for prop in own if prop.get("shares") and prop["shares"] != prop["name"]]
    if shared_own:
        members = members + shared_own
        own = [prop for prop in own if prop not in shared_own]
    slots = {prop["name"]: "_" + prop["name"] for prop in own}
    for prop in members:
        slots[prop["name"]] = ("_" + prop["shares"] if prop.get("shares")
                               else "_charon_" + prop["name"])
    for prop in own + members:
        if prop.get("shares") and prop["shares"] != prop["name"]:
            slots[prop["name"]] = slots.get(prop["shares"], "_" + prop["shares"])

    body = [PARAMS_PREAMBLE.format(name=os.path.basename(path), params=name,
                                   introduced=version or "16.0",
                                   declared=counts["declared"], written=counts["written"],
                                   total=counts["total"],
                                   protocols=", ".join(info["protocols"]) or "no protocol of its own")]

    def synthesis(prop):
        return "@synthesize %s = _%s;\n" % (prop["name"], prop["name"])

    # Storage a category's accessors use and no @synthesize can declare: every slot of theirs that is not an
    # ivar of the class's own @interface. Declared where the accessors use it, in the object's own class
    # extension, which is where a cluster object already keeps its device, endpoint and queue.
    own_names = {prop["name"] for prop in own}
    extra = []
    for prop in members:
        slot = slots[prop["name"]]
        if slot[1:] in own_names or slot[1:] in [each[1:] for each in extra]:
            continue
        extra.append((slot, prop["type"]))
    if extra:
        body.append("// Storage for the deprecated names the SDK declares in a CATEGORY of this class, and for\n"
                    "// the members they share it with: a category cannot hold an ivar, so these are the port's\n"
                    "// own, and they are here because the accessors below are what read and write them.\n")
        body.append("@interface %s () {\n" % name)
        for slot, kind in extra:
            body.append("    %s %s;\n" % (kind, slot))
        body.append("}\n@end\n\n")
    if host and host.get("own_description"):
        body.append(describe_helpers())
    body.append("@implementation %s\n\n" % name)
    seen = []
    for prop in own:
        if prop["name"] not in seen:
            body.append(synthesis(prop))
            seen.append(prop["name"])
    if seen:
        body.append("\n")
    if copying:
        every = list(own)
        for prop in members:
            if slots[prop["name"]] not in [slots[each["name"]] for each in every]:
                every.append(prop)
        body.append("// NSCopying, by declaration: the copy owns its own ivars, so writing to the copy never\n"
                    "// reaches back into the original.\n")
        body.append("- (id)copyWithZone:(NSZone *)zone\n{\n    %s *copied = [[%s allocWithZone:zone] init];\n"
                    % (name, name))
        for prop in every:
            body.append("    copied->%s = self->%s;\n" % (slots[prop["name"]], slots[prop["name"]]))
        if not every:
            body.append("    (void)zone;\n")
        body.append("    return copied;\n}\n\n")
    if name not in unavailable:
        body.append("- (instancetype)init\n{\n    self = [super init];\n    if (!self) {\n"
                    "        return nil;\n    }\n")
        for prop in own:
            store = stores.get(prop["name"])
            if store is not None:
                token, stored = store_value(store[0])
                derived = derived_default(prop)[0]
                if token is None:
                    STORE_UNREAD.append((name, prop["name"], store[0], store[1]))
                elif token == derived:
                    pass
                elif derived == "nil" or stored is None:
                    # The two cases default_of() names: this SDK declares the member nullable and that tree
                    # stores a value into it, or that tree stores nothing and this SDK declares the member
                    # not nullable. Both are the two SDKs' NULLABILITY differing, and the port keeps this
                    # one's answer, so the store is listed rather than applied.
                    STORE_KEPT.append((name, prop["name"], store[1], store[0],
                                       "this SDK declares it nullable" if derived == "nil"
                                       else "this SDK declares it nonnull and the store holds no value"))
                else:
                    STORE_MOVED.append((name, prop["name"], store[1], token))
                    # The class a nested member is given is checked against the SDK, and the check is the
                    # deprecated/current PAIR: a store naming a class other than the member's declared type
                    # is right exactly when the declared type is that class's own deprecated spelling, which
                    # is what `MTR_DEPRECATED("Please use MTRUnitTestingClusterSimpleStruct")` says above
                    # `@interface MTRTestClusterClusterSimpleStruct : MTRUnitTestingClusterSimpleStruct`.
                    # Any other class name is the framework's source and this SDK disagreeing, and the run
                    # names it instead of writing it.
                    if token.startswith("object:"):
                        given = token.split(":", 1)[1]
                        declared = bare_type(prop).replace("*", " ").split()
                        declared = declared[-1] if declared else ""
                        said = (FAMILIES.get(declared) or {}).get("deprecated_for")
                        if given not in FAMILIES:
                            STORE_CLASSES.append((name, prop["name"], given, store[1],
                                                  "the SDK declares no class of that name"))
                        elif given != declared and said != given:
                            STORE_CLASSES.append((name, prop["name"], given, store[1],
                                                  "the SDK declares the member %s, which is not a deprecated"
                                                  " spelling of %s" % (declared, given)))
            value = default_of(prop, store)
            if value:
                body.append("    %s = %s;\n" % (slots[prop["name"]], value))
        body.append("    return self;\n}\n\n")
    if members:
        body.append("// The properties the SDK declares in a CATEGORY of this class - MTRGroupsClusterAddGroupParams\n"
                    "// carries the old `groupId` beside the `groupID` of its own @interface, and 17 classes\n"
                    "// are shaped so. Their accessors are written out over the storage above, because a category\n"
                    "// cannot hold an ivar and clang refuses @synthesize for one in either place.\n")
        for prop in members:
            shared = prop.get("shares")
            body.append(member_accessors(prop, slots,
                                         CONVERSION_TYPES.get(shared) if shared else None))
    described = (host or {}).get("own_description")
    if described is None:
        body.append("// -description: the host does not have this class, so the header's answer stands and this\n"
                    "// object does not override it. Named by the run, per class, from the host measurement.\n")
    elif described:
        body.append(describe_body(name, own, slots))
    body.append("@end\n")
    for where, said, wanted in unplaced:
        SHARED_STORAGE_REFUSED.append((where, said, wanted))
    with open(path, "w") as out:
        out.write("".join(body))
    return len(own) + len(members)


def category_label(label):
    """The port's own name for a category the SDK declares as `label`.

    A category name is invisible at runtime - a program reaches a class by name - but two categories of one
    name on one class are two sets of the same members, and clang resolves the duplicate ivar in link order
    rather than refusing it. The port's name is therefore its own, so it can never be the framework's.
    """
    return "Charon" + label


# A member whose declared type names a class that is ITSELF a deprecated spelling, and where the port would
# have to store something else. Written by retype_deprecated() and counted by the run.
RETYPED = []


def retype_deprecated(families, wanted):
    """A property typed with a deprecated CLASS is declared with the class that one is a spelling of.

    `MTRTestClusterClusterNestedStruct.c` is declared `MTRTestClusterClusterSimpleStruct * _Nonnull` in SDK
    26.2, and SDK 26.2's own deprecated spelling is a SUBCLASS of what the member holds: the framework's
    -init stores `[MTRUnitTestingClusterSimpleStruct new]` (zap-generated/MTRStructsObjc.mm:14623), so the
    value in that member is the SUPERCLASS of the type the header names, and the header's promise cannot be
    kept by anything that stores what the framework stores. Measured on the host, the reading is
    `MTRUnitTestingClusterSimpleStruct(...)` and not `MTRTestClusterClusterSimpleStruct(...)`.

    Which class is the deprecated spelling of which is not a list here: it is each class's OWN
    `MTR_DEPRECATED("Please use X")` annotation, read by payload_classes() - 120 pairs over the SDK's 1,330
    classes, 7 of which type a member this way. The port declares the member with the class it actually
    holds, which is also the class whose accessor answers it in the framework, because the deprecated class
    declares none of its own.
    """
    def base_of(prop):
        spelling = bare_type(prop).replace("*", " ").split()
        return spelling[-1] if spelling else ""
    # Only the plain data family, because only those classes' declarations this run writes: `MTRDevice`'s
    # `deviceController` is typed with a deprecated class too, and its declaration is Matter.h's own, which
    # this does not touch.
    for name in wanted:
        info = families.get(name)
        if info is None:
            continue
        for prop in info["properties"] + [each for label in sorted(info.get("categories", {}))
                                          for each in info["categories"][label]]:
            said = base_of(prop)
            current = (families.get(said) or {}).get("deprecated_for")
            if not current or current not in families:
                continue
            RETYPED.append((name, prop["name"], said, current))
            prop["type"] = prop["type"].replace(said, current)


def payload_interface(name, info, older):
    """The @interface CharonMatterTypes.h needs for one plain data class, or nothing.

    Two shapes, and which one is right is measured rather than chosen:

    * the SDK this library builds against declares NO class of this name, so the port declares the whole
      thing - its superclass, its protocols and every property 26.2 gives it - because a declaration is
      what the @implementation below it needs and an object that implements a class no @interface declares
      is `cannot find interface declaration for`. There are 538 of these, and the file they go in is
      imported by every object in the library.

    * that SDK declares the class, so the port does NOT redeclare it - `duplicate interface definition for
      class` - and carries only what the later SDK added to it, as a CLASS EXTENSION in the same header.
      26.2 adds properties to 313 of the classes the older SDK declares: MTRReadParams gains minEventNumber
      and assumeUnknownAttributesReportable, MTRSubscribeParams gains minInterval and maxInterval, and a
      response params gains the fields its command gained. An extension with no ivars is what a second
      header may add to a class, and the object's @synthesize lines cover the union.

    And the shape that is neither: a CATEGORY. 17 of the classes declare a property in a `(Deprecated)`
    category - MTRGroupsClusterAddGroupParams carries `groupID` in its own @interface and the old `groupId`
    beside it - and a category's property cannot be synthesized in the class's @implementation. It is
    declared and implemented as a category, under the port's own category name, which is what the SDK does.
    """
    own = info["properties"]
    # EVERY property the older SDK declares for this class, in ANY of its declarations. A nullability the
    # newer SDK relaxed is the case that makes the difference: 16.4 declares MTRDiagnosticLogsCluster
    # RetrieveLogsResponseParams' `content` `_Nonnull` in its own `(Deprecated)` category and 26.2 declares
    # the same property `_Nullable`, and redeclaring it beside the SDK's own is `nullability specifier
    # '_Nullable' conflicts with existing specifier '_Nonnull'`. Where the older SDK says it at all, the port
    # does not say it again - and payload_buckets() still synthesizes or writes the accessors for it.
    declared_own = set()
    if name in older:
        declared_own.update(each["name"] for each in older[name]["properties"])
        for props in older[name].get("categories", {}).values():
            declared_own.update(each["name"] for each in props)
    else:
        declared_own = None
    out = []
    if declared_own is None:
        head = "@interface %s : %s" % (name, info["super"])
        if info["protocols"]:
            head += " <%s>" % ", ".join(info["protocols"])
        out.append("\n".join([head] + property_lines(own) + ["@end"]))
    else:
        extra = [prop for prop in own if prop["name"] not in declared_own]
        if extra:
            out.append("\n".join(["@interface %s ()" % name] + property_lines(extra) + ["@end"]))
    for label, props in sorted(info.get("categories", {}).items()):
        if not props:
            continue
        known = declared_own or set()
        extra = [prop for prop in props if prop["name"] not in known]
        if not extra:
            continue
        out.append("\n".join(["@interface %s (%s)" % (name, category_label(label))]
                           + property_lines(extra) + ["@end"]))
    return "\n\n".join(out) if out else None


def property_lines(properties):
    """One `@property` declaration per property, the way the SDK's own header writes it."""
    return ["@property (%s) %s %s;" % (prop["attributes"], prop["type"], prop["name"])
            for prop in properties]


# The library builds against the 16.4 SDK, and this generator reads the 26.2 headers. A cluster object that
# names a type 16.4 does not declare does not compile for the target - `unknown type name
# 'MTRAccessControlClusterReviewFabricRestrictionsResponseParams'` - even though it compiles on the machine
# that generated it, because that machine has the 26.2 SDK. Pointer uses need only a forward declaration.
MATTER_TYPE = re.compile(r"\bMTR[A-Za-z0-9_]+\b")
DECLARED_16 = set()
# The library's SDK's own cluster headers, read once, for the members its @interface declares and the
# newer one dropped - see cluster_declarations().
DECLARED_LINES_16 = []


def cluster_headers(sdk):
    """The cluster headers of an SDK, as one list of lines, or nothing when it has none."""
    lines = []
    for header in HEADERS:
        path = os.path.join(sdk, header)
        if os.path.exists(path):
            with open(path) as handle:
                lines.extend(handle.read().splitlines())
    return lines


def load_declared(sdk16):
    """Every class and protocol the SDK the LIBRARY builds against declares, from its Matter headers."""
    if not sdk16:
        return set()
    framework = os.path.join(sdk16, "System/Library/Frameworks/Matter.framework/Headers")
    if not os.path.isdir(framework):
        raise SystemExit("no Matter headers at %s: pass the SDK the library builds against" % framework)
    declared = set()
    for name in sorted(os.listdir(framework)):
        if not name.endswith(".h"):
            continue
        with open(os.path.join(framework, name)) as handle:
            # EVERY identifier the header mentions, not only the classes it declares with @interface.
            # @class on a name 16.4 declares as a typedef or an enum is itself an error - MTRStatusCompletion
            # is `typedef void (^MTRStatusCompletion)(NSError *)`, and a rule that only collected @interface
            # names treated it as undeclared, emitted @class for it, and turned 2 clean objects into 140
            # failing ones.
            declared.update(re.findall(r"\bMTR[A-Za-z0-9_]+\b", handle.read()))
    return declared


# The shared types 16.4 does not declare. Measured, not assumed: compiling all 142 against the SDK the
# library builds against and collecting every "cannot find interface declaration for" name gives exactly
# ONE - MTRGenericBaseCluster, in 79 objects - and it is itself : MTRCluster, which is : NSObject.
#
# DECLARATIONS go in one private header and IMPLEMENTATIONS in one object per class, so nothing is defined
# twice: a cluster object imports the header and carries only its own @implementation, and the sweep's
# "no strong global symbol defined by two objects" stays clean.
SHARED_TYPES = (
    # (class, superclass, the properties it declares, in header order)
    ("MTRCluster", "NSObject", ("endpointID",)),
    ("MTRGenericBaseCluster", "MTRCluster", ()),
)



TYPES_HEADER = """//
//  CharonMatterTypes.h
//  Matter
//
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers. These are the types the
//  clusters sit on that the SDK this library builds against does not declare: measured by compiling every
//  generated object against that SDK and collecting every `cannot find interface declaration for`, which
//  gives exactly these, in dependency order.
//
//  DECLARATIONS ONLY. Every implementation of these classes is in an object beside this header, so no
//  symbol here is defined twice.
//

#ifndef CHARON_MATTER_TYPES_H
#define CHARON_MATTER_TYPES_H

#import <Foundation/Foundation.h>
// Matter.h for what the SDK this library builds against DOES declare - MTRCluster, the superclass of the one
// class below, among them - and the @class lines after it for the names it does not. Without this the
// header does not stand up on its own: `cannot find interface declaration for 'MTRCluster', superclass of
// 'MTRGenericBaseCluster'`.
#import <Matter/Matter.h>

{forwards}// The nullability of everything below is stated ONCE, here, rather than per parameter: 32 of the
// SDK's Matter headers open an assume-nonnull region, so a pointer in this header with no annotation of
// its own is read as nonnull by one declaration and as _Nullable by another, and that is
// `nullability specifier '_Nullable' conflicts with existing specifier 'nonnull'`.
NS_ASSUME_NONNULL_BEGIN

{declarations}
NS_ASSUME_NONNULL_END

#endif

"""

TYPES_OBJECT = """//
//  {name}
//  Matter
//
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers. {declaration}
//

#import <Matter/Matter.h>
#import "CharonMatterTypes.h"

@implementation {name}

{body}
@end

"""


def cluster_interface(cluster, items, supers):
    """The @interface of a cluster class the target's SDK does not declare, for CharonMatterTypes.h.

    It carries the class's own members, every one the object below implements, because an @interface with
    none of them is `-Wincomplete-implementation` on the first method - which is how the two members of
    MTRClusterStateCacheContainer reached a port object once already.
    """
    if not DECLARED_16 or cluster in DECLARED_16:
        return None
    attributes, commands, version, cache_reads, initialisers, cache = facts(items)
    lines = ["@interface %s : %s" % (cluster, supers or "NSObject")]
    # The dictionary is keyed by the attribute's name, which is the name itself.
    for name in sorted(attributes):
        lines.append("@property (nonatomic, strong) NSMutableDictionary *%sValues;" % name)
    for info in commands.values():
        for key in ("signature", "noparam"):
            shape = info.get(key)
            if shape:
                # The same rule the object applies: this interface sits under the header's
                # assume-nonnull region, so it states nonnull and the object must not say _Nullable.
                lines.append("%s;" % shape_line(shape))
    for info in cache.values():
        if info.get("signature"):
            lines.append("%s;" % shape_line(info["signature"]))
    for info in initialisers:
        lines.append("%s;" % shape_line(info["signature"]))
    lines.append("@end")
    return "\n".join(lines)

def emit_shared_types(arguments, stem_of, cluster_interfaces=(), payload_interfaces=()):
    """One header of declarations and one object per shared class. Dependency order is the order above.

    `payload_interfaces` are the plain data classes' own declarations, already in dependency order by
    plain_data_classes(): each declares its superclass, so a parent has to be above its children in the one
    header. They come after the cluster interfaces because a cluster interface is what forward-declares the
    payload types it names, and a class declared twice is not what this header is for.
    """
    written = []
    declarations, bodies = [], []
    for name, supers, properties in SHARED_TYPES:
        # The @interface is written only for what the target's SDK does not declare. MTRCluster is in this
        # list because MTRGenericBaseCluster inherits from it and the list is in dependency order, but 16.4
        # DOES declare MTRCluster, so declaring it here as well was `duplicate interface definition for class
        # 'MTRCluster'`.
        if name not in DECLARED_16:
            declarations.append("@interface %s : %s\n@end\n" % (name, supers))
        # The OBJECT is written for every one of them, whether the SDK declares the class or not. The
        # declaration says the class exists at compile time; the object is what makes it EXIST at runtime,
        # and the release this family is carried into has no Matter.framework at all: every row in
        # registry/Matter/ios16.json says so, and 6.1.3 is one of them. Without an object for MTRCluster the
        # 143 objects reference _OBJC_CLASS_$_MTRCluster and _OBJC_METACLASS_$_MTRCluster, and the library
        # links with `Undefined symbols for architecture armv7` - measured: of every symbol the 143 leave
        # open, those two are the only Matter ones, and both are the superclass every one of them names.
        #
        # A class the SDK declares gets NO member here: MTRCluster.h in 16.4 declares -init and +new as
        # NS_UNAVAILABLE and no property, while 26.2 adds endpointID at 17.4. What the port carries is the
        # API the SDK it compiles against declares, and that is the class and nothing else.
        body = [] if name in DECLARED_16 else ["@synthesize %s = _%s;\n" % (each, each) for each in properties]
        declaration = ("Beside CharonMatterTypes.h, which declares this class. Read-only ids, kept in the"
                      " class's own state, because a port object has to BE the class and nothing in it"
                      " reaches a fabric.") if name not in DECLARED_16 else (
                      "The class is DECLARED by the SDK this library compiles against and IMPLEMENTED here:"
                      " the release this family is carried into has no Matter.framework at all, so every"
                      " class above this one names it and nothing else would define it. Its header in 16.4"
                      " declares -init and +new NS_UNAVAILABLE and no member, so that is what it carries.")
        stem = stem_of(name)
        if stem.lower() in NAMED:
            print("ERROR: %s and %s differ only by case" % (NAMED[stem.lower()], name))
            NAME_ERRORS.append((NAMED[stem.lower()], name))
            continue
        NAMED[stem.lower()] = name
        path = os.path.join(arguments.out, stem + ".m")
        with open(path, "w") as out:
            out.write(TYPES_OBJECT.format(name=name, declaration=declaration,
                                          body="\n".join([""] + body if body else [""])))
        written.append(name)
        if name in DECLARED_16:
            print("  %s: the SDK declares the class, so its object carries the class and none of its members;"
                  " the release it is carried into has no Matter.framework" % name)
    header = os.path.join(arguments.out, "CharonMatterTypes.h")
    # The plain data classes go ABOVE the cluster interfaces, and the order is the dependency order both
    # ways: a plain data class declares its superclass, and a cluster interface names plain data classes as
    # the types of its command parameters. With them below, every one of the 79 cluster interfaces that
    # names a payload class the library's SDK does not declare is `unknown type name` - measured, and it is
    # the whole reason the @class line above exists.
    declared_here = set(re.findall(r"@interface\s+(\w+)", "\n".join(payload_interfaces)))
    for text in payload_interfaces:
        declarations.append(text)
    for text in cluster_interfaces:
        declarations.append(text)
    if declared_here:
        # A class this header declares is not a type the CLUSTER interfaces above can only forward-declare:
        # the two statements of one name are redundant, and the comment above the @class line would then
        # count a name it no longer holds.
        global HEADER_FORWARDS
        HEADER_FORWARDS = [each for each in HEADER_FORWARDS if each not in declared_here]
        print("CharonMatterTypes.h: %d plain data class declaration(s) the library's SDK does not have, and"
              " %d forward declaration(s) left for the types only the cluster interfaces name"
              % (len(declared_here), len(HEADER_FORWARDS)))
    with open(header, "w") as out:
        forwards = ""
        if HEADER_FORWARDS:
            forwards = ("// The types the interfaces below name that the SDK this library builds against does\n"
                        "// not declare: %d of them, forward-declared here because pointer uses need only this.\n"
                        "@class %s;\n\n" % (len(HEADER_FORWARDS), ", ".join(sorted(HEADER_FORWARDS))))
        out.write(TYPES_HEADER.format(forwards=forwards, declarations="\n".join(declarations)))
    print("CharonMatterTypes.h: %d shared class declaration(s), %d cluster interface(s), "
          "%d plain data declaration(s); %d object(s) written"
          % (len(declarations) - len(cluster_interfaces) - len(payload_interfaces),
             len(cluster_interfaces), len(payload_interfaces), len(written)))
    return written

def own_interface(cluster, supers):
    """`@interface` for a cluster the SDK the library builds against does not declare.

    16.4 declares 815 classes and not, say, MTRBaseClusterActivatedCarbonFilterMonitoring, which arrived
    later. An object that IMPLEMENTS a class with no @interface anywhere is `cannot find interface
    declaration for`, so the class is declared here, with the superclass the 26.2 header gives it. A cluster
    16.4 DOES declare is left alone: there the SDK's own interface is the declaration and re-declaring it
    with different storage is what broke the params objects.
    """
    if not DECLARED_16 or cluster in DECLARED_16:
        return []
    lines = ["// %s arrived after the SDK this library builds against, so the class is declared here and" % cluster,
             "// implemented below. The superclass is the one the header gives it, read from the header.",
             "@interface %s : %s" % (cluster, supers or "NSObject"),
             "@end",
             ""]
    return lines

def forward_declarations(body, self_class):
    """`@class X;` for every Matter type the object names that the target's SDK does not declare.

    Read out of the text the emit just produced rather than out of the header, so a type can only be
    forward-declared if the object really names it.
    """
    if not DECLARED_16:
        return []
    named = set(MATTER_TYPE.findall(body))
    # A type used in a SUPERCLASS position must not be forward-declared: `@class X;` then `: X` is
    # "attempting to use the forward class 'X' in a superclass position". The superclass is the one the
    # object's own @interface names, and the SDK declares it, so it is never missing from the headers.
    supers = set(re.findall(r"@interface\s+\w+\s*:\s*(\w+)", body))
    missing = sorted(name for name in named
                     if name != self_class and name not in DECLARED_16
                     and name not in supers
                     and not name.startswith("Charon"))
    return missing

def shape_line(shape):
    """A shape's declaration, as BOTH the interface and the implementation write it.

    One function on purpose. The two used to disagree: the header said _Nullable where the object said
    nothing, or the reverse, and clang reported that as `nullability specifier '_Nullable' conflicts with
    existing specifier 'nonnull'` - once for MTRBaseClusterContentControl, once for
    MTRBaseClusterGroupKeyManagement, and then 79 times over when only one of the two had been taught the
    rule. A declaration that is written twice must be produced once.
    """
    return strip_region_nullability(signature(shape))


def strip_region_nullability(text):
    """The `_Nullable` / `_Nonnull` a parameter does NOT carry when its interface sits in the region.

    CharonMatterTypes.h states the nullability once, over an assume-nonnull region. A method whose
    declaration is under that region must not also say _Nullable on a parameter, and this is where the two
    disagreed: the header said nonnull, the object said _Nullable, and clang called it a conflict rather than
    resolving it. Only the two pointer specifiers go; `nullable` written before a type is a different
    spelling of the same thing and is left alone.
    """
    return text.replace(" _Nullable", "").replace(" _Nonnull", "")


def stored_value(slot, name, kind):
    """The assignment that puts one initializer argument into the ivar that holds it.

    The header's own declaration decides: an object pointer is stored as it is, and so is a dispatch
    queue, which is an object on every target this port builds for (OS_OBJECT_USE_OBJC is 1 from iOS 6
    on) even though the typedef carries no star. A C value is boxed, because the storage holds an
    NSNumber: TestCluster's deprecated initWithDevice:endpoint:queue: takes a uint16_t endpoint, and
    without the box that assignment is `implicit conversion of 'uint16_t' to 'NSNumber *' is disallowed
    with ARC`. A shape this does not fit is a shape the run reports rather than one it drops.
    """
    if kind.endswith("*") or kind.startswith("dispatch_"):
        return "%s = %s;" % (slot, name)
    return "%s = @(%s);" % (slot, name)


def emit(path, cluster, supers, attributes, commands, version, cache_reads, cache, initialisers):
    """The family as one object, and the object IS the class: the release has no such class.

    Every selector below is the SDK header's own, copied out of the declaration rather than rebuilt from
    a pattern. That is the general fix: a nullability between the type and the selector, a
    subscriptionEstablished: block, a three-argument subscribe - enumerating the shapes is what left two
    members unimplemented last pass, and the header already knows every one of them.
    """
    body = [PREAMBLE.format(name=os.path.basename(path), cluster=cluster,
                            supers=supers or "Matter cluster", cache=cache_reads)]
    if chain_blocked(cluster):
        body.append(SUPPRESSED_CHAIN.format(cluster=cluster))
    body.append("// A class EXTENSION, not a category: it carries the storage and is invisible at\n"
                "// runtime, so the port's class is still the only implementation of the name.\n")
    body.append("@interface %s () {\n" % cluster)
    body.append("    id _charon_device;\n")
    body.append("    NSNumber *_charon_endpoint;\n")
    body.append("    dispatch_queue_t _charon_queue;\n")
    body.append("}\n")
    body.append("@end\n\n")
    body.append("@implementation %s\n\n" % cluster)

    # The class interface above declares one NSMutableDictionary property per attribute, and the
    # library builds with -Werror=objc-missing-property-synthesis, so every one of them is synthesized
    # here by name: the flag is an error on a property the compiler would otherwise have synthesized
    # for us. They cannot be declared in the header instead - @synthesize inside an @interface is an
    # illegal interface qualifier - so the object that implements the class is where they go, which is
    # the same place the payload objects above already synthesize theirs, and only where the
    # interface above was written: for a cluster 16.4 declares, the SDK's own interface is the
    # declaration and the compiler synthesizes those properties itself.
    if not DECLARED_16 or cluster not in DECLARED_16:
        for _name in sorted(attributes):
            body.append("@synthesize %sValues = _%sValues;\n" % (_name, _name))
        body.append("\n")
    body.append("// The values the caller has written, by attribute name: one table, keyed by the\n"
                "// object, guarded by a lock, because armv7 has no thread-local storage to rely on.\n")
    body.append("+ (NSMutableDictionary *)charon_port_values\n{\n"
                "    static NSMutableDictionary *table;\n"
                "    @synchronized ([%s class]) {\n"
                "        if (!table) {\n"
                "            table = [NSMutableDictionary dictionary];\n"
                "        }\n"
                "    }\n"
                "    return table;\n}\n\n" % cluster)
    body.append("// The error a member that would need a node answers, on a release with no Matter\n"
                "// hardware: there is nothing to read from and nothing to commission onto.\n")
    body.append("+ (NSError *)charon_port_no_node_error\n{\n"
                "    return [NSError errorWithDomain:NSCocoaErrorDomain code:4096 userInfo:nil];\n}\n\n")
    for entry in initialisers:
        body.append(as_comment(shape_line(entry["signature"])))
        # The three arguments go into the three ivars the class extension above declares: an initializer
        # that returns self and keeps nothing is a class whose own state nothing can name. It does NOT
        # chain to the superclass initializer, because it cannot: MTRCluster declares -init NS_UNAVAILABLE
        # against the SDK this library builds with, so `self = [super init]` is `error: 'init' is
        # unavailable` (measured, and neither a category nor a class extension redeclaring -init lifts the
        # attribute), and an initializer that leaves the chain out is what -Wobjc-designated-initializers
        # reports on the 60 objects whose @interface is that SDK's own. Those 60 objects carry the
        # repository's own per-file pragma for it, with the reason above it - SUPPRESSED_CHAIN below and
        # chain_blocked() beside it - and facts/Matter/Matter.md carries the measurement.
        typed = [(name, kind) for _, name, kind in parse(entry["signature"])[1] if name]
        if not typed:
            OFFENDERS.append((cluster, "initWithDevice", "initialiser", entry["signature"]))
            continue
        slots = ("_charon_device", "_charon_endpoint", "_charon_queue")
        if len(typed) != len(slots):
            OFFENDERS.append((cluster, "initWithDevice", "initialiser", entry["signature"]))
            continue
        stored = "".join("    %s\n" % stored_value(slot, name, kind)
                         for slot, (name, kind) in zip(slots, typed))
        body.append("%s\n{\n%s    return self;\n}\n\n"
                    % (shape_line(entry["signature"]), stored))
    for name, info in attributes.items():
        value = info["value"]
        body.append("// %s, a %s.\n" % (name, value))
        for s in info.get("read", []):
            names = arguments_or_note(s, cluster, name, "read")
            if names is None:
                continue
            completion, rule = completion_of(s)
            if completion is None:
                OFFENDERS.append((cluster, name, "read", s))
                continue
            body.append("%s\n{\n"
                        "    if (!%s) {\n        return;\n    }\n"
                        "    id written = [%s charon_port_values][@\"%s\"];\n"
                        "    %s;\n}\n\n"
                        % (s, completion, cluster, name, completion_call(s, completion, "written")))
        for s in info.get("read_params", []):
            names = arguments_or_note(s, cluster, name, "read_params")
            if names is None:
                continue
            completion, rule = completion_of(s)
            if completion is None:
                OFFENDERS.append((cluster, name, "read_params", s))
                continue
            unused = "".join("    (void)%s;\n" % each for each in names[:-1])
            body.append("%s\n{\n%s"
                        "    if (!%s) {\n        return;\n    }\n"
                        "    id written = [%s charon_port_values][@\"%s\"];\n"
                        "    %s;\n}\n\n"
                        % (s, unused, completion, cluster, name,
                           completion_call(s, completion, "written")))
        for s in info.get("write", []):
            names = arguments_or_note(s, cluster, name, "write")
            if names is None or len(names) < 2:
                if names is not None:
                    OFFENDERS.append((cluster, name, "write", s))
                continue
            value_name = names[0]
            completion, rule = completion_of(s)
            if completion is None:
                OFFENDERS.append((cluster, name, "write", s))
                continue
            body.append("%s\n{\n"
                        "    [%s charon_port_values][@\"%s\"] = %s;\n"
                        "    if (%s) {\n        %s;\n    }\n}\n\n"
                        % (s, cluster, name, value_name, completion, completion_call(s, completion)))
        for s in info.get("subscribe", []):
            names = arguments_or_note(s, cluster, name, "subscribe")
            if names is None:
                continue
            unused = "".join("    (void)%s;\n" % each for each in names)
            body.append("%s\n{\n%s"
                        "    [%s charon_port_values][@\"%s\"] = @\"subscribed\";\n}\n\n"
                        % (s, unused, cluster, name))
    for name, info in cache.items():
        body.append("// The cached read of %s: no value and the error, because there is no node.\n" % name)
        args = arguments_or_note(info["signature"], cluster, name, "cached read")
        if args is None:
            continue
        completion, rule = completion_of(info["signature"])
        if completion is None:
            OFFENDERS.append((cluster, name, "cached read", info["signature"]))
            continue
        unused = "".join("    (void)%s;\n" % each for each in args[:-1])
        body.append("%s\n{\n%s"
                    "    if (!%s) {\n        return;\n    }\n"
                    "    %s;\n}\n\n"
                    % (info["signature"], unused, completion,
                       completion_call(info["signature"], completion,
                                       error="[%s charon_port_no_node_error]" % cluster)))
    # Every shape this object emits has to match the interface it lives under. For a cluster whose
    # declaration is in the shared header, that means the header's region nullability, not the 26.2
    # header's per-parameter annotation.
    # Unconditionally, because the interface this @implementation lives under is nonnull in BOTH cases:
    # our own CharonMatterTypes.h says so in its region, and the SDK's is inside an assume-nonnull region
    # for every cluster 16.4 declares. An earlier version of this stripped only for the clusters our header
    # declared - which is the reverse of the truth, and left MTRBaseClusterGroupKeyManagement failing on a
    # parameter the SDK itself declares nonnull.
    if True:
        commands = dict((verb, dict((key, strip_region_nullability(value))
                                    for key, value in info.items()
                                    if isinstance(value, str)))
                        for verb, info in commands.items())
        for info in attributes.values():
            for key in ("read", "read_params", "write", "subscribe"):
                if isinstance(info.get(key), list):
                    info[key] = [strip_region_nullability(shape) for shape in info[key]]
        for info in cache.values():
            if isinstance(info.get("signature"), str):
                info["signature"] = strip_region_nullability(info["signature"])

    for verb, info in commands.items():
        if info.get("noparam"):
            shape = info["noparam"]
            names = arguments_or_note(shape, cluster, verb, "command")
            if names is not None:
                completion, rule = completion_of(shape)
                if completion is not None:
                    unused = "".join("    (void)%s;\n" % each for each in names[:-1])
                    body.append("%s\n{\n%s"
                                "    if (%s) {\n        %s;\n    }\n}\n\n"
                                % (shape, unused, completion, completion_call(shape, completion)))
                else:
                    OFFENDERS.append((cluster, verb, "command", shape))
            else:
                OFFENDERS.append((cluster, verb, "command", shape))
        # The parameterised shape, and ONLY when this verb has one. A verb the header declares solely as
        # `<verb>WithCompletion:` carries no "signature" key at all, and reading it here unconditionally
        # is a KeyError the run died on the moment the pattern above started matching those verbs.
        if not info.get("signature"):
            continue
        body.append("// %s. It answers: there is nothing to reach on a release with no fabric.\n" % verb)
        names = arguments_or_note(info["signature"], cluster, verb, "command")
        if names is None:
            continue
        completion, rule = completion_of(info["signature"])
        if completion is None:
            OFFENDERS.append((cluster, verb, "command", info["signature"]))
            continue
        unused = "".join("    (void)%s;\n" % each for each in names if each != completion)
        body.append("%s\n{\n%s"
                    "    if (%s) {\n        %s;\n    }\n}\n\n"
                    % (info["signature"], unused, completion,
                       completion_call(info["signature"], completion)))
    body.append("@end\n")
    text = "".join(body)

    # The shared types, and this cluster's own interface when the target's SDK does not declare it, come
    # from the generated header: declarations there, implementations in the objects. Nothing is declared
    # twice, and this object carries only its @implementation.
    text = text.replace("#import <Matter/Matter.h>",
                        "#import <Matter/Matter.h>\n#import \"CharonMatterTypes.h\"", 1)
    # The forward declarations go in the SHARED HEADER, not in this object: the interfaces there declare
    # methods whose parameter types are 26.2-only, and a @class line in the object is textually AFTER the
    # header that names those types, so the header could not see them and every interface line was
    # "expected a type".
    forward = forward_declarations(text, cluster)
    if forward:
        for name in forward:
            if name not in HEADER_FORWARDS:
                HEADER_FORWARDS.append(name)
        FORWARDED.extend((cluster, name) for name in forward)
    with open(path, "w") as out:
        out.write(text)


SELF_TEST = [
    # The four declarations the parser is tested on: a read with a block, a write in its five-argument
    # shape, the initialiser with a nullability, and a no-argument declaration with an unavailable macro.
    ("- (void)readAttributeIdentifyTimeWithCompletion:(void (^)(NSNumber * _Nullable value, "
     "NSError * _Nullable error))completion MTR_AVAILABLE(ios(16.4), macos(13.3), watchos(9.4), "
     "tvos(16.4));",
     "readAttributeIdentifyTimeWithCompletion:", ["completion"], "completion"),
    ("- (void)writeAttributeIdentifyTimeWithValue:(NSNumber * _Nonnull)value\n"
     "    params:(MTRWriteParams * _Nullable)params\n"
     "    completionHandler:(MTRStatusCompletion)completionHandler MTR_AVAILABLE(ios(16.4));",
     "writeAttributeIdentifyTimeWithValue:params:completionHandler:",
     ["value", "params", "completionHandler"], "completionHandler"),
    ("- (instancetype _Nullable)initWithDevice:(MTRBaseDevice *)device MTR_AVAILABLE(ios(16.4));",
     "initWithDevice:", ["device"], "device"),
    ("- (instancetype)init MTR_UNAVAILABLE(ios(1));", "init", [], None),
]

# The property reader, on every shape the two SDKs write. Each one is a shape that has been got wrong, and
# the reason each is here is that the run that gets one wrong still exits 0 unless the compile catches it -
# which it does, but as `property declared in category 'Deprecated' cannot be implemented in class
# implementation` in one object of 1067, with nothing to say which reader lost it.
PROPERTY_SHAPES = [
    # (the declaration as the SDK writes it, type, name, annotation macro)
    ("NSNumber * _Nonnull operationType API_AVAILABLE(ios(16.1), macos(13.0), watchos(9.1), tvos(16.1))",
     "NSNumber * _Nonnull", "operationType", "API_AVAILABLE"),
    ("NSNumber * _Nonnull operationType MTR_AVAILABLE(ios(16.1), macos(13.0), watchos(9.1), tvos(16.1))",
     "NSNumber * _Nonnull", "operationType", "MTR_AVAILABLE"),
    # The argument label after the type: a reader that stopped at the first space got `NSArray` and `*`.
    ("NSArray * _Nullable externalIDList MTR_PROVISIONALLY_AVAILABLE",
     "NSArray * _Nullable", "externalIDList", "MTR_PROVISIONALLY_AVAILABLE"),
    # A generic argument carries a `*` of its own, which is why the walk is by character and not by token.
    ("NSArray<NSString *, NSString *> * _Nullable externalIDList "
     "MTR_AVAILABLE(ios(16.4), macos(13.3), watchos(9.4), tvos(16.4))",
     "NSArray<NSString *, NSString *> * _Nullable", "externalIDList", "MTR_AVAILABLE"),
    # A scalar, and a deprecated annotation whose arguments are themselves parenthesised lists.
    ("BOOL assumeUnknownAttributesReportable API_AVAILABLE(ios(17.6), macos(14.6), watchos(10.6), tvos(17.6))",
     "BOOL", "assumeUnknownAttributesReportable", "API_AVAILABLE"),
    ("NSNumber * _Nonnull timedInvokeTimeoutMs MTR_DEPRECATED("
     "\"Timed invoke does not make sense for server to client commands\", ios(16.1, 16.4), "
     "macos(13.0, 13.3), watchos(9.1, 9.4), tvos(16.1, 16.4))",
     "NSNumber * _Nonnull", "timedInvokeTimeoutMs", "MTR_DEPRECATED"),
    # No annotation at all, which is what SDK 16.4 writes for some of its own properties.
    ("NSNumber * minInterval", "NSNumber *", "minInterval", ""),
]


def self_test():
    """The parser, on the three signatures this work has actually tripped over. A parser with no unit
    test is a parser whose failures are found by compiling 145 objects."""
    failures = 0
    for text, want_selector, want_names, want_completion in SELF_TEST:
        got = selector_of(text)
        names = arguments(text)
        completion, rule = completion_of(text)
        for what, want, have in (("selector", want_selector, got),
                                 ("argument names", want_names, names),
                                 ("completion", want_completion, completion)):
            if want != have:
                print("self-test %s: wanted %r, got %r" % (what, want, have))
                failures += 1
    for text, want_type, want_name, want_annotation in PROPERTY_SHAPES:
        kind, declared, annotation = payload_line(text)
        for what, want, have in (("type", want_type, kind), ("name", want_name, declared),
                                 ("annotation", want_annotation, annotation)):
            if want != have:
                print("self-test property %s: wanted %r, got %r on %r" % (what, want, have, text[:60]))
                failures += 1
    print("self-test: %d declarations, %d properties, %d failures"
          % (len(SELF_TEST), len(PROPERTY_SHAPES), failures))
    return failures == 0


def check_header_stands_alone(path, sdk16):
    """CharonMatterTypes.h compiled by itself, with the includes it declares for itself.

    It is a header every one of the 143 objects imports, and a review found it does not compile alone -
    the imports that made it work were in the objects, not in the header. So it is checked alone, by
    exit status, in the same run that writes it.
    """
    if not sdk16 or not os.path.exists(path):
        return 0
    # ABSOLUTE, because the compile runs in the header's own directory and a relative --out hands the
    # compiler a path that does not exist there: the check then reports a header that stands alone as one
    # that does not, and fails every run that writes into the package tree rather than a scratch one.
    path = os.path.abspath(path)
    outcome = subprocess.call(
        ["xcrun", "clang", "-target", "arm64-apple-ios13.0", "-isysroot", sdk16, "-fobjc-arc", "-Wall",
         "-fsyntax-only", "-x", "objective-c",
         "-include", "Foundation/Foundation.h", "-include", "Matter/Matter.h", path],
        cwd=os.path.dirname(path) or ".")
    return outcome

def compile_objects(directory, sdk16, jobs=4):
    """Every object the run wrote, compiled the way the library builds. Returns the failures by name.

    The developer's SDK has the 26.2 headers, so an object that names a type the library's SDK does not
    declare compiles here and not there - 94 of 142 did, and nothing else in the pipeline could see it: the
    invariant counts selectors, the differential compiles against macOS where Matter exists, and the light
    guard runs on the host. So the compile is part of the generator, against the SDK the library is built
    with, and the run fails if any object does not compile.
    """
    if not sdk16 or not os.path.isdir(directory):
        return []
    names = sorted(name for name in os.listdir(directory) if name.endswith(".m"))
    marks = os.path.abspath(os.path.join(directory, ".compile-failures"))
    # Created empty before any compile: under xargs -P 4 each failing compile appends to this file, and
    # several racing `>>` on a file that does not exist yet is how a whole tree was reported as failing.
    open(marks, "w").close()
    listing = os.path.abspath(os.path.join(directory, ".compile-list"))
    with open(listing, "w") as out:
        out.write("\n".join(names) + "\n")
    command = ('xcrun clang -target arm64-apple-ios13.0 -isysroot %s -fobjc-arc -Wall -fsyntax-only "$0" '
               '>/dev/null 2>&1 || echo "$0" >> %s') % (sdk16, marks)
    subprocess.call(["xargs", "-P", str(jobs), "-n", "1", "sh", "-c", command],
                    stdin=open(listing), cwd=directory)
    with open(marks) as handle:
        failed = [line.strip() for line in handle if line.strip()]
    os.remove(marks)
    os.remove(listing)
    return failed

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sdk", help="the SDK to read the declarations from")
    parser.add_argument("--out", help="where the generated objects go")
    parser.add_argument("--classes", nargs="+", help="the clusters to emit")
    parser.add_argument("--classes-from", help="a file of cluster names, one a line - the list is 145 long")
    parser.add_argument("--contracts", help="where the .contract files go; they are TEST FIXTURES and do not belong in the package tree")
    parser.add_argument("--shared-types", action="store_true", help="emit CharonMatterTypes.h and one object per shared class")
    parser.add_argument("--sdk16", help="the SDK the LIBRARY builds against; types it does not declare get a forward declaration")
    parser.add_argument("--paths", action="store_true", help="also emit MTRClusterPath and the three that extend it")
    parser.add_argument("--cases",
                        help="write the probe's driver file here: one line per class and one per alias pair, "
                             "read out of the same buckets this run emits from")
    parser.add_argument("--host-measurements",
                        help="the committed data file tests/backports/host/matter/params-probe.m wrote, and the "
                             "generator's input for two things the header cannot say: which classes override "
                             "-description, and which member a deprecated alias shares storage with")
    parser.add_argument("--init-defaults",
                        default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             "matter-init-defaults.tsv"),
                        help="the committed data file tools/matter-init-source.py wrote out of the framework's "
                             "own tree, and what each class's -init stores; a header says nothing about an "
                             "initial value, and MTRReadParams' filterByFabric is one (it stores YES)")
    parser.add_argument("--params", action="store_true",
                        help="emit one object per plain data class the SDK's own Matter headers declare")
    parser.add_argument("--params-from", help="a file of plain data class names to emit instead of all of them")
    parser.add_argument("--self-test", action="store_true", help="parse three declarations and stop")
    arguments = parser.parse_args()

    if arguments.self_test:
        return 0 if self_test() else 1
    DECLARED_16.update(load_declared(arguments.sdk16))
    global DECLARED_LINES_16
    DECLARED_LINES_16 = cluster_headers(arguments.sdk16)
    lines = []
    for header in HEADERS:
        path = os.path.join(arguments.sdk, header)
        if not os.path.exists(path):
            continue
        with open(path) as handle:
            lines.extend(handle.read().splitlines())

    # The completion typedefs are declared in OTHER headers of the same framework - MTRCluster.h holds
    # MTRStatusCompletion, which is 1,435 of the call sites - so the whole Headers directory is read for
    # them and not just the two cluster headers the declarations come from. They are read by listing the
    # directory rather than from a list of names, so a typedef added to the SDK is found without this
    # being edited. The plain data classes are read from the same walk, for the same reason and with the
    # same result: a run that read four headers named in PAYLOAD_HEADERS found 914 of the 923 classes and
    # named the other 9 undeclared, all of which the SDK does declare.
    payload_lines = []
    for _, header_lines_of in matter_headers(arguments.sdk):
        payload_lines.extend(header_lines_of)

    for _, header_lines_of in matter_headers(arguments.sdk):
        TYPEDEF_COMPLETIONS.update(load_typedef_completions(header_lines_of))


    # The class list comes from the tree by default: clusters-emitted.txt is committed beside the objects,
    # because the list the objects were built from used to live only in .agent-work and a regeneration from
    # the repository alone could not reproduce them.
    if arguments.classes_from is None:
        emitted = os.path.join(arguments.out, "clusters-emitted.txt")
        if not os.path.exists(emitted):
            raise SystemExit("no class list: pass --classes-from, or put clusters-emitted.txt in %s" % arguments.out)
        arguments.classes_from = emitted
    if arguments.classes_from:
        with open(arguments.classes_from) as handle:
            arguments.classes = [line.strip() for line in handle if line.strip() and not line.startswith("#")]
    if not arguments.classes and not arguments.self_test:
        parser.error("give --classes or --classes-from")
    if not os.path.isdir(arguments.out):
        os.makedirs(arguments.out)
    for stale in sorted(os.listdir(arguments.out)):
        if stale.endswith(".m"):
            os.remove(os.path.join(arguments.out, stale))
    global NAMED, EMITTED, NAME_ERRORS, PORT_ONLY, PORT_OWNED_CLASS, PARAMS_MISSING, EMITTED_FILES, FORWARDED, CLUSTER_INTERFACES, HEADER_FORWARDS, COMPILE_FAILURES, HEADER_NOT_ALONE, PAYLOAD_INTERFACES, CASES
    NAMED = {}
    EMITTED = []
    CASES = []
    NAME_ERRORS = []
    written = 0
    for cluster in arguments.classes:
        if cluster in EXCLUDED:
            print("skipped %s: %s" % (cluster, EXCLUDED[cluster]))
            continue
        block, supers = cluster_block(lines, cluster)
        if block is None:
            print("no such cluster in the SDK's Matter headers: %s" % cluster)
            continue
        # What the port owes a body for: this SDK's declarations, plus the members the library's SDK's
        # own @interface declares for the class and this one dropped.
        items = cluster_declarations(cluster, block)
        attributes, commands, version, cache_reads, initialisers, cache = facts(items)
        # The CLASS name, verbatim. Stripping a prefix put OTA and Ota, and WakeOnLAN and WakeOnLan, on
        # the same file name, and a volume that folds case would fold them anyway - so a collision on the
        # name as written is detected here and the second one is suffixed, and both are printed.
        stem = "CharonMatter%s" % cluster
        path = os.path.join(arguments.out, stem + ".m")
        if stem.lower() in NAMED:
            # Two emitted names that differ only by CASE are ONE file on a case-insensitive volume, so the
            # second write silently overwrites the first and one cluster is emitted under another's name.
            # That is not renamed around: it is an error, because the fix is a name the volume can hold.
            print("ERROR: %s and %s differ only by case: one file on a case-insensitive volume"
                  % (NAMED[stem.lower()], cluster))
            NAME_ERRORS.append((NAMED[stem.lower()], cluster))
            written -= 1
            continue
        NAMED[stem.lower()] = cluster
        declared_here = cluster_interface(cluster, items, supers)
        if declared_here:
            CLUSTER_INTERFACES.append(declared_here)
        emit(path, cluster, supers, attributes, commands, version, cache_reads, cache, initialisers)
        declared = contract_of(items)
        # The contract is a TEST FIXTURE: it is what the differential holds the port to, and it is not
        # source. Written beside the object it landed in packages/a/apple-backports/Matter/, where it
        # would be swept into the package's sources digest and installed as payload.
        contracts = arguments.contracts or arguments.out
        if not os.path.isdir(contracts):
            os.makedirs(contracts)
        with open(os.path.join(contracts, os.path.basename(path) + ".contract"), "w") as out:
            for name in declared:
                out.write(name + "\n")
        # Through the PARSER, not by slicing: a line is - (void)readAttributeX…, and slicing to the
        # first parenthesis returns the empty string for every one of them, which is how a first attempt
        # at this invariant reported 4,292 members missing. Read as DECLARATIONS for the same reason the
        # header is: the emit writes a method's signature across as many lines as it needs.
        emitted_declarations = list(declarations(open(path), opens_body=True))
        present = [selector_of(signature(text)) for _, text in emitted_declarations]
        if len(present) != len(declared):
            for name in declared:
                if name not in present:
                    LOST.append((cluster, name))
        # The OTHER direction, which this check did not have: a selector the port defines that the
        # contract does not list is one the emit invented. One-sided, it called a file with 700 members
        # nobody asked for correct, and MTRBaseClusterTestCluster came back DIFFERENT on exactly that.
        for first, text in emitted_declarations:
            name = selector_of(signature(text))
            if name in declared or name in PORT_OWNED or name.startswith("."):
                continue
            # A CLASS method is not an instance member: the contract lists the instance methods, which is
            # what the differential compares, and the header's `+` declarations are skipped there on
            # purpose. The seven cached reads the header declares are `+`, and they are 1,873 of the
            # selectors this check would otherwise name - a rule, not 973 lines of allow-list.
            if first.lstrip().startswith("+ ("):
                PORT_OWNED_CLASS.append((cluster, name))
                continue
            PORT_ONLY.append((cluster, name))
        print("wrote %s: %d attributes, %d commands, %d cached reads answered, initialiser %s, release %s"
              % (os.path.basename(path), len(attributes), len(commands), len(cache),
                 len(initialisers), version or "unknown"))
        written += 1
        EMITTED.append(cluster)
    # What was written, as the differential's input. It reads THIS rather than a cluster list kept beside
    # it, which is how the check came to ask for a cluster this run refused to generate.
    if arguments.paths:
        written_paths = emit_paths(arguments, lambda name: "CharonMatter%s" % name)
        print("paths written: %d classes" % written_paths)

    if arguments.params or arguments.params_from:
        if arguments.params_from:
            with open(arguments.params_from) as handle:
                wanted = [line.strip() for line in handle if line.strip()]
        else:
            # Every plain data class the SDK's own headers declare, in the order their superclasses can be
            # declared in. Not a list written here: a cluster that arrives with a payload brings it with no
            # edit to this file, which is the same reason the completion typedefs above are read by walking
            # the Headers directory.
            wanted = plain_data_classes(payload_classes(payload_lines + lines))
            print("plain data classes the SDK's Matter headers declare: %d" % len(wanted))
        # Every Matter header, not only the payload ones: MTRReadParams, MTRWriteParams and the response
        # classes live in MTRCluster.h and the cluster headers, and a run that read only the payload
        # headers reported them as undeclared.
        families = payload_classes(payload_lines + lines)
        global FAMILIES
        FAMILIES = families
        retype_deprecated(families, wanted)
        # What the framework's own source stores in each class's -init, read out of the committed table.
        # The header says nothing about an initial value, and this is the only thing that does.
        INIT_TABLE.update(init_defaults(arguments.init_defaults))
        print("the framework's own -init stores, read out of %s: %d classes, %d members"
              % (os.path.basename(arguments.init_defaults),
                 len([each for each in INIT_TABLE if each in families]),
                 sum(len(each) for each in INIT_TABLE.values())))
        # The deprecated CLASS names, each pair read out of the deprecated class's OWN annotation. It is
        # what says a store naming `MTRUnitTestingClusterSimpleStruct` for a member the SDK declares with
        # the type `MTRTestClusterClusterSimpleStruct *` is the current spelling and not a wrong one.
        pairs = [(each, families[each]["deprecated_for"]) for each in families
                 if families[each].get("deprecated_for")]
        print("  %d of the %d classes the SDK declares carry their own MTR_DEPRECATED(\"Please use X\")"
              " annotation, naming another CLASS: %d of them are in the plain data family"
              % (len(pairs), len(families),
                 len([each for each in pairs if each[0] in set(wanted)])))
        # What the SDK this LIBRARY builds against declares of the same classes, for the two shapes above:
        # the class itself where it declares one, and the properties it gave that class where 26.2 added
        # more. Read from its own headers the same way, not from a list.
        older = {}
        if DECLARED_16:
            older = payload_classes([each for _, block in matter_headers(arguments.sdk16) for each in block])
        # The classes whose header marks -init NS_UNAVAILABLE. Two of 924, and both hand-written in the
        # framework's own source: MTRDeviceControllerFactoryParams and MTRDeviceControllerStartupParams.
        unavailable = init_unavailable_classes(arguments.sdk) & set(wanted)
        print("  %d of the %d plain data classes whose own header marks -init NS_UNAVAILABLE, and so get no"
              " -init here: %s" % (len(unavailable), len(wanted), ", ".join(sorted(unavailable))))
        # Read once for the whole run. It was read inside the per-class loop, which is 924 reads of the same
        # file and grew with the family.
        hosts = host_measurements(arguments.host_measurements)
        missing, properties, emitted, interfaces = [], 0, 0, []
        declared_by_16, extended_by_26, own_by_16 = 0, 0, 0
        contracts = arguments.contracts or arguments.out
        if not os.path.isdir(contracts):
            os.makedirs(contracts)
        for name in wanted:
            info = families.get(name)
            if info is None:
                missing.append(name)
                continue
            stem = "CharonMatter%s" % name
            path = os.path.join(arguments.out, stem + ".m")
            if stem.lower() in NAMED:
                # Two NAMES that differ only in capitalisation are two TYPES - the SDK declares both, and a
                # client can name either - but on a case-insensitive volume they are one FILE. The class is
                # therefore emitted under its own exact name into a file whose name says which of the two
                # capitalisations it holds, and the second file is a real file rather than an overwrite of
                # the first. `_lc` marks the name that writes the acronym in lower case where the one beside
                # it does not; `disambiguate` is the rule, and it applies to every collision, not just this
                # one. The CLUSTERS take the other branch: two cluster classes of one name are the framework
                # declaring a deprecated subclass of itself, and there the right answer is to exclude one.
                other = NAMED[stem.lower()]
                marked = "%s_lc" % stem
                if marked.lower() in NAMED:
                    # A third name for the same path: there is no file left to give it, so it is NOT emitted
                    # and the run FAILS naming it, rather than being silently folded into a neighbour.
                    print("ERROR: %s, %s and %s all want one file on a case-insensitive volume"
                          % (other, name, NAMED[marked.lower()]))
                    PARAMS_MISSING.append(name)
                    continue
                stem = marked
                path = os.path.join(arguments.out, stem + ".m")
                print("  %s and %s differ only by case: %s is written to %s.m, the class keeps its own name"
                      % (other, name, name, stem))
            NAMED[stem.lower()] = name
            declaration = payload_interface(name, info, older)
            if declaration:
                interfaces.append(declaration)
                if name in older:
                    extended_by_26 += 1
                else:
                    declared_by_16 += 1
            own_by_16 += 1 if name in older else 0
            # NSCopying, from the class's own protocol list or from a superclass's: the event classes are
            # the 60 that carry none of their own, and none of them has a superclass that does.
            copying = False
            walk = name
            while walk and walk in families and not copying:
                copying = "NSCopying" in families[walk]["protocols"]
                walk = families[walk]["super"] if walk in families else None
            counts = {"declared": "it" if name in older else "no",
                     "written": ("an extension of" if declaration and name in older
                                 else ("a declaration of" if declaration else "none")),
                     "total": len(wanted)}
            buckets = payload_buckets(name, info, older.get(name, {}))
            if arguments.cases is not None:
                CASES.append((name, buckets))
            properties += emit_params(path, name, info, None, buckets, copying, counts,
                                      hosts.get(name), unavailable=unavailable)
            EMITTED_FILES[name] = os.path.basename(path)
            with open(os.path.join(contracts, stem + ".m.contract"), "w") as out:
                out.write("%s\n" % name)
            EMITTED.append(name)
            emitted += 1
        print("plain data classes written: %d, %d properties; %d named but not declared in the SDK"
              % (emitted, properties, len(missing)))
        if RETYPED:
            print("  %d member(s) this SDK types with a DEPRECATED CLASS, declared with the class that one"
                  " is a spelling of:" % len(RETYPED))
            for where, member, said, current in RETYPED:
                print("    %s.%s: %s -> %s" % (where, member, said, current))
        print("  the SDK this library builds against declares %d of them itself, so those keep the SDK's own"
              " declaration and the port adds only what a later SDK gave them: %d of them as a class"
              " extension. For the other %d the port declares the class, its superclass and every property."
              % (own_by_16, extended_by_26, len(wanted) - own_by_16))
        print("  %d interface(s) added to CharonMatterTypes.h" % len(interfaces))
        if arguments.cases is not None:
            # The probe's driver, written from the buckets this run emits from, so the property list it
            # measures is the port's own and not a list typed beside it.
            with open(arguments.cases, "w") as out:
                for each, (own, categories) in CASES:
                    out.write("%s\town\n" % each)
                    # An alias line only where the deprecation text names a PROPERTY of this class. It often
                    # names a CLASS instead - MTRTestClusterClusterSimpleStruct's members all say "Please use
                    # MTRUnitTestingClusterSimpleStruct", the subclass it is a deprecated alias of - and asking
                    # the probe to write a sentinel through those 11 members is what produced 11 `raised` rows
                    # that were the probe's own artifact and not host behaviour.
                    named = {prop["name"] for prop in own}
                    for props in categories.values():
                        named.update(prop["name"] for prop in props)
                    for prop in own + [q for label in sorted(categories) for q in categories[label]]:
                        if prop.get("successor") and prop["successor"] in named:
                            out.write("%s\t%s\t%s\talias\t%s\n"
                                      % (each, prop["name"], prop["successor"], prop["type"]))
            print("probe driver written: %d class lines" % len(CASES))
        for name in missing[:8]:
            print("  not declared: %s" % name)
        if missing:
            PARAMS_MISSING.extend(missing)
        PAYLOAD_INTERFACES.extend(interfaces)

    if CLUSTER_INTERFACES or PAYLOAD_INTERFACES:
        emit_shared_types(arguments, lambda name: "CharonMatter%s" % name,
                          CLUSTER_INTERFACES, PAYLOAD_INTERFACES)

    # The cluster list, and the plain data list beside it, are committed with the objects so the tree
    # regenerates itself from the repository alone. They are SEPARATE files for the reason they are
    # separate families: one list of both is a list the next run reads back as the cluster list, and 923
    # payload classes then go looking for a cluster block each.
    with open(os.path.join(arguments.out, "clusters-emitted.txt"), "w") as out:
        for each in arguments.classes:
            if each in EMITTED:
                out.write(each + "\n")
    if not arguments.params and not arguments.params_from:
        with open(os.path.join(arguments.out, "clusters-emitted.txt"), "w") as out:
            for each in EMITTED:
                out.write(each + "\n")
    print("clusters written: %d" % written)
    if OFFENDERS:
        shapes = collections.OrderedDict()
        for cluster, member, where, raw in OFFENDERS:
            shapes.setdefault(shape_of(raw), []).append((cluster, member, where, raw))
        print("")
        print("signatures this run could not parse, by shape: %d shapes over %d members"
              % (len(shapes), len(OFFENDERS)))
        for shape, items in shapes.items():
            print("  shape: %s" % shape)
            print("    %d member(s), first: %s.%s (%s)" % (len(items), items[0][0], items[0][1], items[0][2]))
            print("      %s" % items[0][3][:160])
    if LOST:
        print("")
        print("INVARIANT FAILED: %d member(s) the header declares are not in the generated file,"
              " over %d cluster(s):" % (len(LOST), len(set(c for c, _ in LOST))))
        for cluster, name in LOST:
            print("  %s\t%s" % (cluster, name))
    else:
        print("")
        print("invariant: every member the header declares is in the generated file, for every cluster")
    skipped = len([c for c in arguments.classes if c in EXCLUDED])
    if skipped:
        print("skipped by the exclusion list: %d" % skipped)
    # A deliberate exclusion is not a failure; an unparseable signature is.
    if PORT_OWNED_CLASS:
        print("class methods the header declares with `+`, port-only by definition and not in the"
              " instance-method contract: %d over %d cluster(s)"
              % (len(PORT_OWNED_CLASS), len(set(c for c, _ in PORT_OWNED_CLASS))))
    if PORT_ONLY:
        shapes = collections.OrderedDict()
        for cluster, name in PORT_ONLY:
            shapes.setdefault(name, []).append(cluster)
        print("")
        print("INVARIANT FAILED: %d selector(s) the generated file defines that the contract does not"
              " list, over %d cluster(s):" % (len(PORT_ONLY), len(set(c for c, _ in PORT_ONLY))))
        for name in sorted(shapes)[:12]:
            print("  %-58s %d cluster(s), first: %s" % (name[:58], len(shapes[name]), shapes[name][0]))
    if SHARED_STORAGE_REFUSED:
        print("")
        print("deprecated members that do NOT share storage with their successor, and why: %d" % len(
            SHARED_STORAGE_REFUSED))
        for where, said, wanted in SHARED_STORAGE_REFUSED:
            print("  %s.%s: %s" % (where, said, wanted))
    if STORE_SOURCE["own"] or STORE_SOURCE["inherited"] or STORE_SOURCE["none"]:
        print("")
        print("where each plain data class's -init stores come from: %d the framework's own source writes,"
              " %d inherit an ancestor's, %d have none in that tree"
              % (STORE_SOURCE["own"], STORE_SOURCE["inherited"], STORE_SOURCE["none"]))
        if STORE_MOVED:
            print("  %d member(s) the framework's -init stores at something other than the member's type zero,"
                  " and the port writes that:" % len(STORE_MOVED))
            for where, member, said, token in STORE_MOVED:
                print("    %s.%s: %s (%s)" % (where, member, said, token))
        if STORE_KEPT:
            print("  %d member(s) whose store does NOT decide the value, because the two SDKs declare the"
                  " member differently and the port keeps this one's:" % len(STORE_KEPT))
            for where, member, said, expression, why in STORE_KEPT:
                print("    %s.%s: %r at %s, and %s" % (where, member, expression, said, why))
        if STORE_UNREAD:
            print("  STORES THIS RUN CANNOT READ, and the port keeps the derived value for them: %d"
                  % len(STORE_UNREAD))
            for where, member, expression, said in STORE_UNREAD:
                print("    %s.%s: %r at %s" % (where, member, expression, said))
        if STORE_CLASSES:
            print("  CLASS NAMES THE FRAMEWORK'S SOURCE AND THIS SDK DISAGREE ON: %d" % len(STORE_CLASSES))
            for where, member, given, said, why in STORE_CLASSES:
                print("    %s.%s: the source gives it %s at %s, and %s" % (where, member, given, said, why))
    if NAME_ERRORS:
        print("")
        print("EMITTED FILE NAME ERRORS: %d pair(s) that differ only by case" % len(NAME_ERRORS))
        for first, second in NAME_ERRORS:
            print("  %s and %s" % (first, second))
    if arguments.shared_types:
        if check_header_stands_alone(os.path.join(arguments.out, "CharonMatterTypes.h"), arguments.sdk16):
            print("CharonMatterTypes.h does not stand alone: it is imported by every object, and a header"
                  " that does not compile by itself is a defect the objects were hiding")
            HEADER_NOT_ALONE.append("CharonMatterTypes.h")

    failed = compile_objects(arguments.out, arguments.sdk16)
    if failed:
        print("OBJECTS THAT DO NOT COMPILE against the SDK the library builds with: %d" % len(failed))
        for name in failed[:10]:
            print("  %s" % name)
        COMPILE_FAILURES.extend(failed)
    else:
        print("every object compiles against the SDK the library builds with: %d" % len(
            [name for name in os.listdir(arguments.out) if name.endswith(".m")]))

    # Every object names the class it implements, and the count is printed: the registry dates that
    # class and the band holds it, so an object that cannot name one is an API nothing can place. It
    # read silently for a whole series - the shared base class MTRGenericBaseCluster is written here and
    # not from the cluster loop, so it was in no emitted list, and the gate answered "neither the SDK
    # nor the registry says which iOS release MTRGenericBaseCluster arrived in".
    emitted = sorted(name for name in os.listdir(arguments.out) if name.endswith(".m"))
    unnamed = [name for name in emitted if implemented_class(os.path.join(arguments.out, name)) is None]
    if unnamed:
        print("")
        print("OBJECTS THAT DO NOT NAME THE CLASS THEY IMPLEMENT: %d" % len(unnamed))
        for name in unnamed[:10]:
            print("  %s" % name)
    else:
        print("every object names the class it implements: %d of %d" % (len(emitted), len(emitted)))

    everything_clear = not (OFFENDERS or LOST or PORT_ONLY or NAME_ERRORS or PARAMS_MISSING
                            or COMPILE_FAILURES or HEADER_NOT_ALONE or unnamed or STORE_CLASSES)
    return 0 if everything_clear else 1


if __name__ == "__main__":
    sys.exit(main())
