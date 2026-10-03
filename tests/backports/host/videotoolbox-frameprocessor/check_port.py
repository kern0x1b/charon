#!/usr/bin/env python3
"""check_port.py - hold the port's frame processor to what the host measured and to the registry.

    check_port.py <host-answers output> <apple-backports dir> <build dir>

Two halves, and they are separate because they are separate kinds of evidence:

  1. the HOST half. The domain string the host printed must be the string the port's own constant holds,
     read out of the port's compiled armv7 object rather than out of its source - a source check alone
     would pass on a constant the compiler never emitted. The fourteen codes the host printed must be
     the values the port's header enumerates, which is what catches a transcription typo of -19739.

  2. the PORT half. Every selector the new registry rows claim must be in the armv7 objects, and every
     selector an `absent` row names must NOT be in them: the second is the half that catches an
     "absent" row that quietly carries the method anyway, which check_registry would also catch but only
     at gate time.

WHAT IT DELIBERATELY DOES NOT CLAIM. +isSupported answers 1 on this host, because this host is an M4 Pro
with the Neural Engine these processors need, while the port answers NO because no armv7 release has
one. That difference is the documented behaviour for hardware a device lacks and the release
measurement - no VTFrameProcessor class and no VTFrameProcessor* symbol in the 6.1.3 cache - is what
stands behind the port's side of it. This file prints both numbers and asserts neither against the
other; pretending the host were the oracle for that value would be a false check, not a strict one.
"""
import json
import os
import re
import subprocess
import sys

# The seven configuration classes and the one parameters class + the two value holders, in the host's
# own order. Sixteen of the seventeen declare -init NS_UNAVAILABLE, and VTFrameProcessor is the
# exception - so this is what separates the `absent` rows from the one `implemented` one.
NS_UNAVAILABLE_CLASSES = [
    "VTFrameProcessorFrame", "VTFrameProcessorOpticalFlow", "VTFrameRateConversionConfiguration",
    "VTFrameRateConversionParameters", "VTLowLatencyFrameInterpolationConfiguration",
    "VTLowLatencyFrameInterpolationParameters", "VTLowLatencySuperResolutionScalerConfiguration",
    "VTLowLatencySuperResolutionScalerParameters", "VTMotionBlurConfiguration", "VTMotionBlurParameters",
    "VTOpticalFlowConfiguration", "VTOpticalFlowParameters", "VTSuperResolutionScalerConfiguration",
    "VTSuperResolutionScalerParameters", "VTTemporalNoiseFilterConfiguration",
    "VTTemporalNoiseFilterParameters",
]

# The six methods SDK 26.2 declares on VTFrameProcessor that the port carries. -init is NOT among them:
# Apple's own class implements none, so the port's must not either - the same rule the sixteen
# NS_UNAVAILABLE classes are held to, for the same measured reason.
PROCESSOR_METHODS = [
    "startSessionWithConfiguration:error:", "processWithParameters:error:",
    "processWithParameters:completionHandler:", "processWithParameters:frameOutputHandler:",
    "processWithCommandBuffer:parameters:", "endSession",
]

# The two methods of the other two classes this series adds.
OTHER_METHODS = {
    "VTLowLatencySuperResolutionScalerConfiguration": ["supportedScaleFactorsForFrameWidth:frameHeight:"],
    "VTSuperResolutionScalerConfiguration": ["downloadConfigurationModelWithCompletionHandler:"],
}


def own_methods(obj):
    """The methods the object DEFINES for one class, instance and class, out of the class's own
    baseMethods list.

    Not the selector strings: __objc_methname holds every selector an object MENTIONS, and
    `[super init]` in any initialiser puts the four letters of "init" in there whatever the class
    declares. That is what an earlier version of this file read, and it reported all sixteen
    NS_UNAVAILABLE classes as carrying -init. baseMethods is the list a message dispatch walks, and it
    is the same list modules/apple/objc.lua's binary_inventory reads, so this agrees with what the
    ledger measures rather than with what the compiler mentioned.
    """
    out = subprocess.run(["otool", "-oV", obj], check=True, capture_output=True, text=True).stdout
    instance, klass, current = set(), set(), None
    for line in out.split("\n"):
        if "baseMethods" in line:
            current = instance if "INSTANCE_METHODS" in line else klass
        elif current is not None and re.match(r"^\s+name\s+0x[0-9a-f]+\s+(\S+)$", line):
            current.add(re.match(r"^\s+name\s+0x[0-9a-f]+\s+(\S+)$", line).group(1))
    return {"instance": instance, "class": klass}


