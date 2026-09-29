"""Checks availability_of() against a table READ BY HAND from the seventeen windows.

    VT_SDK=<an iPhoneOS*.sdk> python3 availability_test.py

The table below was written by reading the windows in .agent-work/runs/vtclass/avail-windows.txt, one
class at a time - NOT by running the function and recording what it said. That is the whole point: a
function checked against itself proves it agrees with itself. All seventeen declare ios(26.0), and the
line numbers are the ones the windows showed, so a change in the SDK's spelling moves the function away
from a table a person read.

The control deletes the availability macro from one header and requires the function to RAISE. A version
rule that cannot fail is a version rule that will quietly return the wrong release.
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util

spec = importlib.util.spec_from_file_location("vt_availability", os.path.join(HERE, "availability.py"))
availability = importlib.util.module_from_spec(spec)
spec.loader.exec_module(availability)
assert os.path.abspath(availability.__file__) == os.path.join(HERE, "availability.py"), \
    "loaded an availability.py that is not this one"

# (class, ios version) - read from the windows, by hand
TABLE = [
    ("VTFrameProcessor", "26.0"),
    ("VTFrameProcessorFrame", "26.0"),
    ("VTFrameProcessorOpticalFlow", "26.0"),
    ("VTFrameRateConversionConfiguration", "26.0"),
    ("VTFrameRateConversionParameters", "26.0"),
    ("VTLowLatencyFrameInterpolationConfiguration", "26.0"),
    ("VTLowLatencyFrameInterpolationParameters", "26.0"),
    ("VTLowLatencySuperResolutionScalerConfiguration", "26.0"),
    ("VTLowLatencySuperResolutionScalerParameters", "26.0"),
    ("VTMotionBlurConfiguration", "26.0"),
    ("VTMotionBlurParameters", "26.0"),
    ("VTOpticalFlowConfiguration", "26.0"),
    ("VTOpticalFlowParameters", "26.0"),
    ("VTSuperResolutionScalerConfiguration", "26.0"),
    ("VTSuperResolutionScalerParameters", "26.0"),
    ("VTTemporalNoiseFilterConfiguration", "26.0"),
    ("VTTemporalNoiseFilterParameters", "26.0"),
]


def headers(sdk):
    directory = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    return {os.path.basename(p): open(p).read() for p in sorted(glob.glob(os.path.join(directory, "*.h")))}


def main():
    sdk = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VT_SDK", "")
    if not sdk:
        sys.exit("availability_test.py: set VT_SDK to an iPhoneOS*.sdk")
    texts = headers(sdk)
    joined = "\n".join(texts.values())
    bad = []
    for name, wanted in TABLE:
        try:
            got, line = availability.availability_of(joined, name)
        except ValueError as error:
            bad.append("%s: %s" % (name, str(error).split("\n")[0]))
            continue
        if got != wanted:
            bad.append("%s: the header says ios %s and the hand-read table says %s" % (name, got, wanted))
        else:
            print("  %-48s ios %-5s from line %d" % (name, got, line))
    # THE CONTROL: one header with its availability macro renamed, and the function must refuse rather
    # than find some other API_AVAILABLE above it and report a version anyway.
    victim = [n for n in texts if "VTTemporalNoiseFilterConfiguration" in texts[n]]
    if not victim:
        bad.append("the control could not find a header to copy")
    else:
        broken = texts[victim[0]].replace("API_AVAILABLE(", "API_XAVAILABLE(", 1)
        try:
            availability.availability_of(broken, "VTTemporalNoiseFilterConfiguration")
            bad.append("the control did NOT raise: a header with its availability macro renamed still "
                       "resolved, so a class with no stated version would be given one")
        except ValueError:
            print("  control: a header with its API_AVAILABLE renamed raises, as it must")
    for line in bad:
        print("FAIL " + line)
    if bad:
        sys.exit(1)
    print("availability: %d of %d resolve, control raises" % (len(TABLE), len(TABLE)))


if __name__ == "__main__":
    main()
