"""WHICH iOS RELEASE A STRING CONSTANT ARRIVED IN, read from the SDK's own header line.

    VT_SDK=<an iPhoneOS*.sdk> python3 availability_test.py

VideoToolbox declares its 135 string constants with the availability ON THE DECLARATION'S OWN LINE:

    VTCompressionProperties.h:1076
    VT_EXPORT const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha	API_AVAILABLE(macos(10…

so the rule the seventeen CLASSES need - the nearest API_AVAILABLE ABOVE the declaration - matches none
of them, and a reader built that way reports every constant as unstated. It is the opposite order for
the two subjects, and both orders have to be tried: the line's own availability first, and the lines
above it only when the line carries none.

This is the fourth time in this series that the same question has had two right answers, and the third
time the wrong one came from a rule written for a neighbouring subject. That is why there is a control
for BOTH shapes here, and a decoy: a reader that can only answer one shape is a reader that will
quietly say "unstated" about the other.
"""
import glob
import os
import re
import sys

AVAILABLE = re.compile(r'API_AVAILABLE\((?:[^()]|\([^()]*\))*?ios\((\d+(?:\.\d+)*)\s*\)')
DECLARATION = re.compile(r'^\s*(?:VT_EXPORT\s+|extern\s+)?const\s+CFStringRef\s+(\w+)')


def header_texts(sdk):
    directory = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    for path in sorted(glob.glob(os.path.join(directory, "*.h"))):
        yield path, open(path).read()


def release_near(lines, index):
    """(release, line number) from a declaration at `index`, trying the three shapes in order.

    ONE implementation. The test used to own a second reader with the older two-shape logic, so the
    shape the production paths had just gained was exactly the shape the test could not do - the same
    two-implementations failure that hid the class/constant difference in the first place, this time
    inside one file.
    """
    own = AVAILABLE.search(lines[index])
    if own:
        return own.group(1), index + 1
    if index + 1 < len(lines):          # a declaration can end in a // comment, availability after it
        below = AVAILABLE.search(lines[index + 1])
        if below:
            return below.group(1), index + 2
    for back in range(index - 1, max(-1, index - 11), -1):
        above = AVAILABLE.search(lines[back])
        if above:
            return above.group(1), back + 1
    return None, index + 1


def constant_availability(sdk, name):
    """(release, file, line) for one constant, or None when the header states none.

    The declaration's OWN line is asked first, and the ten lines above it only if that line carries no
    availability - which is the shape a class declaration has, and the shape the earlier reader was
    written for.
    """
    for path, text in header_texts(sdk):
        lines = text.split("\n")
        for index, line in enumerate(lines):
            found = DECLARATION.match(line)
            if not found or found.group(1) != name:
                continue
            release, line_no = release_near(lines, index)
            return release, os.path.basename(path), line_no
            return None, os.path.basename(path), index + 1
    return None


def all_constants(sdk):
    """Every constant VideoToolbox declares, with what the header says and where."""
    out = {}
    for path, text in header_texts(sdk):
        lines = text.split("\n")
        for index, line in enumerate(lines):
            found = DECLARATION.match(line)
            if not found:
                continue
            release, _line_no = release_near(lines, index)
            out[found.group(1)] = (release, os.path.basename(path), index + 1)
    return out


# The two shapes, written out as text so the test does not need an SDK to have them, and a DECOY that
# looks like a declaration and states nothing, so a reader that invents a release fails.
SAMPLES = {
    "own line": (
        "VT_EXPORT const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha\t"
        "API_AVAILABLE(macos(10.10), ios(2.0), tvos(9.0))",
        "kVTAlphaChannelMode_PremultipliedAlpha", "2.0"),
    "line below": (
        "VT_EXPORT const CFStringRef kVTCompressionPropertyKey_PreserveDynamicHDRMetadata // CFBoolean, Wr…\n"
        "\t\t\t\t\t\t\tAPI_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))",
        "kVTCompressionPropertyKey_PreserveDynamicHDRMetadata", "14.0"),
    "line above": (
        "API_AVAILABLE(macos(15.4), ios(26.0), tvos(26.0), visionos(26.0)) API_UNAVAILABLE(watchos)\n"
        "VT_EXPORT const CFStringRef kVTFrameRateConversionQualityPrioritizationNormal",
        "kVTFrameRateConversionQualityPrioritizationNormal", "26.0"),
}
DECOY = ("VT_EXPORT const CFStringRef kVTCharonDecoyNameThatIsNotInAnyHeader\t", "kVTCharonDecoyNameThatIsNotInAnyHeader", None)


def read_line_shape(text, name):
    """The TEST calls the production reader. It does not own one."""
    lines = text.split("\n")
    for index, line in enumerate(lines):
        found = DECLARATION.match(line)
        if found and found.group(1) == name:
            return release_near(lines, index)[0]
    return None


def main():
    bad = []
    for label, (text, name, wanted) in SAMPLES.items():
        got = read_line_shape(text, name)
        if got is None and wanted is not None:
            bad.append("%s shape: read nothing, so the fallback was never reached" % label)
        if got != wanted:
            bad.append("%s shape: read %r, wanted %r" % (label, got, wanted))
        else:
            print("  %-10s shape read: %s" % (label, got))
    text, name, wanted = DECOY
    got = read_line_shape(text, name)
    if got != wanted:
        bad.append("the decoy read %r; a reader that invents a release is the failure this is for" % got)
    else:
        print("  decoy      read: %r, and it invents nothing" % got)

    sdk = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VT_SDK", "")
    if sdk:
        stated = all_constants(sdk)
        print("  %d constants declared by the headers; %d state a release"
              % (len(stated), sum(1 for v in stated.values() if v[0])))
    for line in bad:
        print("FAIL " + line)
    if bad:
        return 1
    print("constant availability: both shapes read, and the decoy invents nothing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