def literal_strings(obj):
    """The string literals the object carries, read out of __TEXT,__cstring. Apple's and the port's
    error domain are both constant strings, and the port's own lives here."""
    out = subprocess.run(["otool", "-v", "-s", "__TEXT", "__cstring", obj],
                         check=True, capture_output=True, text=True).stdout
    found = set()
    for line in out.split("\n"):
        match = re.match(r"^[0-9a-f]{6,}  (\S.*)$", line)
        if match:
            found.add(match.group(1).strip())
    return found


def numbers_in_header(path):
    """Every integer the header enumerates as a VTFrameProcessor code, so a transcription typo shows."""
    text = open(path, encoding="utf-8").read()
    found = {}
    for name, value in re.findall(r"\b(VTFrameProcessor[A-Za-z]+) = (-?\d+),", text):
        found[name] = int(value)
    return found


def read_registry(backports):
    """Every row VideoToolbox's registry holds, over all of its files - ios26.json for the frame
    processor and ios18.json for the HDR per-frame metadata session. Reading one file would have made
    this check blind to a family it is meant to hold."""
    folder = os.path.join(backports, "registry", "VideoToolbox")
    rows = {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        for entry in json.load(open(os.path.join(folder, name), encoding="utf-8"))["entries"]:
            rows[(entry["api"], entry["kind"])] = entry
    return rows


def main():
    if len(sys.argv) != 4:
        sys.exit("check_port.py: pass <host-answers output> <apple-backports dir> <build dir>")
    host_path, backports, build = sys.argv[1:4]

    domain, codes, supported, unavailable, raised = None, {}, {}, {}, []
    controls = 0
    for line in open(host_path, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if parts[0] == "CONTROL" and len(parts) == 3:
            controls += 1
        elif parts[0] == "DOMAIN" and len(parts) == 3:
            domain = parts[1]
        elif parts[0] == "ERRORCODE" and len(parts) == 3:
            codes[parts[1]] = int(parts[2])
        elif parts[0] == "SUPPORTED" and len(parts) == 3:
            supported[parts[1]] = parts[2]
        elif parts[0] == "UNAVAILABLE" and len(parts) == 6:
            unavailable[parts[1]] = (parts[2], parts[3], parts[4], parts[5])
        elif parts[0] == "RAISES" and len(parts) == 3:
            raised.append((parts[1], parts[2]))

    failures = []
    if controls != 1:
        failures.append("the host reader printed %d control lines, and this check trusts none of its "
                        "output without exactly one" % controls)
    if not domain:
        failures.append("the host reader printed no DOMAIN line")
    if len(codes) != 14:
        failures.append("the host printed %d error codes, and SDK 26.2 enumerates 14" % len(codes))

    header = os.path.join(backports, "VideoToolbox", "CharonVideoToolbox.h")
    port_codes = numbers_in_header(header)
    for name, value in sorted(codes.items()):
        if port_codes.get(name) != value:
            failures.append("%s is %s on the host and %s in CharonVideoToolbox.h"
                            % (name, value, port_codes.get(name)))
    missing_codes = set(codes) - set(port_codes)
    if missing_codes:
        failures.append("CharonVideoToolbox.h enumerates none of %s" % ", ".join(sorted(missing_codes)))

    domain_object = os.path.join(build, "VTFrameProcessorErrors26_0.o")
    strings = literal_strings(domain_object)
    if domain and domain not in strings:
        failures.append("the port's compiled error-domain object carries no literal %r; it carries %s"
                        % (domain, sorted(strings) or "no string at all"))

    registry = read_registry(backports)

    processor = own_methods(os.path.join(build, "VTFrameProcessor.o"))["instance"]
    for method in PROCESSOR_METHODS:
        if method not in processor:
            failures.append("VTFrameProcessor.o carries no -%s, and the registry row claims it"
                            % method)
        row = registry.get(("-[VTFrameProcessor %s]" % method, "method"))
        if row is None or row["status"] != "implemented":
            failures.append("no implemented registry row for -[VTFrameProcessor %s]" % method)

    # -init is the other half of the same rule: Apple's VTFrameProcessor implements none, so the port's must
    # not either, and the row is `absent` rather than unimplemented. SDK 26.2 declares it WITHOUT the
    # NS_UNAVAILABLE the other sixteen carry, which is why this assertion exists separately - the annotation
    # is not what decides it, the host measurement is.
    if "init" in processor:
        failures.append("VTFrameProcessor.o defines -init; the host's class implements none of its own, so "
                        "the port's class must not differ from Apple's in which class owns the method")
    processor_init_row = registry.get(("-[VTFrameProcessor init]", "method"))
    if processor_init_row is None or processor_init_row["status"] != "absent":
        failures.append("-[VTFrameProcessor init] is not an absent registry row; the host's class implements "
                        "no -init of its own")

    # Every class the SDK marks -init NS_UNAVAILABLE: its compiled object must carry neither -init nor
    # +new, and the registry must say absent for both. An `absent` row that carried the method anyway is
    # the failure this half exists for.
    #
    # The class does not always live in a file of its own name: VTMotionBlurConfiguration is carried by
    # VideoToolboxValue26.m, and asking for a VTMotionBlurConfiguration.o that the port never wrote would
    # make this half skip the one class it most needs to look at.
    OBJECT_OF = {cls: cls for cls in NS_UNAVAILABLE_CLASSES}
    OBJECT_OF["VTMotionBlurConfiguration"] = "VideoToolboxValue26"
    seen_objects = set()
    for cls in NS_UNAVAILABLE_CLASSES:
        for api, status in (("-[%s init]" % cls, "absent"), ("+[%s new]" % cls, "absent")):
            row = registry.get((api, "method"))
            if row is None:
                failures.append("no registry row at all for %s" % api)
            elif row["status"] != status:
                failures.append("%s is %s, and the SDK marks -init NS_UNAVAILABLE" % (api, row["status"]))
        unit = OBJECT_OF[cls]
        seen_objects.add(unit)
        obj = os.path.join(build, unit + ".o")
        if not os.path.exists(obj):
            failures.append("no compiled object for %s (expected %s.o)" % (cls, unit))
            continue
        found = own_methods(obj)
        if "init" in found["instance"]:
            failures.append("%s.o defines -init, and the SDK marks it NS_UNAVAILABLE" % cls)
        if "new" in found["class"]:
            failures.append("%s.o defines +new, and the SDK marks -init NS_UNAVAILABLE" % cls)

    # +isSupported is the property's own renamed accessor on all seven configuration classes: the
    # selectors must be `isSupported`, never a second `supported` added to satisfy a spelling.
    configuration_classes = ["VTFrameRateConversionConfiguration",
                             "VTLowLatencyFrameInterpolationConfiguration",
                             "VTLowLatencySuperResolutionScalerConfiguration", "VTOpticalFlowConfiguration",
                             "VTSuperResolutionScalerConfiguration", "VTTemporalNoiseFilterConfiguration"]
    for cls in configuration_classes:
        unit = OBJECT_OF[cls]
        seen_objects.add(unit)
        obj = os.path.join(build, unit + ".o")
        if not os.path.exists(obj):
            failures.append("no compiled object for %s (expected %s.o)" % (cls, unit))
            continue
        found = own_methods(obj)
        if "isSupported" not in found["class"]:
            failures.append("%s.o defines no +isSupported, which is what the SDK's getter= names" % cls)
        if "supported" in found["class"]:
            failures.append("%s.o carries +supported as well; the SDK declares one accessor, "
                            "getter=isSupported, and a second spelling is not that accessor" % cls)

    # The host's own answer about -init, held to the row's claim rather than to the header. The row says
    # Apple's class implements no -init of its own and that nothing raises; if the host ever starts
    # raising, or grows its own -init, the row's reason is no longer what it says it is and the check must
    # say so rather than let a stale claim stand.
    for cls, text in raised:
        failures.append("the host RAISES on %s: %s. The absent rows for this family claim it does not, "
                        "and that claim is now false" % (cls, text))
    for cls in NS_UNAVAILABLE_CLASSES:
        if cls not in unavailable:
            failures.append("the host reader printed no UNAVAILABLE line for %s" % cls)
            continue
        own_init, new_answers, init_answers, _width = unavailable[cls]
        if own_init != "own-init=0":
            failures.append("the host's %s implements -init of its own (own-init=1), so the absent row's "
                            "reason - that it inherits NSObject's - is no longer what it says" % cls)
        if new_answers != "+new-answers=1" or init_answers != "-init-answers=1":
            failures.append("the host's %s does not answer both +new and -init (%s, %s), so the absent "
                            "row's measured effect is no longer what it says"
                            % (cls, new_answers, init_answers))

    # processorSupported is API_UNAVAILABLE(ios) on three classes: the registry says absent, and the
    # three objects must not carry either spelling of the accessor.
    for cls in ("VTFrameRateConversionConfiguration", "VTMotionBlurConfiguration",
                "VTOpticalFlowConfiguration"):
        row = registry.get(("%s.processorSupported" % cls, "property"))
        if row is None or row["status"] != "absent":
            failures.append("%s.processorSupported is not an absent registry row" % cls)
        found = own_methods(os.path.join(build, OBJECT_OF[cls] + ".o"))
        for accessor in ("processorSupported", "isProcessorSupported"):
            if accessor in found["class"] or accessor in found["instance"]:
                failures.append("%s.o carries %s, and the SDK marks the property API_UNAVAILABLE(ios)"
                                % (cls, accessor))

    # The two methods this series adds to the other two classes, and the selectors they need.
    for cls, methods in OTHER_METHODS.items():
        obj = os.path.join(build, cls + ".o")
        if not os.path.exists(obj):
            failures.append("no compiled object for %s" % cls)
            continue
        found = own_methods(obj)
        for method in methods:
            is_class = method.startswith("supported")
            side = "class" if is_class else "instance"
            if method not in found[side]:
                failures.append("%s.o defines no %s%s" % (cls, "+" if is_class else "-", method))
            api = ("+[%s %s]" if is_class else "-[%s %s]") % (cls, method)
            row = registry.get((api, "method"))
            if row is None or row["status"] != "implemented":
                failures.append("no implemented registry row for %s" % api)

    # The eleven properties the two PROTOCOLS own, plus VTMotionBlurConfiguration.supported. The protocol
    # rows are the ones api-ledger.py cannot place at all - classify_property takes no protocols - so
    # this is where they are checked: the protocol object itself must carry the selectors SDK 26.2
    # declares on it, because that protocol metadata is what a conforming class inherits the
    # conformance from, and every conforming class must carry the accessor too.
    PROTOCOL_METHODS = {
        "VTFrameProcessorParameters": ["destinationFrame", "destinationFrames", "sourceFrame"],
        "VTFrameProcessorConfiguration": ["destinationPixelBufferAttributes", "frameSupportedPixelFormats",
                                         "isSupported", "maximumDimensions", "minimumDimensions",
                                         "nextFrameCount", "previousFrameCount",
                                         "sourcePixelBufferAttributes"],
    }
    # The protocols themselves carry no registry row, and they need none: check_registry reads a
    # protocol row as answered by a declaration a caller compiles against - a header this package
    # installs, the SDK, or the release - and CharonVideoToolbox.h declares both. What is checked here is
    # the OTHER half: that the accessor exists on every class that declares the conformance, because a
    # protocol row with no accessor behind it is a promise nothing keeps.
    for cls, methods in PROTOCOL_METHODS.items():
        for method in methods:
            api = "%s.%s" % (cls, method if method != "isSupported" else "supported")
            entry = registry.get((api, "property"))
            if entry is None:
                failures.append("no registry row for %s, which the protocol declares" % api)
            elif entry["status"] != "implemented":
                failures.append("%s is %s" % (api, entry["status"]))
    # Which protocol each class declares conformance to, as CharonVideoToolbox.h writes it: the six
    # configuration classes conform to VTFrameProcessorConfiguration and the six parameters classes to
    # VTFrameProcessorParameters. Asking a configuration class for -sourceFrame would be the check
    # asserting something the header does not say.
    CONFORMS = {
        "VTFrameRateConversionConfiguration": "VTFrameProcessorConfiguration",
        "VTLowLatencyFrameInterpolationConfiguration": "VTFrameProcessorConfiguration",
        "VTLowLatencySuperResolutionScalerConfiguration": "VTFrameProcessorConfiguration",
        "VTOpticalFlowConfiguration": "VTFrameProcessorConfiguration",
        "VTSuperResolutionScalerConfiguration": "VTFrameProcessorConfiguration",
        "VTTemporalNoiseFilterConfiguration": "VTFrameProcessorConfiguration",
        "VTFrameRateConversionParameters": "VTFrameProcessorParameters",
        "VTLowLatencyFrameInterpolationParameters": "VTFrameProcessorParameters",
        "VTLowLatencySuperResolutionScalerParameters": "VTFrameProcessorParameters",
        "VTOpticalFlowParameters": "VTFrameProcessorParameters",
        "VTSuperResolutionScalerParameters": "VTFrameProcessorParameters",
        "VTTemporalNoiseFilterParameters": "VTFrameProcessorParameters",
        "VTMotionBlurConfiguration": "VTFrameProcessorConfiguration",
        "VTMotionBlurParameters": "VTFrameProcessorParameters",
    }
    for cls, protocol in sorted(CONFORMS.items()):
        unit = OBJECT_OF.get(cls, cls)
        obj = os.path.join(build, unit + ".o")
        if not os.path.exists(obj):
            failures.append("no compiled object for %s (expected %s.o)" % (cls, unit))
            continue
        found = own_methods(obj)
        for method in PROTOCOL_METHODS[protocol]:
            if method not in found["instance"] and method not in found["class"]:
                failures.append("%s.o defines no %s, which %s - the protocol it declares conformance to -"
                                " carries in the built library" % (cls, method, protocol))

    # The HDR per-frame metadata session: the constant's string in the compiled object, and the three
    # functions as symbols. nm, not otool: these are C functions, and a C function has no ObjC method
    # list to read, so the only place its name lives is the symbol table.
    hdr = os.path.join(build, "VTHDRPerFrameMetadataGenerationSession18_0.o")
    if not os.path.exists(hdr):
        failures.append("no compiled object for the HDR per-frame metadata session")
    else:
        defined = subprocess.run(["nm", "-gU", hdr], check=True, capture_output=True,
                                 text=True).stdout.split()
        for symbol in ("_VTHDRPerFrameMetadataGenerationSessionGetTypeID",
                       "_VTHDRPerFrameMetadataGenerationSessionCreate",
                       "_VTHDRPerFrameMetadataGenerationSessionAttachMetadata",
                       "_kVTHDRPerFrameMetadataGenerationHDRFormatType_DolbyVision"):
            if symbol not in defined:
                failures.append("%s.o does not export %s" % (os.path.basename(hdr), symbol))
        if "DolbyVision" not in literal_strings(hdr):
            failures.append("%s.o carries no literal \"DolbyVision\", which is what the host's own "
                            "kVTHDRPerFrameMetadataGenerationHDRFormatType_DolbyVision holds"
                            % os.path.basename(hdr))
        for api in ("VTHDRPerFrameMetadataGenerationSessionGetTypeID()",
                    "VTHDRPerFrameMetadataGenerationSessionCreate()",
                    "VTHDRPerFrameMetadataGenerationSessionAttachMetadata()",
                    "kVTHDRPerFrameMetadataGenerationHDRFormatType_DolbyVision"):
            row = registry.get((api, "constant" if api.startswith("kVT") else "function"))
            if row is None or row["status"] != "implemented":
                failures.append("no implemented registry row for %s" % api)

    # What the host said about +isSupported, and what the port answers, side by side and asserted
    # against neither: this host is an M4 Pro and the port's releases are armv7, so the two numbers are
    # SUPPOSED to differ and a check that demanded they agree would be demanding a lie.
    print("supported (host=1 on this M4 Pro; the port answers NO because no armv7 release has the "
          "hardware, and that difference is the documented answer):")
    for cls in sorted(supported):
        print("  %-46s host=%s  port=NO" % (cls, supported[cls]))
    print("the host's own +new/-init on the NS_UNAVAILABLE classes: none of them implements -init, both "
          "answer, nothing raises, and the object that comes back is empty - which is why the rows are "
          "`absent` and the port's objects must not grow an -init of their own:")
    for cls in sorted(unavailable):
        own_init, new_answers, init_answers, width = unavailable[cls]
        if cls in NS_UNAVAILABLE_CLASSES:
            print("  %-46s %s %s %s empty=%s" % (cls, own_init, new_answers, init_answers, width))

    if failures:
        for failure in failures:
            print("FAIL " + failure)
        print("videotoolbox-frameprocessor: %d failure(s)" % len(failures))
        return 1
    print("videotoolbox-frameprocessor: OK - the domain string, %d codes, %d processor methods (and no"
          " -init, which Apple's class does not implement either), the"
          " protocol accessors on %d conforming classes, the HDR session's 3 functions and its measured"
          " constant, and %d NS_UNAVAILABLE classes agree with the host and with the registry"
          % (len(codes), len(PROCESSOR_METHODS), len(CONFORMS), len(NS_UNAVAILABLE_CLASSES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())