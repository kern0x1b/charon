#!/usr/bin/env python3
"""Checks gen_body on the declarations whose spelling broke it, before anything is generated from it.

The star was absorbed by the pattern's own `\\*?`, so a property the SDK writes `NSIndexSet*` was read as a
scalar and generated as a by-value return of an interface type - which the compiler rejects, correctly,
and which cost a run of this series. The SDK writes both spellings, so both are here: a check that only
covered the spaced one would have passed on the broken code.

    python3 test-gen-body.py
"""
import importlib.util
import re
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("gen_body", os.path.join(HERE, "gen_body.py"))
gen_body = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen_body)
assert os.path.abspath(gen_body.__file__) == os.path.join(HERE, "gen_body.py"), \
    "loaded %s, not this directory's copy" % gen_body.__file__

CASES = [
    # (declaration, expected name, expected type, expected obj, expected class, expected getter)
    ('@property (nonatomic, readonly) NSIndexSet* supportedRevisions;',
     "supportedRevisions", "NSIndexSet", True, False, None),
    ('@property (nonatomic, readonly) NSIndexSet * supportedRevisions;',
     "supportedRevisions", "NSIndexSet", True, False, None),
    ('@property (nonatomic, readonly) NSArray<NSNumber *> * frameSupportedPixelFormats '
     'NS_REFINED_FOR_SWIFT;',
     "frameSupportedPixelFormats", "NSArray<NSNumber *>", True, False, None),
    ('@property (nonatomic, readonly) NSDictionary<NSString *, id> * sourcePixelBufferAttributes;',
     "sourcePixelBufferAttributes", "NSDictionary<NSString *, id>", True, False, None),
    ('@property (class, nonatomic, readonly, getter=isSupported) BOOL supported;',
     "supported", "BOOL", False, True, "isSupported"),
    ('@property (nonatomic, readonly) NSInteger frameWidth;',
     "frameWidth", "NSInteger", False, False, None),
    ('@property (nonatomic, readonly) float configurationModelPercentageAvailable;',
     "configurationModelPercentageAvailable", "float", False, False, None),
    ('@property (nonatomic, readonly) CMVideoDimensions maximumDimensions;',
     "maximumDimensions", "CMVideoDimensions", False, False, None),
    ('@property (nonatomic, readonly) CMTime presentationTimeStamp;',
     "presentationTimeStamp", "CMTime", False, False, None),
    # A CFTypeRef is NOT an object property and NOT a scalar either: it is a reference the accessor
    # retains out of the store, which is the branch that wanted CVPixelBufferRetain.
    ('@property (nonatomic, readonly) CVPixelBufferRef buffer;',
     "buffer", "CVPixelBufferRef", False, False, None),
    # the SDK's own spelling of an absent-on-iOS property: the strip has to leave the name behind
    # The nested parens here are the point: API_DEPRECATED_WITH_REPLACEMENT("isSupported", macos(15.4,
    # 26.0)) used to leave a trailing ')' and the property vanished from the parse altogether.
    ('@property (class, nonatomic, readonly) Boolean processorSupported '
     'API_DEPRECATED_WITH_REPLACEMENT("isSupported", macos(15.4, 26.0)) API_UNAVAILABLE(ios);',
     "processorSupported", "Boolean", False, True, None),
]

bad = []
for declaration, name, type_, obj, is_class, getter in CASES:
    got = gen_body.props_of(declaration)
    if name not in got:
        bad.append("%s -> no property parsed at all" % declaration)
        continue
    p = got[name]
    for field, want in (("type", type_), ("obj", obj), ("class", is_class), ("getter", getter)):
        if p[field] != want:
            bad.append("%s -> %s is %r, wanted %r" % (declaration, field, p[field], want))
    print("  %-34s %-30s obj=%-5s class=%-5s getter=%s"
          % (name, p["type"], p["obj"], p["class"], p["getter"]))

# and the accessor it generates for the two spellings of the same property must be the SAME, or the
# port would have one accessor for the spaced spelling and another for the unspaced one
spaced = gen_body.body("supportedRevisions", gen_body.props_of(
    '@property (nonatomic, readonly) NSIndexSet * supportedRevisions;')["supportedRevisions"])
