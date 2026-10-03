import os
import re, glob, json, os, subprocess

ORDER = ["VTFrameProcessor", "VTFrameProcessorFrame", "VTFrameProcessorOpticalFlow",
         "VTFrameRateConversionConfiguration", "VTFrameRateConversionParameters",
         "VTLowLatencyFrameInterpolationConfiguration", "VTLowLatencyFrameInterpolationParameters",
         "VTLowLatencySuperResolutionScalerConfiguration", "VTLowLatencySuperResolutionScalerParameters",
         "VTMotionBlurConfiguration", "VTMotionBlurParameters", "VTOpticalFlowConfiguration",
         "VTOpticalFlowParameters", "VTSuperResolutionScalerConfiguration",
         "VTSuperResolutionScalerParameters", "VTTemporalNoiseFilterConfiguration",
         "VTTemporalNoiseFilterParameters"]
STRUCTS = {"CMTime", "CMVideoDimensions"}

# IS THIS TYPE A CF REFERENCE? Asked of the SDK's own headers, never of a list of names. A previous
# version answered it with CF_TYPES = {"CVPixelBufferRef"} and that is the same mistake in a different
# costume: a name someone remembered instead of a rule the SDK states.
#
# TWO WAYS THE SDK SAYS SO, and both are read here:
#
#   CF_BRIDGED_TYPE(name) / CF_BRIDGED_MUTABLE_TYPE(name)   - the annotation
#   a typedef chain that ends at a pointer to a struct whose name begins with __   - the form
#
# CVPixelBufferRef is the second kind, and the chain crosses FRAMEWORKS, which is why a resolver reading
# only VideoToolbox's headers cannot answer it:
#
#   CoreVideo:   typedef CVImageBufferRef CVPixelBufferRef CV_SWIFT_NONSENDABLE;
#   CoreVideo:   typedef CVBufferRef CVImageBufferRef;
#   CoreFoundation: typedef const struct __CVBuffer *CVBufferRef;
#
# A class type is `VTFrameProcessorFrame *` - a pointer, and NOT CF, because its pointee is not a
# `struct __…`. OSType is not CF at all: it resolves to an integer.
# A TYPE'S CANONICAL FORM, ASKED OF THE COMPILER. Three regular expressions tried to answer this from the
# header text and all three were wrong: a non-greedy base made the name 'id', a greedy base made it the
# trailing attribute, and a global CF_BRIDGED_TYPE name list answered NSArray as CF. The compiler already
# knows, so it is asked, and the 979-entry table it replaces is gone.
#
# The probe is one translation unit with one typedef per type, run with -ast-dump=json filtered to them,
# and the answer read from the TypedefDecl's desugaredQualType. The 26 of this family's:
#
#   CVPixelBufferRef                                      ->  struct __CVBuffer *
#   CMTime                                                ->  CMTime
#   NSArray<NSNumber *> *                                 ->  NSArray<NSNumber *> *
#   OSType                                                ->  unsigned int
#   VTMotionBlurConfigurationRevision                      ->  enum VTMotionBlurConfigurationRevision
#
# and the branches follow from what THAT says, not from what a name looks like.
SCALAR_CANONICAL = {"long", "long long", "unsigned int", "unsigned char", "unsigned long", "int",
                    "bool", "float", "double", "short", "char", "long double"}


def probe_types(sdk, types, workdir):
    """The canonical type of each, by asking clang. Returns {type: desugaredQualType}."""
    if not os.path.isdir(workdir):
        os.makedirs(workdir)
    source = os.path.join(workdir, "type-probe.m")
    lines = ["#import <VideoToolbox/VideoToolbox.h>", "#import <CoreMedia/CoreMedia.h>",
             "#import <CoreVideo/CoreVideo.h>", "#import <CoreFoundation/CoreFoundation.h>", ""]
    for index, type_name in enumerate(types):
        lines.append("typedef %s charon_probe_%d;" % (type_name, index))
    open(source, "w").write("\n".join(lines) + "\n")
    command = ["xcrun", "clang", "-fsyntax-only", "-isysroot", sdk,
               "-F", os.path.join(sdk, "System/Library/Frameworks"),
               "-isystem", os.path.join(sdk, "usr/include"),
               "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter=charon_probe_", source]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("the type probe did not compile:\n%s" % result.stderr[:2000])
    # the filtered dump is SEVERAL concatenated JSON documents, not one - raw_decode reads them in turn
    decoder, rest, found = json.JSONDecoder(), result.stdout, {}

    def walk(node):
        if isinstance(node, dict):
            if node.get("kind") == "TypedefDecl" and str(node.get("name", "")).startswith("charon_probe_"):
                declared = node.get("type") or {}
                found[node["name"]] = declared.get("desugaredQualType") or declared.get("qualType")
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    index = 0
    while index < len(rest):
        while index < len(rest) and rest[index] in " \t\r\n":
            index += 1
        if index >= len(rest):
            break
        document, index = decoder.raw_decode(rest, index)
        walk(document)
    return {types[int(name[len("charon_probe_"):])]: canonical
            for name, canonical in found.items() if name[len("charon_probe_"):].isdigit()}


