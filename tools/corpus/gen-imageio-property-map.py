#!/usr/bin/env python3
"""Measure the HOST's ImageIO property-to-tag table and print it as C rows for
packages/a/apple-backports/Graphics/ImageIOMetadata7.m.

    xcrun clang -w -fobjc-arc -Itests/backports/host/imageio-metadata \\
        tests/backports/host/imageio-metadata/property-table.m \\
        -framework ImageIO -framework Foundation -framework CoreServices -o /tmp/property-table
    python3 tools/corpus/gen-imageio-property-map.py /tmp/property-table > /tmp/property-map.txt

WHAT IT MEASURES, so a reader does not take the output on trust: for every (dictionary, property) pair
the SDK's CGImageProperties.h declares, one process asks the host's own
CGImageMetadataSetValueMatchingImageProperty to write a value for it and reads the tag it wrote back out
of the tree. The tag's namespace, prefix and name are the row, and nothing in this script decides what a
property maps to - that is the host's answer. A pair the host answers false for gets no row, which is the
161 of 518 the header itself describes: "Not all dictionaries and properties are supported at this time."

It prints the rows and the counts; it does not write any file in the tree. The check that the port's table
answers what the host answers is tests/backports/host/imageio-metadata/table.sh and the differential in
run.sh, which compares both functions pair by pair.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(HERE, "..", ".."))
HARNESS = os.path.join(WT, "tests/backports/host/imageio-metadata")

# The ten public namespaces ImageIO declares, and the constant the port names each by. The URI is what the
# measurement prints; this table only says which of the ten the URI is, so a row reads as constants.
# The ten public namespaces ImageIO declares: what the measurement prints for each, and the constant the
# port names it by. The table below only says which of the ten a URI is, so a row reads as constants; a URI
# that is not one of them stops the generator rather than being carried as a string literal.
NAMESPACES = {
    "http://ns.adobe.com/exif/1.0/": ("Exif", "exif", "Exif"),
    "http://ns.adobe.com/exif/1.0/aux/": ("ExifAux", "aux", "ExifAux"),
    "http://cipa.jp/exif/1.0/": ("ExifEX", "exifEX", "ExifEX"),
    "http://purl.org/dc/elements/1.1/": ("DublinCore", "dc", "DublinCore"),
    "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/": ("IPTCCore", "Iptc4xmpCore", "IPTCCore"),
    "http://iptc.org/std/Iptc4xmpExt/2008-02-29/": ("IPTCExtension", "Iptc4xmpExt", "IPTCExtension"),
    "http://ns.adobe.com/photoshop/1.0/": ("Photoshop", "photoshop", "Photoshop"),
    "http://ns.adobe.com/tiff/1.0/": ("TIFF", "tiff", "TIFF"),
    "http://ns.adobe.com/xap/1.0/": ("XMPBasic", "xmp", "XMPBasic"),
    "http://ns.adobe.com/xap/1.0/rights/": ("XMPRights", "xmpRights", "XMPRights"),
}

PAIRS = os.path.join(HARNESS, "property-pairs-all.h")


def measured_pairs(binary):
    """[(index, dictionary symbol, property symbol, dictionary string, property string, stdout)]"""
    source = open(PAIRS).read()
    symbols = re.findall(r"out\[\d+\]\.dictionary = (\w+); out\[\d+\]\.property = (\w+);", source)
    out = []
    for index, (dictionary, prop) in enumerate(symbols):
        run = subprocess.run([binary, str(index)], capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit("pair %d (%s %s) exited %d: the host did not answer"
                     % (index, dictionary, prop, run.returncode))
        printed = re.search(r"^# pair\t(.+?)\t(.+)$", run.stdout, re.M)
        if not printed:
            sys.exit("pair %d printed no '# pair' line" % index)
        out.append((index, dictionary, prop, printed.group(1), printed.group(2), run.stdout))
    return out


def row_of(stdout):
    """The row's (namespace, prefix, name) from one pair's output, or None where the host maps nothing."""
    ok = re.search(r"^set\t(\d)$", stdout, re.M)
    if not ok or ok.group(1) != "1":
        return None
    tag = re.search(r"^set\t0\ttag\t(\S+)\t(\S+)\t(\S+)\t(\d+)$", stdout, re.M)
    if not tag:
        sys.exit("a pair answered set true and printed no tag line:\n" + stdout)
    return tag.group(1), tag.group(2), tag.group(3), tag.group(4)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    binary = sys.argv[1]
    rows = []
    unmapped = 0
    for _, dictionary, prop, dictionary_value, property_value, stdout in measured_pairs(binary):
        found = row_of(stdout)
        if not found:
            unmapped += 1
            continue
        uri, prefix, name, kind = found
        if uri not in NAMESPACES:
            sys.exit("the host mapped a property into %s, which is not one of the ten public namespaces" % uri)
        namespace, space_prefix, prefix_constant = NAMESPACES[uri]
        if prefix != space_prefix:
            sys.exit("%s: the host answered prefix %s where the namespace %s declares %s"
                     % (prop, prefix, uri, space_prefix))
        if kind != "1":
            sys.exit("a tag written from a CFString is of type %s, not String" % kind)
        rows.append((dictionary_value, property_value, uri, prefix, name, dictionary, prop))
    for dictionary_value, property_value, uri, prefix, name, dictionary, prop in rows:
        print('    { "%s", "%s",\n      "%s", "%s", "%s" },  // %s'
              % (dictionary_value, property_value, uri, prefix, name, prop))
    sys.stderr.write("%d pairs measured, %d rows, %d the host does not map\n" % (len(rows) + unmapped, len(rows), unmapped))


if __name__ == "__main__":
    main()