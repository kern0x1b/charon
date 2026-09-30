#!/usr/bin/env python3
"""The three box fixtures, written with every offset and length computed rather than typed.

    make-box-pdfs.py <directory>

A page that names every box, one with no /CropBox at all, and one rotated 90 - the three cases that
decide what -[PDFPage boundsForBox:] answers.  The content stream is `q Q`, a valid one: these fixtures
are about geometry, and a hand-built xref with typed offsets is how the last attempt produced files
whose /Contents the reader could not hand back.

    /Contents is an indirect reference, so the reader resolves it through the xref; every offset here
    is measured from the object bytes as they are written, and /Length is the byte count of the stream
    itself, so nothing depends on arithmetic typed by hand.
"""
import os
import sys

TEXT = b"q Q"          # a valid content stream: these fixtures are read for their boxes
FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"


def build(path, crop, boxes, rotate):
    page = b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]"
    if crop:
        page += b" /CropBox [0 0 300 400]"
    if boxes:
        page += b" /BleedBox [10 10 290 390] /TrimBox [20 20 280 380] /ArtBox [30 30 270 370]"
    if rotate:
        page += b" /Rotate 90"
    page += b" /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        page,
        b"<< /Length " + str(len(TEXT)).encode() + b" >>\nstream\n" + TEXT + b"\nendstream",
        FONT,
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))                      # measured, never typed
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    start_xref = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n"
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset          # ten digits, from the measured offset
    out += (b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\nstartxref\n"
            + str(start_xref).encode() + b"\n%%EOF\n")
    with open(path, "wb") as handle:
        handle.write(bytes(out))
    return len(out), offsets


def main():
    directory = sys.argv[1]
    os.makedirs(directory, exist_ok=True)
    made = [("box-all.pdf", True, True, False), ("box-nocrop.pdf", True, False, False),
            ("box-rotated.pdf", True, True, True)]
    for name, crop, boxes, rotate in made:
        size, offsets = build(os.path.join(directory, name), crop, boxes, rotate)
        print(f"  wrote {name}: {size} bytes, object offsets {offsets}")


main()