# WHAT __builtin_classify_type PRINTS ON THIS TOOLCHAIN, and it is NOT the documented table: 1 integer,
# 4 boolean, 5 pointer, 8 real, 12 record, and -1 for every Objective-C object pointer - which is not a
# documented class at all. So the object branch has a SECOND, independent witness: @encode(T) begins with
# "@" exactly for an Objective-C object type, and on all twenty-six types the two agree.
#
# A class that is in neither the map nor the object case returns None, and the WALK FAILS on it. That is
# the property that matters: an unknown answer is a failure, not a default.
CLASS_BRANCH = {12: "struct", 5: "CF", 1: "scalar", 2: "scalar", 3: "scalar", 4: "scalar",
                6: "scalar", 7: "scalar", 8: "scalar"}


def branch_of(class_number, objc_pointer):
    """The branch, from the two signals. None when the class is one this toolchain has not shown."""
    if objc_pointer or class_number == -1:
        return "object"
    return CLASS_BRANCH.get(class_number)


BRANCH_TABLE = {}


def load_branch_table(path=None):
    """type -> (class, @encode) from the probe's output. Read from a FILE so the codes are what the
    compiler printed on this machine, not a list someone typed."""
    if path is None:
        # Beside this file, and TRACKED. It used to be read from .agent-work, which is excluded from the
        # repository, so the generator could not run in a fresh tree - a fresh git am of the series has
        # never produced it and never would. It is derived from the SDK by probe-types.py, which is in
        # the tree, and a regeneration that disagrees is a diff someone can see.
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "type-branches.tsv")
    if not os.path.exists(path):
        raise SystemExit("the type probe has not been run: %s is missing" % path)
    table = {}
    for line in open(path):
        if line.strip():
            fields = line.rstrip("\n").split("\t")
            if len(fields) == 3:
                table[fields[0]] = (int(fields[1]), fields[2] == "objc")
    return table


def store_branch(type_name):
    """The branch a value of this type takes, from the compiler's two signals.

    A type the probe has not classified, or a class the map does not know, is an ERROR here rather than a
    default - a value that reached the store line unclassified is what produced a boxed CFTypeRef, a
    boxed struct and a boxed object, one compile at a time.
    """
    if not BRANCH_TABLE:
        BRANCH_TABLE.update(load_branch_table())
    bare = re.sub(r'\s*_(?:Nullable|Nonnull|null_unspecified)\b|\s*__nonnull\b', '', type_name).strip()
    # A PROPERTY spells an object type without its star (the star is the obj flag) and an INITIALISER
    # spells it with one, so both are looked up - the probe has one row per spelling the SDK uses.
    if bare not in BRANCH_TABLE and (bare + " *") in BRANCH_TABLE:
        bare = bare + " *"
    if bare not in BRANCH_TABLE:
        raise SystemExit("%s: the type probe has no row for it - run the probe before generating" % bare)
    branch = branch_of(*BRANCH_TABLE[bare])
    if branch is None:
        raise SystemExit("%s: the compiler classified it as %d, which is a class this toolchain has not "
                         "shown - a NEW branch, not a default" % (bare, BRANCH_TABLE[bare][0]))
    return branch



PROTO_NAMES = ("VTFrameProcessorConfiguration", "VTFrameProcessorParameters")


def strip(decl):
    while True:
        # The parenthesised list is consumed whole, parens included: API_DEPRECATED_WITH_REPLACEMENT
        # ("isSupported", macos(15.4, 26.0)) has a ')' inside it, and stopping at the first one left a
        # trailing ')' on the declaration, which then matched nothing - so the property vanished from the
        # parse instead of being excluded for the reason it is excluded.
        m = re.search(r'\s*(?:API_[A-Z_]+|NS_REFINED_FOR_SWIFT|NS_SWIFT_NAME|NS_SWIFT_UNAVAILABLE'
                      r'|NS_SWIFT_SENDABLE|API_DEPRECATED_WITH_REPLACEMENT)'
                      r'\s*(\((?:[^()]|\([^()]*\))*\))?', decl)
        if not m:
            break
        decl = decl[:m.start()] + decl[m.end():]
    return ' '.join(decl.split()).rstrip(',').strip()