unspaced = gen_body.body("supportedRevisions", gen_body.props_of(
    '@property (nonatomic, readonly) NSIndexSet* supportedRevisions;')["supportedRevisions"])
if spaced != unspaced:
    bad.append("the two spellings generate different accessors:\n%s\n%s" % (spaced, unspaced))
else:
    print("  both spellings generate one accessor: %s" % spaced.splitlines()[0].strip())

# The generated accessor is checked as TEXT, not only for agreeing with itself: the cast once spelled the
# star twice, `(NSArray<NSNumber *> * *)`, and a test that only compared the two spellings with each other
# passed on that, because both were wrong in the same way. ARC rejects a pointer-to-pointer cast, so the
# exact return line is what has to be asserted.
# An INSTANCE property is one line of the package's own macro - CHARON_VALUE_PROPERTY and
# CHARON_SCALAR_PROPERTY from CharonValueStore.h - since the macro-capable generator landed in
# ce094d3a4. The check is still worth having and is still the same check: a pointer-to-pointer would be
# `(NSArray<NSNumber *> * *)`, and that doubled star is exactly what this catches. A CLASS property stays
# hand-written, because all three macros read [self charon_valueForKey:] and a class property's value is
# on the class.
EXPECTED = {
    "object": "CHARON_VALUE_PROPERTY(NSIndexSet *, supportedRevisions)\n",
    "class-object": "+ (NSIndexSet *)supportedRevisions\n{\n"
                    "    return (NSIndexSet *)CharonValueStoreOfClass([self class])"
                    "[@\"supportedRevisions\"];\n}\n",
    "scalar": "CHARON_SCALAR_PROPERTY(NSInteger, frameWidth)\n",
}
shapes = {
    "object": gen_body.props_of('@property (nonatomic, readonly) NSIndexSet* supportedRevisions;')["supportedRevisions"],
    "class-object": gen_body.props_of('@property (class, nonatomic, readonly) NSIndexSet* supportedRevisions;')["supportedRevisions"],
    "scalar": gen_body.props_of('@property (nonatomic, readonly) NSInteger frameWidth;')["frameWidth"],
}
for shape, prop in shapes.items():
    got = gen_body.body(prop["getter"] or "supportedRevisions", prop) if shape != "scalar" \
        else gen_body.body("frameWidth", prop)
    if got != EXPECTED[shape]:
        bad.append("the %s accessor is not what it should be:\n  got      %r\n  expected %r"
                   % (shape, got, EXPECTED[shape]))
    else:
        print("  %-13s accessor exact: %s" % (shape, got.splitlines()[0].strip()))

# And the exclusion is a RULE, not a side effect of a regex: parse() must leave every property the SDK
# marks API_UNAVAILABLE(ios) out of the class, and name it, because step 4 registers those ledger rows as
# absent with that reason. Measured against the SDK itself - three classes declare processorSupported and
# none of them may carry it.
sdk = os.environ.get("VT_SDK", "")
if not sdk:
    print("  VT_SDK unset: the API_UNAVAILABLE(ios) rule is NOT checked here")
else:
    import glob
    headers = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    text = "\n".join(open(f).read() for f in sorted(glob.glob(os.path.join(headers, "*.h"))))
    _, allclasses = gen_body.parse(text)
    excluding = sorted(c for c, entry in allclasses.items() if entry.get("unavailable_ios"))
    if excluding != ["VTFrameRateConversionConfiguration", "VTMotionBlurConfiguration",
                     "VTOpticalFlowConfiguration"]:
        bad.append("API_UNAVAILABLE(ios) excluded by %r, wanted the three classes the SDK declares it on"
                   % excluding)
    for cls in excluding:
        entry = allclasses[cls]
        if entry["unavailable_ios"] != ["processorSupported"]:
            bad.append("%s recorded %r" % (cls, entry["unavailable_ios"]))
        if "processorSupported" in entry["own"]:
            bad.append("%s carried processorSupported" % cls)
        print("  %-46s excludes %s (API_UNAVAILABLE(ios))" % (cls, ",".join(entry["unavailable_ios"])))

