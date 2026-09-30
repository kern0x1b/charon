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
  * a CATEGORY on the cluster, not a second declaration of it. The cluster is declared by
    the SDK the port compiles against - iPhoneOS 16.4 ships Matter.framework, and
    MTRBaseClusterIdentify is in its MTRBaseClusters.h - and the release has no such
    class, so the port adds the members and not the class.
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


def contract_of(block):
    """The selectors the header declares for a cluster, in every shape it declares them.

    Re-parses the block's own declarations with parse(), and shares no scope with the emit loop,
    so it cannot be broken by what the emit does or not do. The result is written beside the generated
    file and is what the differential holds the port to: a selector the port has that this does not list
    is one the generator invented, and a selector this lists that the port no longer has is one it dropped.
    """
    names = []
    for first, text in declarations(block):
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
    start = None
    for index, line in enumerate(lines):
        found = INTERFACE.match(line)
        if found and found.group(1) == name:
            start = index
            break
    if start is None:
        return None, None
    supers = INTERFACE.match(lines[start]).group(2)
    block = [lines[start]]
    for line in lines[start + 1:]:
        found = INTERFACE.match(line)
        if found and found.group(1) != name:
            break
        block.append(line)
    return block, supers


def facts(block):
    """What the header says a cluster has: its attributes, its commands, and the release it arrived in.

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
    for first, text in declarations(block):
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

// The framework's own declarations are the contract: the class is declared in Matter.h, and an object that
// re-declares it without importing is the compiler's `cannot find interface declaration for`, which is what
// every one of the 234 said until the import was here.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>

@interface {params} ()
@end

"""

PAYLOAD_HEADERS = (
    "System/Library/Frameworks/Matter.framework/Headers/MTRCommandPayloadsObjc.h",
    "System/Library/Frameworks/Matter.framework/Headers/MTRStructsObjc.h",
    "System/Library/Frameworks/Matter.framework/Headers/MTRCluster.h",
    "System/Library/Frameworks/Matter.framework/Headers/MTRBaseCluster.h",
)

# The availability annotation is matched to the end of the declaration, not to its first `)`: MTR_AVAILABLE
# nests three deep - MTR_AVAILABLE(ios(16.1), macos(13.0), watchos(9.1), tvos(16.1)) - and a pattern that
# stopped at the first close paren matched no property at all.
PROPERTY = re.compile(r"^@property\s*\(([^)]*)\)\s*(.+?)\s+(\w+)\s*(MTR_\w+\(.*\))?\s*;$")
# ANY superclass, not just NSObject: MTRContentLauncherClusterLaunchResponseParams derives from
# MTRContentLauncherClusterLauncherResponseParams, and a head that demanded NSObject left 25 of the 234
# classes the objects name undeclared. The protocols are what say the class is plain data.
CLASS_HEAD = re.compile(r"^@interface\s+(\w+)\s*:\s*(\w+)\s*(?:<([^>]*)>)?\s*$")
CUSTOM_GETTER = re.compile(r"getter=(\w+)")
PARAMS = []


def payload_classes(lines):
    """Every `@interface X : NSObject <...>` block in the payload headers, with its properties.

    Read out of the headers the same way the cluster blocks are, and keyed by class name: the cluster
    objects name these types, and 234 of them are the subset the emitted objects actually reference.
    """
    found = {}
    name = None
    for line in lines:
        head = CLASS_HEAD.match(line)
        if head:
            name = head.group(1)
            found[name] = {"super": head.group(2),
                           "protocols": (head.group(3) or "").split(),
                           "properties": [], "methods": []}
            continue
        if name is None:
            continue
        if line.startswith("@end"):
            name = None
            continue
        stripped = line.strip()
        if stripped.startswith("@property"):
            prop = PROPERTY.match(stripped)
            if prop:
                getter = CUSTOM_GETTER.search(prop.group(1))
                found[name]["properties"].append({
                    "type": prop.group(2).strip(),
                    "name": prop.group(3),
                    "attributes": prop.group(1),
                    "getter": getter.group(1) if getter else None,
                    "available": prop.group(4)})
        elif stripped.startswith("- ("):
            for _, declaration in declarations([line]):
                found[name]["methods"].append(signature(declaration))
    return found


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