def props_of(text):
    out = {}
    for attrs, decl in re.findall(r'@property\s*\(([^)]*)\)([^;]*);', text, re.S):
        # The pointer belongs to the TYPE, so it is captured rather than absorbed. The SDK writes both
        # `NSIndexSet* supportedRevisions` and `NSArray<NSNumber *> * frameSupportedPixelFormats`, and a
        # pattern that lets \*? eat the star loses the one thing that says the value is an object: every
        # such property is then generated as a by-value return of an interface type, which the compiler
        # rejects ("interface type cannot be statically allocated"). test-gen-body.py covers both
        # spellings, because that is what this cost a run of the series to find.
        pm = re.match(r'^(.*?)\s*(\*?)\s*(\w+)$', strip(decl))
        if not pm:
            continue
        g = re.search(r'getter=(\w+)', attrs)
        out[pm.group(3)] = {"type": pm.group(1).strip(), "obj": pm.group(2) == '*',
                            "class": 'class' in attrs, "getter": g.group(1) if g else None,
                            "unavailable_ios": 'API_UNAVAILABLE(ios)' in decl}
    return out


def parse(alltext):
    protocols = {}
    for p in PROTO_NAMES:
        m = re.search(r'@protocol\s+%s\s*(?:<[^>]*>)?(.*?)@end' % p, alltext, re.S)
        # A protocol this tool reads that the SDK does not declare is a FINDING, not a reason to fall
        # over: the whole point of the comparison is that the port answers what the SDK declares, so a
        # name that has gone from the headers has to be said out loud and by name. It used to be
        # `m.group(1)` on a None, which is `AttributeError: 'NoneType' object has no attribute 'group'`
        # with the protocol nowhere in it - and a traceback is not a line the host sweep can read, so
        # the sweep called this DEAD, which reads as "nobody has run this lately".
        if m is None:
            raise SystemExit("FAIL: the SDK headers declare no @protocol %s, so there is nothing to "
                             "compare the port's %s against; the name is gone from VideoToolbox and the "
                             "ledger needs a row saying so" % (p, p))
        protocols[p] = props_of(m.group(1))
    classes = {}
    for c in ORDER:
        blocks = re.findall(r'@interface\s+%s\b\s*(?:\([^)]*\))?\s*(?::\s*\w+\s*(?:<([^>]*)>)?)?(.*?)@end'
                            % c, alltext, re.S)
        protos, own = set(), {}
        for angle, body in blocks:
            if angle:
                protos |= {x.strip() for x in angle.split(',') if x.strip()}
            own.update(props_of(body))
        pnames = {}
        for pr in protos:
            pnames.update(protocols.get(pr, {}))
        # A property the SDK marks API_UNAVAILABLE(ios) does not exist on iOS, so the port does not carry
        # it - by that measured reason, recorded per class rather than left to whatever the parser did with
        # it. The ledger has a row for each and the registry carries them as absent with this reason.
        unavailable = sorted(k for k, v in own.items() if v.get('unavailable_ios'))
        own = {k: v for k, v in own.items() if k not in unavailable}
        # A protocol property re-declared with DIFFERENT class-ness is not redundant: the class's own
        # declaration is the one an app is compiled against, and it is what the accessor must be.
        kept = {k: v for k, v in own.items() if k not in pnames or pnames[k]['class'] != v['class']}
        classes[c] = {"sup": 'NSObject', "protocols": sorted(protos), "own": kept,
                      "redeclared": sorted(k for k in kept if k in pnames),
                      "unavailable_ios": unavailable}
    return protocols, classes



