#!/usr/bin/env python3
"""Fixtures with ANNOTATIONS, written with every xref offset and /Length measured.

    make-annotation-fixtures.py <directory>

The PDFKit annotation work needs a page that CARRIES annotations, and the fixtures the other two
slices wrote do not: their pages name no /Annots at all.  Three shapes, because the members divide by
what the annotation has:

  annot-text       a text annotation with a /Rect, /Contents, /T, /M, /C, /Border and /F
  annot-free       a link annotation with a /Rect, /Contents, /Border and /F and NOTHING else - the
                   members that read an absent key are the interesting ones
  annot-two        a page carrying TWO annotations, so a count and an index can be read

Every offset and length below is measured from the object bytes as they are written.
"""
import os
import sys

FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
TEXT = b"BT /F1 12 Tf 72 720 Td (annotated) Tj ET\n"


def annot(kind, extra):
    body = b"<< /Type /Annot /Subtype /" + kind
    for key, value in extra:
        body += b" /" + key + b" " + value
    return body + b" >>"


FULL = [
    (b"Rect", b"[100 600 300 650]"),
    (b"Contents", b"(a note on the page)"),
    (b"T", b"(the annotator)"),
    (b"M", b"(D:20260930000000Z)"),
    (b"C", b"[1 0 0]"),
    (b"Border", b"[0 0 1]"),
    (b"F", b"4"),
    (b"NM", b"(mark-1)"),
]
BARE = [
    (b"Rect", b"[20 700 60 720]"),
    (b"Contents", b"(bare)"),
]


def build(path, annotations):
    """1 catalog, 1 pages, 1 page, the content stream, the annotations, the font."""
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /Parent 1 0 R >>",
        None,                                    # the page, filled in once the numbers are known
        b"<< /Length " + str(len(TEXT)).encode() + b" >>\nstream\n" + TEXT + b"\nendstream",
    ]
    refs = []
    for body in annotations:
        objects.append(body)
        refs.append(len(objects))               # 1-based object numbers
    font_number = len(objects) + 1
    objects.append(FONT)
    annots = b" ".join(b"%d 0 R" % n for n in refs)
    objects[2] = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [" + annots +
                  b"] /Resources << /Font << /F1 %d 0 R >> >> /Contents 4 0 R >>" % font_number)
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))               # measured
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    start = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\nstartxref\n"
            + str(start).encode() + b"\n%%EOF\n")
    with open(path, "wb") as handle:
        handle.write(bytes(out))
    return len(objects)


def main():
    directory = sys.argv[1]
    os.makedirs(directory, exist_ok=True)
    shapes = [
        ("annot-text.pdf", [annot(b"Text", FULL)]),
        ("annot-free.pdf", [annot(b"Link", BARE)]),
        ("annot-two.pdf", [annot(b"Text", FULL), annot(b"Link", BARE)]),
        # HELD-OUT rects, and two more subtypes.  The /Text icon rule - a 24x24 note at
        # (minX, maxY-24) - was derived from ONE rect; it is not a rule until it is right on a rect it
        # was not fitted to, and not a PDFKit-wide rule until a subtype that is not a note answers
        # something else.
        ("annot-text-holdout.pdf", [annot(b"Text", [(b"Rect", b"[10 20 500 90]")] + FULL[1:])]),
        ("annot-link-wide.pdf", [annot(b"Link", [(b"Rect", b"[0 0 600 700]")] + BARE[1:])]),
        ("annot-square.pdf", [annot(b"Square", [(b"Rect", b"[40 40 240 140]"),
                                               (b"Contents", b"(a square)"), (b"F", b"4")])]),
        ("annot-highlight.pdf", [annot(b"Highlight", [(b"Rect", b"[0 0 200 30]"),
                                                    (b"QuadPoints", b"[0 30 200 30 0 0 200 0]"),
                                                    (b"Contents", b"(highlighted)"), (b"F", b"4")])]),
        # FLAGS, held out.  Every other shape writes /F 4, so they all answer shouldDisplay=1 and
        # shouldPrint=1, and "always YES" fits that data exactly as well as "mirrors the bit" does.  The
        # two below are the only fixtures that can tell those two rules apart: /F 0 clears Print,
        # /F 2 is Hidden alone.
        ("annot-noprint.pdf", [annot(b"Square", [(b"Rect", b"[40 40 140 140]"),
                                                (b"Contents", b"(no flags)"), (b"F", b"0")])]),
        ("annot-hidden.pdf", [annot(b"Square", [(b"Rect", b"[40 40 140 140]"),
                                               (b"Contents", b"(hidden)"), (b"F", b"2")])]),
    ]
    for name, annotations in shapes:
        count = build(os.path.join(directory, name), annotations)
        print("  wrote %-16s %d objects, %d annotation(s)" % (name, count, len(annotations)))


main()