# THE SELECTOR PIECE AND THE ARGUMENT NAME ARE NOT ALWAYS THE SAME WORD, and SDK 26.2 has one where
# they differ. VTFrameProcessor_FrameRateConversion.h:166-171, quoted:
#
#   - (nullable instancetype) initWithSourceFrame:(VTFrameProcessorFrame *)sourceFrame
#                                           nextFrame:(VTFrameProcessorFrame *)nextFrame
#                                           opticalFlow:(VTFrameProcessorOpticalFlow * _Nullable)opticalFlow
#                                    interpolationPhase:(NSArray<NSNumber *> *) interpolationPhase
#                                      submissionMode:(VTFrameRateConversionParametersSubmissionMode)submissionMode
#                                   destinationFrames:(NSArray<VTFrameProcessorFrame *> *)destinationFrame NS_REFINED_FOR_SWIFT;
#
# The selector says destinationFrames: and the parameter is named destinationFrame. The piece is the API
# contract and belongs in the declaration; the name is what the value is called and is what the store
# keys. Building the selector from the NAME produced a declaration of a method the SDK does not have, and
# check-declarations.py caught it as EXTRA - the first time that check caught a generator rather than a
# hand-written line.
SDK_DECLARATION = """- (nullable instancetype) initWithSourceFrame:(VTFrameProcessorFrame *)sourceFrame
                                                                 nextFrame:(VTFrameProcessorFrame *)nextFrame
                                                                 opticalFlow:(VTFrameProcessorOpticalFlow * _Nullable)opticalFlow
                                                          interpolationPhase:(NSArray<NSNumber *> *) interpolationPhase
                                                            submissionMode:(VTFrameRateConversionParametersSubmissionMode)submissionMode
                                                         destinationFrames:(NSArray<VTFrameProcessorFrame *> *)destinationFrame NS_REFINED_FOR_SWIFT;"""

pieces = re.findall(r"(\w+):\s*\(([^)]*)\)\s*(\w+)", gen_body.strip(SDK_DECLARATION))
expected_pieces = ["initWithSourceFrame", "nextFrame", "opticalFlow", "interpolationPhase",
                   "submissionMode", "destinationFrames"]
expected_names = ["sourceFrame", "nextFrame", "opticalFlow", "interpolationPhase", "submissionMode",
                  "destinationFrame"]
if [p[0] for p in pieces] != expected_pieces:
    bad.append("the selector pieces are %r, wanted %r" % ([p[0] for p in pieces], expected_pieces))
if [p[2] for p in pieces] != expected_names:
    bad.append("the argument names are %r, wanted %r" % ([p[2] for p in pieces], expected_names))
print("  the declaration yields %d pieces, the last two differing: %r / %r"
      % (len(pieces), pieces[-1][0], pieces[-1][2]))

# and the declaration built from them must spell the SDK's selector, ending in destinationFrames:
selector = "".join(piece + ":" for piece, _type, _arg in pieces)
if not selector.endswith("destinationFrames:"):
    bad.append("the built selector ends %r, wanted it to end with destinationFrames:" % selector[-24:])
signature = gen_body.init_signature(selector, [(a, t, p) for p, t, a in pieces], "instancetype")
if "destinationFrames:(NSArray<VTFrameProcessorFrame *> *)destinationFrame" not in signature:
    bad.append("the declaration does not spell the SDK's last piece:\n%s" % signature)
print("  the declaration's last piece: %s"
      % [l for l in signature.split("\n") if "destinationFrames" in l][0].strip())

# ONE TEST PER BRANCH of the initialiser's store line, because the branch is chosen by the argument's
# TYPE and the three are genuinely different code. The failure that brought them here is the one worth
# naming: a rule asserted for scalars and applied to everything, so @(buffer) boxed a CFTypeRef and
# @(presentationTimeStamp) boxed a CMTime, and the compiler said "illegal type used in by-value return".
SCALAR_ARGS = [("frameWidth", "NSInteger", "frameWidth"),
               ("frameHeight", "NSInteger", "frameHeight"),
               ("usePrecomputedFlow", "BOOL", "usePrecomputedFlow")]