# The initialisers, from the same headers, keyed on the FULL selector. Keying on a prefix would collapse
# the two VTLowLatencySuperResolutionScale... no: the two VTLowLatencyFrameInterpolationConfiguration
# initialisers, which differ only in their last keyword (numberOfInterpolatedFrames, spatialScaleFactor)
# and share the first two. One body per selector, never one per prefix.
def initialisers(alltext, classname):
    out = []
    for m in re.finditer(r'@interface\s+%s\b(.*?)@end' % classname, alltext, re.S):
        body = m.group(1)
        for _sign, returns, decl in re.findall(r'([-+])\s*\(([^)]*)\)([^;]*);', body, re.S):
            if 'NS_UNAVAILABLE' in decl:
                continue
            cleaned = strip(decl)
            # THREE things per piece: the selector's keyword (Buffer), the type (CVPixelBufferRef) and
            # the ARGUMENT'S OWN NAME (buffer). The property is named after the argument, not after the
            # selector piece, and taking the piece gives "Buffer" - a name no property has. The SDK
            # writes initWithBuffer:(CVPixelBufferRef)buffer, and the lowercase word is the property.
            parts = re.findall(r'(\w+):\s*\(([^)]*)\)\s*(\w+)', cleaned)
            if not parts or not parts[0][0].startswith('init'):
                continue
            # The first selector piece is initWithBuffer:, not buffer: - the method's own name and its
            # first keyword are one word, and reading that word as a keyword is how the assert below
            # fired on the very first class. The keyword is what follows "init".
            selector = ''.join(word + ':' for word, _type, _arg in parts)
            # FOUR fields per argument, not two: the SELECTOR PIECE and the ARGUMENT NAME are not always
            # the same word, and SDK 26.2 has one where they differ -
            #   destinationFrames:(NSArray<VTFrameProcessorFrame *> *)destinationFrame
            # in VTFrameProcessor_FrameRateConversion.h:166-171. The piece is the API contract and goes
            # into the selector; the name is what the value is called and is what the store keys. Taking
            # the name for both is right everywhere else and wrong exactly there, and it produced a
            # declaration of a selector the SDK does not have.
            arguments = [(arg, type_name.strip(), word) for word, type_name, arg in parts]
            out.append((selector, arguments, returns.strip()))
    return out


def init_signature(selector, arguments, returns):
    """The declaration, in the SDK's own spelling: one keyword per argument, the type each one carries."""
    if not arguments:
        return '- (nullable instancetype)%s;' % selector
    # the declaration is written with the SDK's own first piece, so the spelling is the SDK's
    first_word = arguments[0][2]
    lines = ['- (nullable instancetype)%s:(%s)%s' % (first_word, arguments[0][1], arguments[0][0])]
    pad = ' ' * (len('- (nullable instancetype)') - 1)
    for keyword, type_name, piece in arguments[1:]:
        # the SELECTOR PIECE, with the ARGUMENT NAME as the parameter: a caller writes destinationFrames:
        # and passes a value the port stores under the name the SDK gave that value
        lines.append('%s%s:(%s)%s' % (pad, piece, type_name, keyword))
    return '\n'.join(lines) + ';'


# The initialisers whose argument name is not the property's own name. The SDK spells the argument
# usePrecomputedFlow and the property precomputedFlow, and a value stored under the argument's name
# would sit in the store where no accessor and no property walk would ever look for it.
# WHERE THE SDK SPELLS ONE CONCEPT THREE WAYS, and no rule bridges it. Quoted, class-scoped, and argued
# from the header rather than normalised:
#
#   VTFrameProcessor_SuperResolutionScaler.h:130
#     @property (nonatomic, readonly, getter=usesPrecomputedFlow) BOOL precomputedFlow;
#     its initialiser's argument is  usePrecomputedFlow
#
# so the ARGUMENT is usePrecomputedFlow, the PROPERTY is precomputedFlow and the GETTER is
# usesPrecomputedFlow - and the argument matches neither of the other two. Case does not help: they differ
# by an "s". This entry is CLASS-SCOPED, and that is the whole point: in the other two classes the argument
# IS the property name -
#
#   VTFrameProcessor_MotionBlur.h:96            @property (nonatomic, readonly) BOOL usePrecomputedFlow;
#   VTFrameProcessor_FrameRateConversion.h:103   @property (nonatomic, readonly) BOOL usePrecomputedFlow;
#
# which is exactly what the global map this replaced got wrong, moving two classes' values under a key
# their accessors do not read.
#
# What the table replaced: a GLOBAL rename map, {"usePrecomputedFlow": "precomputedFlow"}, which was dead
# on arrival for those two classes - the review found VTFrameRateConversionConfiguration storing under
# "precomputedFlow" while its accessor reads "usePrecomputedFlow", so -usePrecomputedFlow answered NO for
# both inputs. A global map cannot be right when the SDK differs by class, which it does.
DECLARED_KEYS = {
    ("VTSuperResolutionScalerConfiguration", "usePrecomputedFlow"):
        ("precomputedFlow", "usesPrecomputedFlow", "VTFrameProcessor_SuperResolutionScaler.h:130"),
    # A THIRD SPELLING MISMATCH, and the read-back's own parser found it on its first run - the review
    # that found the first one had not looked at this class:
    #
    #   VTFrameProcessor_FrameRateConversion.h:171
    #     destinationFrames:(NSArray<VTFrameProcessorFrame *> *)destinationFrame NS_REFINED_FOR_SWIFT;
    #   VTFrameProcessor_FrameRateConversion.h:198
    #     @property(nonatomic, readonly) NSArray<VTFrameProcessorFrame *> * destinationFrames;
    #
    # the ARGUMENT is destinationFrame and the PROPERTY is destinationFrames. The accessor reads the
    # property, so storing under the argument's own name is a THIRD dead store, identical in kind to the
    # first one, and invisible to the differential because the store and the expectation were derived from
    # the same code and could not disagree.
    ("VTFrameRateConversionParameters", "destinationFrame"):
        ("destinationFrames", None, "VTFrameProcessor_FrameRateConversion.h:198"),
}