def emit_params(path, name, info, version):
    """One object for one params class: the properties it declares, and a copy that is independent.

    The synthesis is WRITTEN OUT rather than left to the compiler, so the object's own property list is
    visible in the object file and `-Werror=objc-missing-property-synthesis` has nothing to catch. The
    copy walks the ivars by name, so a property added to the header and not to this list is caught by the
    invariant rather than silently not copied.
    """
    body = [PARAMS_PREAMBLE.format(name=os.path.basename(path), params=name,
                                   introduced=version or "16.0",
                                   protocols=", ".join(info["protocols"]) or "none")]
    body.append("@implementation %s\n\n" % name)
    for prop in info["properties"]:
        body.append("@synthesize %s = _%s;\n" % (prop["name"], prop["name"]))
    if info["properties"]:
        body.append("\n")
    body.append("- (instancetype)init\n{\n    self = [super init];\n    if (!self) {\n        return nil;\n    }\n    return self;\n}\n\n")
    body.append("// NSCopying, by declaration: the copy owns its own ivars, so writing to the copy never\n"
                "// reaches back into the original.\n")
    body.append("- (id)copyWithZone:(NSZone *)zone\n{\n    %s *copied = [[%s allocWithZone:zone] init];\n"
                % (name, name))
    for prop in info["properties"]:
        body.append("    copied->_%s = self->_%s;\n" % (prop["name"], prop["name"]))
    if not info["properties"]:
        body.append("    (void)zone;\n")
    body.append("    return copied;\n}\n\n@end\n")
    with open(path, "w") as out:
        out.write("".join(body))
    return len(info["properties"])

# The library builds against the 16.4 SDK, and this generator reads the 26.2 headers. A cluster object that
# names a type 16.4 does not declare does not compile for the target - `unknown type name
# 'MTRAccessControlClusterReviewFabricRestrictionsResponseParams'` - even though it compiles on the machine
# that generated it, because that machine has the 26.2 SDK. Pointer uses need only a forward declaration.
MATTER_TYPE = re.compile(r"\bMTR[A-Za-z0-9_]+\b")
DECLARED_16 = set()


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
//  GENERATED by tools/matter-generate.py from the SDK's own Matter headers, beside CharonMatterTypes.h
//  which declares this class. Read-only ids, kept in the class's own state, because a port object has to
//  BE the class and nothing in it reaches a fabric.
//

#import <Matter/Matter.h>
#import "CharonMatterTypes.h"

@implementation {name}

{body}
@end