CF_ARG = ("buffer", "CVPixelBufferRef", "buffer")
STRUCT_ARG = ("presentationTimeStamp", "CMTime", "presentationTimeStamp")

for label, arg, wanted in (
        ("a scalar goes in the keyed store", SCALAR_ARGS,
         '    CharonValueSet(self, @(frameWidth), @"frameWidth");'),
        ("a CFTypeRef goes in an ivar, retained", [CF_ARG],
         '    if (self->_buffer)\n        CFRetain(self->_buffer);'),
        ("a struct is boxed, which is what getValue: reads", [STRUCT_ARG],
         'CharonValueSet(self, [NSValue valueWithBytes:&boxed objCType:@encode(CMTime)], @"presentationTimeStamp");')):
    body_text = gen_body.init_body("initWithBuffer:presentationTimeStamp:", arg, {"buffer", "presentationTimeStamp", "frameWidth", "frameHeight", "usePrecomputedFlow"})
    if wanted not in body_text:
        bad.append("%s: the body has no %r\n%s" % (label, wanted, body_text))
    else:
        print("  %-46s %s" % (label, wanted.strip()[:44]))

# and the CF branch is chosen by the TYPE: the same property name with a different type is a different
# branch, which is the rule stated as a test rather than as a comment
if "self->_buffer" in gen_body.init_body("initWithX:", [("buffer", "NSInteger", "buffer")], {"buffer"}):
    bad.append("a NSInteger named buffer took the CF branch - the branch is following the NAME")

# and the accessor for a CF property reads the ivar, not the store
cf_accessor = gen_body.body("buffer", gen_body.props_of("@property(nonatomic,readonly) CVPixelBufferRef buffer;")["buffer"])
if "self->_buffer" not in cf_accessor or "CharonValueStore" in cf_accessor:
    bad.append("the CF accessor does not read the ivar:\n%s" % cf_accessor)
else:
    print("  the CF accessor reads the ivar: %s" % cf_accessor.splitlines()[0].strip())

# THE MANDATORY WALK. Every argument type of all seventeen initialisers, the branch each one takes, and
# a FAILURE for any type with no expected branch - because a type nobody classified is a type that
# reaches the generator's store line unclassified, and that is how @(buffer) boxed a CFTypeRef,
# @(presentationTimeStamp) boxed a CMTime and @(sourceFrame) boxed an object: three compiles, one rule
# that was asserted for scalars and applied to everything.
#
# The expected branch is stated here, per type, and the types are read from the SDK - so a type the SDK
# adds later has no entry and the test is RED until someone says which branch it takes.
EXPECTED_BRANCH = {
    "CVPixelBufferRef": "CF",
    "CMTime": "struct",
    "OSType": "scalar",
    "NSInteger": "scalar",
    "BOOL": "scalar",
    "float": "scalar",
    "Boolean": "scalar",
    "NSArray<NSNumber *> *": "object",
    "NSArray<VTFrameProcessorFrame *> *": "object",
    "VTFrameProcessorFrame *": "object",
    "VTFrameProcessorFrame * _Nullable": "object",
    "VTFrameProcessorOpticalFlow *": "object",
    "VTFrameProcessorOpticalFlow * _Nullable": "object",
    "VTMotionBlurConfigurationQualityPrioritization": "scalar",
    "VTMotionBlurConfigurationRevision": "scalar",
    "VTFrameRateConversionParametersSubmissionMode": "scalar",
    "VTFrameRateConversionConfigurationQualityPrioritization": "scalar",
    "VTFrameRateConversionConfigurationRevision": "scalar",
    "VTOpticalFlowConfigurationQualityPrioritization": "scalar",
    "VTOpticalFlowConfigurationRevision": "scalar",
    "VTOpticalFlowParametersSubmissionMode": "scalar",
    "VTSuperResolutionScalerConfigurationQualityPrioritization": "scalar",
    "VTSuperResolutionScalerConfigurationRevision": "scalar",
    "VTSuperResolutionScalerConfigurationInputType": "scalar",
    "VTSuperResolutionScalerParametersSubmissionMode": "scalar",
    "VTTemporalNoiseFilterConfigurationQualityPrioritization": "scalar",
    "VTTemporalNoiseFilterConfigurationRevision": "scalar",
    "VTLowLatencyFrameInterpolationConfigurationQualityPrioritization": "scalar",
    "VTLowLatencyFrameInterpolationConfigurationRevision": "scalar",
    "VTLowLatencyFrameInterpolationParametersSubmissionMode": "scalar",
    "VTLowLatencySuperResolutionScalerConfigurationQualityPrioritization": "scalar",
    "VTLowLatencySuperResolutionScalerConfigurationRevision": "scalar",
    "VTLowLatencySuperResolutionScalerParametersSubmissionMode": "scalar",
    "VTMotionBlurParametersSubmissionMode": "scalar",
    "id": "object",
}