# A parameter the SDK declares NO PROPERTY for: VTTemporalNoiseFilterConfiguration's initialiser takes
# sourcePixelFormat and the class exposes only supportedSourcePixelFormats, the list it accepts.
#
# MEASURED ON THE HOST, and the measurement changed the answer. class_copyIvarList on the host's own
# VTTemporalNoiseFilterConfiguration returns ten ivars and the first is _sourcePixelFormat, so KVC on the
# host does NOT refuse that key: NSObject's default implementation finds the ivar, strips the leading
# underscore and reads it. The port keeps the value in an IVAR of that same name - the host's own
# mechanism - and not in the keyed store under a private key, which would have made the port refuse a key
# the host answers.
#
# An ivar and not a store entry for a second reason: the value walk reads the store keyed by property
# names, and the SDK declares no property here, so a store entry under any name is a value no walk and no
# accessor would ever name - a second spelling of a value nothing reads.
PRIVATE_KEYS = {"sourcePixelFormat"}


def is_private_key(class_name, keyword):
    """Whether this argument's value is kept in an IVAR rather than the keyed store.

    FIVE SITES USED TO ASK THIS, in two files, and the fourth one decided RETENTION from it. That is
    the same failure this series has now produced three times - a rule in two spellings, or in five:
    ivars_for deciding the ivar, store_key deciding the key, init_body deciding the ivar, init_body
    deciding whether to CFRetain, and the mutants loop choosing the branch. They agreed because they
    read one set, and they would not have had to if any one of them changed. One predicate, and the
    class name is a parameter so the answer can be scoped per class when the SDK needs it to be.
    """
    return keyword in PRIVATE_KEYS


def ivars_for(arguments, properties=None, selector=None, class_name=None):
    """The ivar declarations an implementation needs: the parameters the SDK declares no property for.

    An ivar cannot be added to class from outside its own @implementation, so the block belongs to the
    generated implementation and NOT to the header - the header stays the SDK's declarations, and
    check-declarations.py must not see a property the SDK does not declare."""
    return [("_" + store_key(keyword, properties, selector, class_name), type_name) for keyword, type_name, _piece in arguments
            if is_private_key(class_name, keyword) or store_branch(type_name) == "CF"]


# THE SECOND COPY OF DECLARED_KEYS WAS HERE - the comment and the table, verbatim - and it is gone.
# Two spellings of one rule, and the SECOND shadowed the first, which meant the copy that documented the
# table was the dead one. That is the third time in this series: the duplicate assert, the global map
# beside store_key, and now the table beside itself.

# THE READ-BACK'S OWN PARSER, and it is deliberately a SECOND implementation of the same question.
#
# The round-trip has to read each value back through the PROPERTY the header declares, and if that
# property is chosen by the same code that chose the store's key then the two cannot disagree - which is
# exactly why the dead store shipped: the expectation and the store were both wrong in the same way, so
# the check read green over a value nothing could read. So this parses the header TEXT with its own
# pattern and its own loop, calls neither store_key nor props_of, and a disagreement with the generator is
# a generation-time failure with both keys printed.
#
# A second implementation is only worth having if it is genuinely second: it matches the attribute list
# as a whole string rather than reusing the property dictionary, and it re-derives the class's block from
# the SDK text rather than from the parsed classes.
READBACK_PROPERTY = re.compile(
    r'@property\s*\(([^)]*)\)\s*([A-Za-z_][\w\s*<>,]*?)\s*(\w+)\s*(?:[A-Z_][A-Z_0-9]*\s*(?:\([^)]*\))?)?;')


def readback_property(sdk_text, class_name, argument):
    """The property this class's header declares for `argument`, found independently of the generator.

    A property NAMED as the argument wins; otherwise a property whose `getter=` is the argument. Returns
    None when the header declares neither - and None is a FAILURE at the call site, not a default, for
    the same reason store_key raises: a value no accessor reads is a value nobody can check.
    """
    blocks = re.findall(r'@interface\s+%s\b.*?@end' % re.escape(class_name), sdk_text, re.S)
    if not blocks:
        return None
    for attrs, type_name, name in READBACK_PROPERTY.findall(blocks[0]):
        if name == argument:
            return name
    for attrs, type_name, name in READBACK_PROPERTY.findall(blocks[0]):
        getter = re.search(r'getter\s*=\s*(\w+)', attrs)
        if getter and getter.group(1) == argument:
            return name
    return None


