#!/usr/bin/env python3
"""The twenty-two fixtures the -string table in facts/PDFKit/Document11.md was measured on.

    make-text-fixtures.py <directory>

Every row of that table is generated here, so the table is reproducible and not a claim in a message
that scrolls away.  `tools/verify-table.sh` regenerates, asks the host through tools/host-string.m, and
diffs what came out against what the facts file says.

    row name | content stream | what the table is asking

  the four the first table was measured on
  kern-20  kern-50  kern-100  kern-150  kern-250  kern-500  kern-1000  kern-plus250
      a TJ kerning between the same two strings, from -20 to -1000 and one positive: where does a
      space start, does magnitude buy more than one, and does the sign matter
  td-x-only  td-small-y  td-y--0.4  td-y--14  td-y--40
      movement between two shows, in each axis and by magnitude
  op-TD-next-line  op-quote-operator  op-TD-star-between
      the other positioning and quoting operators
  size-6  size-12  size-24
      the same kerning at three font sizes: is the threshold relative to the em?
  op-Tm-set  op-TD-star-next-line  op-dquote-operator
      the three the reader rejects, kept in the table as the VOID cases they are

Every xref offset and the stream's /Length is measured from the object bytes, never typed.
"""
import os
import sys

FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

RANGE = b"BT /F1 12 Tf 72 720 Td"


def kern(value):
    return ("kern-%s" % (abs(value) if value < 0 else "plus%d" % value),
            RANGE + b" [(al) " + str(value).encode() + b" (pha)] TJ ET",
            "TJ kerning %+d" % value)


def td(operator, name, note):
    return (name,
            RANGE + b" (alpha) Tj " + operator + b" (beta) Tj ET",
            note)


def other(operator, name, note, leading):
    if leading:
        return (name, RANGE + b" " + operator + b" ET", note)
    return (name, RANGE + b" (alpha) Tj " + operator + b" (beta) Tj ET", note)


def size(points):
    return ("size-%d" % points,
            b"BT /F1 " + str(points).encode() + b" Tf 72 720 Td [(al) -100 (pha)] TJ ET",
            "kerning -100 at %dpt" % points)


CASES = [
    kern(-20), kern(-50), kern(-100), kern(-150), kern(-250), kern(-500), kern(-1000), kern(250),
    td(b"72 0 Td", "td-x-only", "x only"),
    td(b"0 -2 Td", "td-small-y", "small y"),
    td(b"0 -0.4 Td", "td-y--0.4", "y -0.4"),
    td(b"0 -14 Td", "td-y--14", "y -14"),
    td(b"0 -40 Td", "td-y--40", "y -40"),
    other(b"0 -14 TD", "op-TD-next-line", "TD next line", False),
    other(b"(alpha) '", "op-quote-operator", "the quote operator", True),
    other(b"0 -14 Td (beta) Tj T* (gamma) Tj", "op-TD-star-between", "T* between two shows", True),
    size(6), size(12), size(24),
    other(b"1 0 0 1 72 706 Tm 0 -14 Td", "op-Tm-set", "Tm set", True),
    other(b"0 -14 T*", "op-TD-star-next-line", "a leading T*", True),
    other(b'(alpha) "', "op-dquote-operator", "the double-quote operator", True),
]


def build(path, content):
    page = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        page,
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream",
        FONT,
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))                       # measured, never typed
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    start = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\nstartxref\n"
            + str(start).encode() + b"\n%%EOF\n")
    with open(path, "wb") as handle:
        handle.write(bytes(out))
    return content


def main():
    directory = sys.argv[1]
    os.makedirs(directory, exist_ok=True)
    for name, content, note in CASES:
        written = build(os.path.join(directory, name + ".pdf"), content)
        print("%s\t%s\t%s" % (name, written.decode("latin-1").strip(), note))


main()