sdk = os.environ.get("VT_SDK", "")
if not sdk:
    print("  VT_SDK unset: the branch walk is NOT checked here")
else:
    import glob as _glob
    frameworks = os.path.join(sdk, "System/Library/Frameworks")
    directories = [os.path.join(frameworks, name, "Headers")
                   for name in sorted(os.listdir(frameworks))
                   if os.path.isdir(os.path.join(frameworks, name, "Headers"))]
    directories.append(os.path.join(sdk, "usr/include"))
    headers = os.path.join(sdk, 'System/Library/Frameworks/VideoToolbox.framework/Headers')
    import glob as _glob
    text = chr(10).join(open(f).read() for f in sorted(_glob.glob(os.path.join(headers, '*.h'))))
    seen = []
    for cls in gen_body.ORDER:
        for _selector, arguments, _returns in gen_body.initialisers(text, cls):
            for _keyword, type_name, _piece in arguments:
                if type_name not in seen:
                    seen.append(type_name)
    signals = {t: (c, e) for t, c, e in [(r[0], int(r[1]), r[2] == "objc") for r in [l.split(chr(9)) for l in open(os.path.join(HERE, "..", "..", "..", "..", ".agent-work", "runs", "vt", "type-branches.tsv"))] if len(r) == 3]}
    canonical = gen_body.probe_types(sdk, seen, os.path.join(HERE, "..", "..", "..", "..",
                                                            ".agent-work", "runs", "vt"))
    print("  %d distinct argument types across the seventeen initialisers" % len(seen))
    for type_name in seen:
        got = signals.get(type_name, (None, False)) and gen_body.branch_of(*signals[type_name])
        wanted = EXPECTED_BRANCH.get(type_name)
        if wanted is None:
            bad.append("%s: no expected branch - the SDK declares it and nobody classified it "
                       "(the compiler says %r)" % (type_name, canonical.get(type_name)))
            print("     %-58s %-38s NO EXPECTED BRANCH" % (type_name, canonical.get(type_name)))
        elif got != wanted:
            bad.append("%s: the branch is %s and it should be %s (the compiler says %r)"
                       % (type_name, got, wanted, canonical.get(type_name)))
            print("     %-58s %-38s wanted %s" % (type_name, canonical.get(type_name), wanted))
        else:
            print("     %-58s %-38s %s" % (type_name, canonical.get(type_name), got))
    # the two cases named on their own, with the compiler's answer beside them
    for type_name, wanted in (("CVPixelBufferRef", "CF"), ("OSType", "scalar"),
                              ("NSArray<NSNumber *> *", "object"), ("CMTime", "struct")):
        got = signals.get(type_name, (None, False)) and gen_body.branch_of(*signals[type_name])
        if got != wanted:
            bad.append("%s: the compiler says %r and the branch is %s, wanted %s"
                       % (type_name, canonical.get(type_name), got, wanted))

for line in bad:
    print("FAIL " + line)
if bad:
    sys.exit(1)
print("gen_body: %d declarations, both spellings, one accessor each" % len(CASES))