def store_key(keyword, properties, where, class_name=None):
    """The key an argument's value belongs under, from THIS class's own property declarations.

    properties is {name: prop}. A property with the argument's NAME wins; failing that, a property whose
    GETTER is the argument's name; failing that, an entry in DECLARED_KEYS, which is class-scoped and
    carries the header line it comes from. An argument that is none of those is an ERROR: there would be
    no key any accessor reads it back through, and a value nobody can read is a value nobody can check.

    The table it replaces was a GLOBAL rename map, usePrecomputedFlow -> precomputedFlow, and it was dead
    on arrival for two of the three classes that spell the argument that way - the review found
    VTFrameRateConversionConfiguration storing under "precomputedFlow" while its accessor reads
    "usePrecomputedFlow". A global map cannot be right when the SDK differs by class, which it does.
    """
    # A DECLARED ENTRY IS CONSULTED FIRST, and the order matters. VTFrameRateConversionParameters's
    # argument is destinationFrame and its PROTOCOL declares a property of that name - but the SDK
    # distinguishes the two concepts at VTFrameProcessor_FrameRateConversion.h:143, "this class is
    # ``destinationFrame`` where the processor returns output frame", against the class's own
    # `destinationFrames` array at :198, which is what the accessor reads and what the caller passed. A
    # generic property match therefore returns the protocol's member and the store is dead again, so the
    # entry - the most specific statement of the SDK's spelling - has to be asked before the general rule.
    declared = DECLARED_KEYS.get((class_name, keyword))
    if declared:
        name, getter, sdk_line = declared
        assert name in properties, (
            "%s: DECLARED_KEYS names the property %r and this class does not declare it, so the table is "
            "about this SDK and nothing else" % (class_name, name))
        return name
    if keyword in properties or is_private_key(class_name, keyword):
        # a PRIVATE key is the SDK's own: a parameter it declares no property for, kept under a name of
        # this file's own, and the value lives in an ivar rather than the store. It is spelled as itself
        # and that is correct, so it is not the table's business.
        return keyword
    for name, prop in properties.items():
        if prop.get("getter") == keyword:
            return name
    declared = DECLARED_KEYS.get((class_name, keyword))
    if declared:
        name, getter, sdk_line = declared
        assert name in properties, (
            "%s: DECLARED_KEYS names the property %r and this class does not declare it, so the table is "
            "about this SDK and nothing else" % (class_name, name))
        return name
    raise SystemExit(
        "%s: the argument %r is neither a property of %s, nor the getter of one, nor in DECLARED_KEYS for "
        "it - no accessor would read it back, and that is an error rather than a guess"
        % (where, keyword, class_name))


def init_body(selector, arguments, properties, class_name=None):
    """The body: each argument stored under the property it is NAMED after, and nothing else.

    The keyword-is-a-property rule is not asserted here: store_key is the rule and it RAISES. A second
    spelling of a rule is how the generator and the rule drift apart, and the one that was here kept
    the global map alive after store_key replaced it - which is why two classes were still writing a
    dead key while the table said the opposite.
    """
    # The IMPLEMENTATION's signature carries the types, not the bare selector. A declaration may be
    # written selector-only, but an @implementation may not: - (instancetype)initWithBuffer:presentationTimeStamp:
    # with no types is "expected identifier" in a definition and fine in a header. Same spelling, both
    # places, built by the same function - so a signature cannot be right in one and wrong in the other.
    head = init_signature(selector, arguments, 'instancetype')
    head = head.replace('(nullable instancetype)', '(instancetype)').rstrip(';')
    lines = [head, '{']
    for index, (keyword, _type_name, _piece) in enumerate(arguments):
        lines.append('    self = [super init];' if index == 0 else None)
    lines = [l for l in lines if l is not None]
    for keyword, type_name, _piece in arguments:
        # the PROPERTY's own name, which is what the accessor reads, even where the SDK's argument is
        # spelled differently; and the branch by the ARGUMENT'S TYPE, never by a property's name
        key = store_key(keyword, properties, selector, class_name)
        branch = store_branch(type_name)
        if is_private_key(class_name, keyword) or branch == "CF":
            # a CFTypeRef is an ivar, and it is retained: the SDK declares the property with no ownership
            # annotation, so the frame is what holds it
            lines.append('    self->_%s = (%s)%s;' % (key, type_name, keyword))
            if branch == "CF" and not is_private_key(class_name, keyword):
                lines.append('    if (self->_%s)' % key)
                lines.append('        CFRetain(self->_%s);' % key)
        elif branch == "struct":
            # a struct is boxed, which is the other end of the getValue: its accessor reads
            lines.append('    { %s boxed = %s;' % (type_name, keyword))
            lines.append('      CharonValueSet(self, [NSValue valueWithBytes:&boxed objCType:@encode(%s)],'
                         ' @"%s"); }' % (type_name, key))
        elif branch == "object":
            lines.append('    CharonValueSet(self, %s, @"%s");' % (keyword, key))
        else:
            lines.append('    CharonValueSet(self, @(%s), @"%s");' % (keyword, key))
    lines += ['    return self;', '}', '']
    return '\n'.join(lines)