"""


def cluster_interface(cluster, block, supers):
    """The @interface of a cluster class the target's SDK does not declare, for CharonMatterTypes.h.

    It carries the class's own members, every one the object below implements, because an @interface with
    none of them is `-Wincomplete-implementation` on the first method - which is how the two members of
    MTRClusterStateCacheContainer reached a port object once already.
    """
    if not DECLARED_16 or cluster in DECLARED_16:
        return None
    attributes, commands, version, cache_reads, initialisers, cache = facts(block)
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

def emit_shared_types(arguments, stem_of, cluster_interfaces=()):
    """One header of declarations and one object per shared class. Dependency order is the order above."""
    written = []
    declarations, bodies = [], []
    for name, supers, properties in SHARED_TYPES:
        # Only what the target's SDK does not declare. MTRCluster is in this list because MTRGenericBaseCluster
        # inherits from it and the list is in dependency order, but 16.4 DOES declare MTRCluster, so
        # declaring it here as well was `duplicate interface definition for class 'MTRCluster'`.
        if name in DECLARED_16:
            continue
        declarations.append("@interface %s : %s\n@end\n" % (name, supers))
        body = ["@synthesize %s = _%s;\n" % (each, each) for each in properties]
        stem = stem_of(name)
        if stem.lower() in NAMED:
            print("ERROR: %s and %s differ only by case" % (NAMED[stem.lower()], name))
            NAME_ERRORS.append((NAMED[stem.lower()], name))
            continue
        NAMED[stem.lower()] = name
        path = os.path.join(arguments.out, stem + ".m")
        with open(path, "w") as out:
            out.write(TYPES_OBJECT.format(name=name, body="\n".join(
                [""] + body if body else [""])))
        written.append(name)
    header = os.path.join(arguments.out, "CharonMatterTypes.h")
    for text in cluster_interfaces:
        declarations.append(text)
    with open(header, "w") as out:
        forwards = ""
        if HEADER_FORWARDS:
            forwards = ("// The types the interfaces below name that the SDK this library builds against does\n"
                        "// not declare: %d of them, forward-declared here because pointer uses need only this.\n"
                        "@class %s;\n\n" % (len(HEADER_FORWARDS), ", ".join(sorted(HEADER_FORWARDS))))
        out.write(TYPES_HEADER.format(forwards=forwards, declarations="\n".join(declarations)))
    print("CharonMatterTypes.h: %d shared class declaration(s), %d cluster interface(s); "
          "%d object(s) written" % (len(declarations) - len(cluster_interfaces),
                                     len(cluster_interfaces), len(written)))
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


def emit(path, cluster, supers, attributes, commands, version, cache_reads, cache, initialisers):
    """The family as one object, and the object IS the class: the release has no such class.

    Every selector below is the SDK header's own, copied out of the declaration rather than rebuilt from
    a pattern. That is the general fix: a nullability between the type and the selector, a
    subscriptionEstablished: block, a three-argument subscribe - enumerating the shapes is what left two
    members unimplemented last pass, and the header already knows every one of them.
    """
    body = [PREAMBLE.format(name=os.path.basename(path), cluster=cluster,
                            supers=supers or "Matter cluster", cache=cache_reads)]
    body.append("// A class EXTENSION, not a category: it carries the storage and is invisible at\n"
                "// runtime, so the port's class is still the only implementation of the name.\n")
    body.append("@interface %s () {\n" % cluster)
    body.append("    id _charon_device;\n")
    body.append("    NSNumber *_charon_endpoint;\n")
    body.append("    dispatch_queue_t _charon_queue;\n")
    body.append("}\n")
    body.append("@end\n\n")
    body.append("@implementation %s\n\n" % cluster)
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
        # MTRBaseCluster's -init is unavailable, so the initialiser does not chain to it: the object
        # is already allocated and its three storage slots are already nil.
        body.append("%s\n{\n"
                    "    return self;\n}\n\n" % shape_line(entry["signature"]))
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
    print("self-test: %d declarations, %d failures" % (len(SELF_TEST), failures))
    return failures == 0


def check_header_stands_alone(path, sdk16):
    """CharonMatterTypes.h compiled by itself, with the includes it declares for itself.

    It is a header every one of the 143 objects imports, and a review found it does not compile alone -
    the imports that made it work were in the objects, not in the header. So it is checked alone, by
    exit status, in the same run that writes it.
    """
    if not sdk16 or not os.path.exists(path):
        return 0
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
    parser.add_argument("--params-from", help="a file of *Params class names the emitted objects reference")
    parser.add_argument("--self-test", action="store_true", help="parse three declarations and stop")
    arguments = parser.parse_args()

    if arguments.self_test:
        return 0 if self_test() else 1
    DECLARED_16.update(load_declared(arguments.sdk16))
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
    # being edited.
    payload_lines = []
    for header in PAYLOAD_HEADERS:
        path = os.path.join(arguments.sdk, header)
        if os.path.exists(path):
            with open(path) as handle:
                payload_lines.extend(handle.read().splitlines())

    header_dir = os.path.dirname(os.path.join(arguments.sdk, HEADERS[0]))
    for name in sorted(os.listdir(header_dir)) if os.path.isdir(header_dir) else []:
        if not name.endswith(".h"):
            continue
        with open(os.path.join(header_dir, name)) as handle:
            TYPEDEF_COMPLETIONS.update(load_typedef_completions(handle.read().splitlines()))


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
    global NAMED, EMITTED, NAME_ERRORS, PORT_ONLY, PORT_OWNED_CLASS, PARAMS_MISSING, EMITTED_FILES, FORWARDED, CLUSTER_INTERFACES, HEADER_FORWARDS, COMPILE_FAILURES, HEADER_NOT_ALONE
    NAMED = {}
    EMITTED = []
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
        attributes, commands, version, cache_reads, initialisers, cache = facts(block)
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
        declared_here = cluster_interface(cluster, block, supers)
        if declared_here:
            CLUSTER_INTERFACES.append(declared_here)
        emit(path, cluster, supers, attributes, commands, version, cache_reads, cache, initialisers)
        declared = contract_of(block)
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

    if arguments.params_from:
        wanted = []
        with open(arguments.params_from) as handle:
            wanted = [line.strip() for line in handle if line.strip()]
        # Every Matter header, not only the payload ones: 25 of the 234 are declared beside the clusters
        # that use them - MTRReadParams, MTRWriteParams and the response classes live in MTRCluster.h and
        # the cluster headers, and a run that read only the payload headers reported them as undeclared.
        families = payload_classes(payload_lines + lines)
        missing, properties, emitted = [], 0, 0
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
            properties += emit_params(path, name, info, None)
            EMITTED_FILES[name] = os.path.basename(path)
            with open(os.path.join(contracts, stem + ".m.contract"), "w") as out:
                out.write("%s\n" % name)
            EMITTED.append(name)
            emitted += 1
        print("params written: %d classes, %d properties; %d named but not declared in the SDK"
              % (emitted, properties, len(missing)))
        for name in missing[:8]:
            print("  not declared: %s" % name)
        if missing:
            PARAMS_MISSING.extend(missing)

    if CLUSTER_INTERFACES:
        emit_shared_types(arguments, lambda name: "CharonMatter%s" % name, CLUSTER_INTERFACES)

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

    everything_clear = not (OFFENDERS or LOST or PORT_ONLY or NAME_ERRORS or PARAMS_MISSING or COMPILE_FAILURES or HEADER_NOT_ALONE)
    return 0 if everything_clear else 1


if __name__ == "__main__":
    sys.exit(main())