# A type with a COMMA cannot be an argument to CHARON_VALUE_PROPERTY, and both obvious spellings are dead
# ends. Unparenthesised, the preprocessor splits the argument and the macro is handed three of them:
# "too many arguments provided". Parenthesised, the macro expands to -((NSDictionary<NSString *, id> *))
# and clang rejects the doubled parentheses: "expected a type". Both measured, this session.
#
# So a comma-carrying type gets a FILE-LOCAL TYPEDEF, emitted at the top of the .m, and the macro takes
# that name. One accessor path - no predicate, no second spelling of an accessor - and the header keeps
# the SDK's own spelling, which is what check-declarations.py reads: it compares the header, not the .m.
MACRO_TYPEDEFS = {
    "NSDictionary<NSString *, id> *": "CharonVTFrameAttributes",
    "NSArray<NSString *, id> *": "CharonVTFrameAttributeList",
}


def _macro_type(type_name):
    """The spelling the macro takes: the file-local typedef where one exists, else the type itself."""
    # The typedef names the object type itself - typedef NSDictionary<NSString *, id> X; is a POINTER
    # typedef, which is what an Objective-C object type is - and the macro expands -(Type)name, so the
    # argument still has to carry the star like every other object property. Without it the macro
    # returns the object BY VALUE: "interface type cannot be returned by value".
    alias = MACRO_TYPEDEFS.get(type_name)
    return alias + " *" if alias else type_name


def macro_typedefs(type_names):
    """The typedef lines a .m needs, for the comma-carrying types its accessors name."""
    lines = ["",
             "// A file-local spelling for the types the property macros cannot take. Each of these carries a",
             "// comma, and the preprocessor counts arguments rather than template parameters, so the macro",
             "// would be handed three arguments for one type. The declaration in CharonVideoToolbox.h keeps",
             "// the SDK's own spelling: this is the same type, named once so the macro has one argument."]
    emitted = []
    for name in type_names:
        alias = MACRO_TYPEDEFS.get(name)
        if alias and alias not in emitted:
            emitted.append(alias)
            lines.append("typedef %s %s;" % (name[:-2].strip(), alias))
    return lines + [""]


def prop_line(n, p):
    t = p['type'] + (' *' if p['obj'] else '')
    parts = (['class'] if p['class'] else []) + ['nonatomic', 'readonly',
                                                 'strong' if p['obj'] else 'assign']
    if p['getter'] and p['getter'] != n:
        parts.append('getter=%s' % p['getter'])
    return '@property (%s) %s %s;' % (', '.join(parts), t, n)


def body(n, p):
    store = 'CharonValueStoreOfClass([self class])' if p['class'] else 'CharonValueStore(self)'
    ret = p['type'] + (' *' if p['obj'] else '')
    sig = ('+ ' if p['class'] else '- ') + '(%s)%s' % (ret, p['getter'] or n)
    key = '@"%s"' % n
    if not p['class'] and store_branch(p['type']) == 'CF':
        # A CFTypeRef is an IVAR of the property's own name, not a store entry - the store is keyed by
        # property name and read by the value walk, and a buffer is not a value object. It is retained on
        # the way in, so the frame owns the buffer, and retained again on the way out, because handing a
        # caller a buffer it does not own is how a use-after-free starts.
        return ('%s\n{\n    if (self->_%s)\n        CFRetain(self->_%s);\n    return self->_%s;\n}\n'
                % (sig, n, n, n))
    if p['class']:
        # A CLASS property has no instance to keep the value on, so its value is on the class and no macro
        # reaches it: CharonValueStore's three macros all read [self charon_valueForKey:]. These stay
        # written out.
        if p['obj']:
            return '%s\n{\n    return (%s)%s[%s];\n}\n' % (sig, ret, store, key)
        if p['type'] in STRUCTS:
            return ('%s\n{\n    %s value = {0};\n    NSValue *boxed = %s[%s];\n    if (boxed)\n'
                    '        [boxed getValue:&value];\n    return value;\n}\n'
                    % (sig, p['type'], store, key))
        if p['type'] == 'CVPixelBufferRef':
            return ('%s\n{\n    CVPixelBufferRef value = NULL;\n    NSValue *boxed = %s[%s];\n'
                    '    if (boxed)\n    {\n        [boxed getValue:&value];\n'
                    '        if (value)\n            CFRetain(value);\n    }\n    return value;\n}\n'
                    % (sig, store, key))
        cast = {'BOOL': 'BOOL', 'NSInteger': 'NSInteger', 'float': 'float'}.get(p['type'], p['type'])
        return '%s\n{\n    return (%s)[%s[%s] longLongValue];\n}\n' % (sig, cast, store, key)
    if p.get('getter') and p['getter'] != n:
        # the getter differs from the name, so no macro can spell it
        if p['obj']:
            return '%s\n{\n    return (%s)%s[%s];\n}\n' % (sig, ret, store, key)
        cast = {'BOOL': 'BOOL', 'NSInteger': 'NSInteger', 'float': 'float'}.get(p['type'], p['type'])
        return '%s\n{\n    return (%s)[%s[%s] longLongValue];\n}\n' % (sig, cast, store, key)
    if p['obj']:
        # An INSTANCE object property is one line of the store's own macro. The cast inside it takes the
        # type with its pointer, so the argument is the same spelling: (NSArray<NSNumber *> * *) would be
        # a pointer to a pointer, and ARC rejects that cast.
        # The type is PARENTHESISED when it carries a comma, because the preprocessor does not know
        # what a template argument list is: CHARON_VALUE_PROPERTY(NSDictionary<NSString *, id> *,
        # sourcePixelBufferAttributes) hands the macro THREE arguments, and it fails with 'too many
        # arguments provided'. Every dictionary property in this family has that shape, so this is most
        # of the object properties rather than a corner. The macro expands -(Type)name, and an extra
        # pair of parentheses around the type is accepted there.
        return 'CHARON_VALUE_PROPERTY(%s, %s)\n' % (_macro_type(ret), n)
    if p['type'] not in STRUCTS and p['type'] != 'CVPixelBufferRef':
        # A scalar or an enumeration reads through longLongValue, and a float through doubleValue - which
        # longLongValue would round. The two macros are the store's, not ours.
        macro = 'CHARON_DOUBLE_PROPERTY' if p['type'] == 'float' else 'CHARON_SCALAR_PROPERTY'
        return '%s(%s, %s)\n' % (macro, p['type'], n)
    if p['type'] in STRUCTS:
        # getValue:, NOT getValue:size:. The two-argument form is iOS 11.0 and this library is built for
        # 6.0: -Wunguarded-availability-new names every one of these call sites, and on a 6.1.3 device that
        # selector is not there, so a struct read is an unrecognised-selector crash. The one-argument form is
        # iOS 2.0, so it exists on every release this package covers, and the size is implied by the value's
        # own type. The whole earlier series compiled with -w, which is how an iOS 11 call sat in nine files
        # that a reviewer and a compiler both passed over.
        return ('%s\n{\n    %s value = {0};\n    NSValue *boxed = %s[%s];\n    if (boxed)\n'
                '        [boxed getValue:&value];\n    return value;\n}\n'
                % (sig, p['type'], store, key))
    if p['type'] == 'CVPixelBufferRef':
        return ('%s\n{\n    CVPixelBufferRef value = NULL;\n    NSValue *boxed = %s[%s];\n'
                '    if (boxed)\n    {\n        [boxed getValue:&value];\n'
                '        if (value)\n            CFRetain(value);\n    }\n    return value;\n}\n'
                % (sig, store, key))
    cast = {'BOOL': 'BOOL', 'NSInteger': 'NSInteger', 'float': 'float'}.get(p['type'], p['type'])
    return '%s\n{\n    return (%s)[%s[%s] longLongValue];\n}\n' % (sig, cast, store, key)


def emit(classes, outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    for c, v in classes.items():
        protos = ' <%s>' % ', '.join(v['protocols']) if v['protocols'] else ''
        h = ['@interface %s : %s%s\n' % (c, v['sup'], protos), '']
        for n, p in v['own'].items():
            h.append(prop_line(n, p))
        h.append('@end\n')
        m = ['@implementation %s\n' % c]
        for n, p in v['own'].items():
            m.append(body(n, p))
        m.append('@end\n')
        open(os.path.join(outdir, '%s.h' % c), 'w').write('\n'.join(h))
        open(os.path.join(outdir, '%s.m' % c), 'w').write('\n'.join(m))
