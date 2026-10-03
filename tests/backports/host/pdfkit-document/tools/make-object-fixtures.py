#!/usr/bin/env python3
"""Fixtures whose pages carry the DICTIONARY OBJECTS, written with every xref offset and /Length measured.

    make-object-fixtures.py <directory>

The annotation fixtures write /Rect, /Contents, /T, /M, /C, /Border and /F - one annotation's flat
keys.  The classes that read a nested dictionary or an array of dictionaries need fixtures whose
dictionaries the port and the host both parse rather than one that both copy out by name:

  border-*        /Border as [hR vR lw], which is the three-number array of PDF 1.7 Table 164, and
                  the /BS dictionary beside it, so -style and -dashPattern have something to read
  mk-*            /MK, the appearance characteristics dictionary of PDF 1.7 Table 8.40
  dest-*          /Dest as [pageRef /XYZ left top zoom] and as [pageRef /Fit], plus a named /Dest
                  object, because a destination is an ARRAY in one spelling and a dictionary in
                  another and the port has to answer both
  act-*           /A, the action dictionary of PDF 1.7 Table 8.44, one fixture per /S the port reads
  outline-*       /Outlines and the /First /Next /Prev /Count tree, because an outline is a tree and
                  every member the port answers is read off a parent or a sibling link

Every offset and length below is measured from the object bytes as they are written.
"""
import os
import sys

FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
TEXT = b"BT /F1 12 Tf 72 720 Td (outlined) Tj ET\n"


def annot(kind, extra, name=None):
    """One annotation dictionary as BYTES.  `name` writes the /NM of PDF 1.7 Table 8.16, the unique name,
    which is what lets a reading be keyed by the annotation it belongs to rather than by a position."""
    body = b"<< /Type /Annot /Subtype /" + kind
    for key, value in extra:
        body += b" /" + key + b" " + value
    if name is not None:
        body += b" /NM (" + name.encode("ascii") + b")"
    return body + b" >>"


def build(path, annotations, extra_objects=(), catalog_extra=b"", pages_extra=b"", page_extra=b"",
          page_count=1):
    """1 catalog, 1 pages, `page_count` pages, the content streams, the annotations, the font.

    `extra_objects` are the indirect objects the catalog or a page needs - the /Outlines tree, a
    /Dest dictionary - and each is written AFTER the annotations, so their numbers are known here.
    Every reference the caller writes has to be written with those numbers in mind, which is why the
    caller passes bodies built from `n` below rather than a fixed number.
    """
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R" + catalog_extra + b" >>",   # 1 0 obj
        None,                                     # 2 0 obj, the pages tree, filled in below
    ]
    # the pages are 3 0 obj onwards, so their 1-based numbers are known before anything references
    # them; the content streams follow them, then the annotations, the font, and `extra_objects`.
    for _ in range(page_count):
        objects.append(None)                     # each page, filled in below
    for _ in range(page_count):
        objects.append(b"<< /Length " + str(len(TEXT)).encode() + b" >>\nstream\n" + TEXT
                       + b"\nendstream")
    annotation_numbers = []
    for body in annotations:
        objects.append(body)
        annotation_numbers.append(len(objects))
    font_number = len(objects) + 1
    objects.append(FONT)
    extra_numbers = {}
    for name, body in extra_objects:
        extra_numbers[name] = len(objects)
        objects.append(body)

    annots = b" ".join(b"%d 0 R" % n for n in annotation_numbers)
    contents = [b"%d 0 R" % (3 + page_count + i) for i in range(page_count)]
    resources = b"<< /Font << /F1 %d 0 R >> >>" % font_number
    kids = b" ".join(b"%d 0 R" % (3 + i) for i in range(page_count))
    # The /Pages node carries NO /Parent, and that is right: the catalog is the parent of the page tree
    # in the sense that the TRAILER's /Root names it, and a real PDF does not put /Parent on the root
    # /Pages node.  An earlier version of this file added one, so that -outlineRoot could reach the
    # catalog by walking /Parent up from a page - and that walk was only ever working because of this
    # line.  The catalog now comes from CGPDFDocumentGetCatalog, which is in the release, so the line is
    # gone and the fixtures are ordinary documents again.
    objects[1] = (b"<< /Type /Pages /Kids [" + kids + b"] /Count " + str(page_count).encode()
                  + pages_extra + b" >>")
    for i in range(page_count):
        objects[2 + i] = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots ["
                          + annots + b"] /Resources " + resources + b" /Contents " + contents[i]
                          + page_extra + b" >>")
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    start = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\nstartxref\n"
            + str(start).encode() + b"\n%%EOF\n")
    with open(path, "wb") as handle:
        handle.write(bytes(out))
    return len(objects), extra_numbers


# ---- /Border: the three-number array of PDF 1.7 Table 164, and the /BS dictionary beside it -----
#
# The host's PDFBorder has three members and the array has three numbers, so the mapping looks
# obvious and is NOT assumed: what is measured is which element answers -lineWidth, whether the two
# corner radii are read at all, and where -style and -dashPattern come from - /BS or the array.
def square(extra):
    return annot(b"Square", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(square)"), (b"F", b"4")]
                 + extra)


BORDER_PLAIN = square([(b"Border", b"[0 0 3]")])
BORDER_RADII = square([(b"Border", b"[5 7 2]")])
BORDER_ZERO = square([(b"Border", b"[0 0 0]")])
BORDER_NEGATIVE = square([(b"Border", b"[0 0 -2.5]")])
BORDER_BS = square([(b"Border", b"[0 0 1]"),
                    (b"BS", b"<< /Type /Border /W 4 /S /D /D [3 2] >>")])
# a /Border with ONE number and one with FOUR, so "answers the third element" and "answers the last"
# are told apart by the fixtures rather than by reading the port's own array walk.
BORDER_SHORT = square([(b"Border", b"[0 0]")])
BORDER_LONG = square([(b"Border", b"[1 2 3 4]")])
BORDER_NONE = square([])
BORDER_LINK = annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"Contents", b"(link)"), (b"F", b"4")])

# The /BS /S name, one fixture per name PDF 1.7 Table 8.11 lists and per name it does not: the enum
# PDFBorderStyle declares is solid 0, dashed 1, beveled 2, inset 3, underline 4, and reading the name
# as its ORDINAL would fit the first two.  The other three are what tell an ordinal from a table.
for _name in (b"S", b"D", b"B", b"I", b"U", b"Q"):
    globals()["BS_" + _name.decode()] = square([(b"BS", b"<< /S /" + _name + b" /W 2 >>")])
# a dash pattern with a SOLID style: is -dashPattern read from /D or only when /S says dashed?
BS_DASH_SOLID = square([(b"BS", b"<< /S /S /W 2 /D [4 1] >>")])
# /BS with a style but no /W and no /Border: the default line width is a fact, not a guess
BS_NO_WIDTH = square([(b"BS", b"<< /S /I >>")])
# /BS with a width but no /S, and /Border's third element present: which of the two answers -lineWidth
BS_WIDTH_ONLY = square([(b"Border", b"[0 0 7]"), (b"BS", b"<< /W 5 >>")])
# and the other way round: a /BS with a STYLE and no /W beside a /Border that has a third element, which
# is the fixture that says whether /Border's third element is the fallback for a /BS that has no /W
BS_STYLE_ONLY = square([(b"Border", b"[0 0 9]"), (b"BS", b"<< /S /D /D [4 4] >>")])
# a dash pattern that is NOT the default: a dashed border with no /D answers [3 2], so only a /D the
# reader demonstrably takes can tell "reads /D" from "answers a default"
BS_DASH_CUSTOM = square([(b"BS", b"<< /S /D /W 2 /D [7 5] >>")])
# a /D that is not an array, and a /W that is not a number: the reader has to refuse both, not coerce
BS_DASH_STRING = square([(b"BS", b"<< /S /D /W 2 /D (not an array) >>")])
BS_WIDTH_STRING = square([(b"BS", b"<< /S /D /W (not a number) >>")])
# an absent /Border is nil for these subtypes and a default for the geometry ones, so the two rules
# "always a border" and "a /Border in the file makes one" are told apart by putting a /Border in a
# file whose subtype answers nil without one
BORDER_ON_NONTYPE = [
    annot(b"Highlight", [(b"Rect", b"[0 0 200 30]"), (b"Contents", b"(highlight)"), (b"F", b"4"),
                         (b"Border", b"[0 0 6]")]),
    annot(b"Text", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(text)"), (b"F", b"4"),
                    (b"Border", b"[0 0 6]")]),
    annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"Contents", b"(link)"), (b"F", b"4"),
                    (b"Border", b"[0 0 6]")]),
    annot(b"Stamp", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(stamp)"), (b"F", b"4"),
                     (b"Border", b"[0 0 6]")]),
    annot(b"Popup", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(popup)"), (b"F", b"4"),
                     (b"Border", b"[0 0 6]")]),
]
# and a /BS with no /Border on a subtype that answers nil without one, so "a /BS in the file makes one"
# is measured on its own rather than inferred from the /Border case
BS_ON_NONTYPE = [annot(b"Highlight", [(b"Rect", b"[0 0 200 30]"), (b"Contents", b"(highlight)"),
                                      (b"F", b"4"), (b"BS", b"<< /W 6 /S /D >>")])]

# the corner radii alone, with no third element: [5 7] answers 1.0 like [0 0] does, which is the
# default, so this is a holdout on the "third element" rule rather than a new rule
BORDER_RADII_ONLY = square([(b"Border", b"[5 7]")])

# ---- the absent /Border, one fixture per subtype -------------------------------------------
#
# /Square with no /Border answers a DEFAULT border and /Link with none answers nil (measured), so
# "a missing /Border is nil" and "a missing /Border is the default" both fit that pair.  Every subtype
# the header names gets its own fixture, because the answer is what decides the port's own rule.
for _kind in (b"Text", b"FreeText", b"Line", b"Circle", b"Highlight", b"Underline", b"StrikeOut",
              b"Ink", b"Stamp", b"Popup"):
    globals()["NOBORDER_" + _kind.decode()] = annot(
        _kind, [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(no border)"), (b"F", b"4")])
# a /Widget, and a /Widget with a field name: measured to differ, so the pair is here rather than a
# rule the reader has to guess at
NOBORDER_Widget = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn")])
NOBORDER_WidgetT = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                                    (b"T", b"(a field)")])
NOBORDER_WidgetBG = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                                      (b"MK", b"<< /BG [1 0 0] >>")])
NOBORDER_WidgetBC = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                                      (b"MK", b"<< /BC [0 0 1] >>")])
NOBORDER_WidgetBCgray = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                                          (b"FT", b"/Btn"), (b"MK", b"<< /BC [1] >>")])
NOBORDER_WidgetEmptyBC = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                                           (b"FT", b"/Btn"), (b"MK", b"<< /BC [] >>")])
# The SKIPPED shapes, on one fixture, so the rule in PDFPage11.m has its own fixture rather than being
# discovered by the border fixtures: the host drops an annotation with no /Rect whatever its subtype,
# and drops a /Line with a /Rect and no /L, and keeps a /Widget with no /FT.
DROPS = [
    annot(b"Line", [(b"Contents", b"(Line no L)")]),
    annot(b"Line", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(Line L)"),
                    (b"L", b"[40 40 240 140]")]),
    annot(b"Line", [(b"Contents", b"(Line L no Rect)"), (b"L", b"[40 40 240 140]")]),
    annot(b"Square", [(b"Contents", b"(Square no Rect)")]),
    annot(b"Text", [(b"Contents", b"(Text no Rect)")]),
    annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"Contents", b"(Widget no FT)")]),
    annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"Contents", b"(Widget FT)"), (b"FT", b"/Tx")]),
    annot(b"Popup", [(b"Contents", b"(Popup no Rect)")]),
    annot(b"Ink", [(b"Contents", b"(Ink no InkList)")]),
    annot(b"Circle", [(b"Contents", b"(Circle no Rect)")]),
    annot(b"FreeText", [(b"Contents", b"(FreeText no Rect)")]),
    annot(b"Stamp", [(b"Contents", b"(Stamp no Rect)")]),
    annot(b"Link", [(b"Contents", b"(Link no Rect)")]),
]

# a /Line needs an /L before the host keeps it: with only a /Rect it is dropped from -annotations, so
# the geometry subtypes would be measured on one member fewer than the header names
NOBORDER_LineL = annot(b"Line", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(line)"), (b"F", b"4"),
                                 (b"L", b"[40 40 240 140]")])
NOBORDER_CircleL = annot(b"Circle", [(b"Rect", b"[40 40 240 140]"), (b"Contents", b"(circle)"),
                                     (b"F", b"4")])
NOBORDER_WidgetTm = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                                      (b"Tm", b"(label)")])

# ---- /MK: the appearance characteristics dictionary of PDF 1.7 Table 8.40 --------------------
MK_FULL = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"T", b"(a field)"),
                            (b"MK", b"<< /BG [1 0 0] /BC [0 0 1] /R 90 /CA (caption) /RC (rollover)"
                                    b" /AC (down) >>"),
                            (b"FT", b"/Btn"), (b"Tm", b"(label)")])
MK_BARE = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                            (b"MK", b"<< /CA (only a caption) >>"), (b"FT", b"/Btn")])
MK_NONE = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn")])
# every colour spelling PDF 1.7 Table 8.40 lists, on their own key: [0] is no colour, [1] is gray,
# [3] is RGB and [4] is CMYK, and a two-element array is neither of those
MK_GRAY = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                            (b"MK", b"<< /BG [0.5] /BC [0] >>"), (b"FT", b"/Btn")])
MK_CMYK = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                            (b"MK", b"<< /BG [0.1 0.2 0.3 0.4] >>"), (b"FT", b"/Btn")])
MK_NONE_C = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                              (b"MK", b"<< /BG [0 0 0 0] /BC [1] >>"), (b"FT", b"/Btn")])
MK_TWO = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                           (b"MK", b"<< /BG [1 0] /BC [0.25 0.5] >>"), (b"FT", b"/Btn")])
# a rotation that is not an integer, and a key of the wrong type
MK_ROT_REAL = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                                 (b"MK", b"<< /R 90.5 /CA 7 >>"), (b"FT", b"/Btn")])
MK_R_ZERO = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"),
                              (b"MK", b"<< /R 0 >>"), (b"FT", b"/Btn")])


# ---- the /BC component count, which is what decides a widget's border ------------------------
#
# PDF 1.7 Table 8.40 gives a colour array four spellings: no components, one (gray), three (RGB) and
# four (CMYK).  A /BC that is none of those leaves the widget with no border colour and so with no
# border - measured, and the widget-with-bc set above is what a two-component /BC broke.
BC_CMYK = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                            (b"MK", b"<< /BC [0 0 0 1] >>")])
BC_STRING = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                              (b"MK", b"<< /BC (a string) >>")])
BC_NUMBER = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                              (b"MK", b"<< /BC 0.5 >>")])
BC_RGB = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                           (b"MK", b"<< /BC [0.25 0.5 0.75] >>")])

# ---- a /Popup and the print flag, and a /Widget and the name keys ------------------------------
#
# Both of these are not this family's rows - -shouldPrint and -userName are main's - and both were
# found by the fixtures above: the port read the format's rules and the host does not, and a
# differential that ignored the difference would be a comparison that cannot fail.  So the fixtures
# that find them are here rather than removed.
POPUP_F4 = annot(b"Popup", [(b"Rect", b"[40 40 140 140]"), (b"F", b"4"), (b"Contents", b"(f4)")])
POPUP_F0 = annot(b"Popup", [(b"Rect", b"[40 40 140 140]"), (b"F", b"0"), (b"Contents", b"(f0)")])
POPUP_F2 = annot(b"Popup", [(b"Rect", b"[40 40 140 140]"), (b"F", b"2"), (b"Contents", b"(f2)")])
POPUP_NOF = annot(b"Popup", [(b"Rect", b"[40 40 140 140]"), (b"Contents", b"(no F)")])
SQUARE_F4 = annot(b"Square", [(b"Rect", b"[40 40 140 140]"), (b"F", b"4"), (b"Contents", b"(square f4)")])
STAMP_F4 = annot(b"Stamp", [(b"Rect", b"[40 40 140 140]"), (b"F", b"4"), (b"Contents", b"(stamp f4)")])

WIDGET_T = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Btn"),
                             (b"T", b"(T only)"), (b"MK", b"<< /BC [0 0 1] >>")])
WIDGET_T_NOFT = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"T", b"(T no FT)"),
                                  (b"MK", b"<< /BC [0 0 1] >>")])
WIDGET_T_TX = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Tx"),
                                (b"T", b"(T tx)"), (b"MK", b"<< /BC [0 0 1] >>")])
WIDGET_TU_TX = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Tx"),
                                 (b"TU", b"(TU tx)"), (b"MK", b"<< /BC [0 0 1] >>")])
WIDGET_NO_T = annot(b"Widget", [(b"Rect", b"[40 40 140 70]"), (b"F", b"4"), (b"FT", b"/Tx"),
                                (b"MK", b"<< /BC [0 0 1] >>")])
SQUARE_T = annot(b"Square", [(b"Rect", b"[40 40 140 140]"), (b"F", b"4"), (b"T", b"(square T)"),
                             (b"MK", b"<< /BC [0 0 1] >>")])


# ---- the widget dictionary of PDF 1.7 Table 8.39, one fixture per group of keys -------------------
#
# A /Widget's state is its /FT field type, its /Ff FLAGS as bits, and a handful of value keys, and every
# member of PDFAnnotation (PDFAnnotationUtilities) that reads a widget is a question about one of them.
# The flags are the part that cannot be guessed: Table 8.39 gives each a bit and a name, and the fixture
# carries one annotation PER BIT with only that bit set, so each member is measured against a file that
# sets its own bit and nothing else.  A fixture with all the bits at once would answer every member YES
# and prove nothing.
def widget(extra, field=b"/Tx", rect=b"[40 40 240 70]", name=None):
    return annot(b"Widget", [(b"Rect", rect), (b"F", b"4"), (b"FT", field)] + extra, name=name)


# bit 1 ReadOnly, 2 Required, 3 NoExport, 13 Multiline, 14 Password, 15 NoToggleToOff, 16 Radio in
# unison, 17 Pushbutton, 18 Combo, 19 Edit, 20 Sort, 21 FileSelect, 22 MultiSelect, 23 DoNotSpellCheck,
# 24 DoNotScroll, 25 Comb, 26 RichText - each on an annotation of its own, named for its bit
# Each bit is the INTEGER, not a list holding it: the first version of this table wrote lists, so
# str(bits) produced "[1]" and the fixtures carried /Ff [1] - an ARRAY where the format wants an integer -
# and the host then answered every flag member NO for every fixture, which read as "the host ignores
# /Ff".  A fixture that cannot fail is not a fixture, and this one failed silently for a whole round.
WIDGET_FLAG_BITS = [
    (b"bit1-readonly", 1),
    (b"bit2-required", 2),
    (b"bit13-multiline", 1 << 12),
    (b"bit14-password", 1 << 13),
    (b"bit15-notoggletooff", 1 << 14),
    (b"bit16-radioinunison", 1 << 15),
    (b"bit17-pushbutton", 1 << 16),
    (b"bit18-combo", 1 << 17),
    (b"bit19-edit", 1 << 18),
    (b"bit21-fileselect", 1 << 20),
    (b"bit22-multiselect", 1 << 21),
    (b"bit25-comb", 1 << 24),
    (b"bit26richtext", 1 << 25),
]
WIDGET_FLAGS = [widget([(b"Ff", str(bits).encode()),
                        (b"V", b"(value)"), (b"DV", b"(default)"), (b"AS", b"/Yes")])
                for _title, bits in WIDGET_FLAG_BITS]
# no /Ff at all, so every flag member's ABSENT answer is measured on the same shape
WIDGET_NO_FLAGS = [widget([(b"V", b"(value)"), (b"DV", b"(default)"), (b"AS", b"/Yes")])]
# a flags word with EVERY bit the table names, so a member that reads more than one bit is measured
# against all of them at once as well as one at a time
WIDGET_ALL_FLAGS = [widget([(b"Ff", str((1 << 0) | (1 << 1) | (1 << 12) | (1 << 13) | (1 << 14) |
                                     (1 << 15) | (1 << 16) | (1 << 17) | (1 << 18) | (1 << 20) |
                                     (1 << 21) | (1 << 24) | (1 << 25)).encode())])]

# the field TYPES of Table 8.39, one annotation each, and the button-widget STATES beside them
# AND the same four one at a time, each ALONE on its page, because a fixture carrying all four can only
# say that one of them is missing and not which - and the answer turned out to be one of them.
WIDGET_FIELD_TYPES_ONE = [(ft, [widget([], field=ft)]) for ft in
                          (b"/Btn", b"/Tx", b"/Ch", b"/Sig")]
WIDGET_FIELD_TYPES_ONE += [
    (b"/Ch", [widget([(b"Opt", b"[(one) (two)]")], field=b"/Ch")]),
    (b"/Ch", [widget([(b"Opt", b"(not an array)")], field=b"/Ch")]),
]

# one /FT each, written ONCE: the first version of this passed the field type both as the helper's
# `field` argument and as an extra pair, so every dictionary carried /FT twice - and the host then
# answered three of the four field types rather than four, which read as "the host drops a choice widget"
# and was this fixture writing a duplicate key.
WIDGET_FIELD_TYPES = [widget([], field=ft) for ft in
                      (b"/Btn", b"/Tx", b"/Ch", b"/Sig")]
WIDGET_STATES = [widget([(b"FT", b"/Btn"), (b"V", b"(off)"), (b"AS", state)])
                 for state in (b"/Yes", b"/Off", b"/On")]

# the VALUE keys, one annotation per key, because a key that is ABSENT and a key that is present with
# the wrong type are two different answers and the port has to tell them apart
# /FT is written ONCE here too: the first version of this list passed /FT as an extra AND let the helper
# write it, so every dictionary carried /FT /Tx twice - and the host then answered a SYNTHESISED fieldName
# for a widget that had /T (the field) in plain sight, which read as "fieldName is not /T".  See
# widget-t-literal.pdf, which carries one /FT and answers "the field".
WIDGET_VALUES = [
    widget([(b"V", b"(typed)"), (b"DV", b"(preset)"), (b"MaxLen", b"7"),
            (b"Q", b"2"), (b"Opt", b"[(one) (two) (three)]"), (b"T", b"(the field)"),
            (b"TU", b"(alternate)"), (b"DA", b"(/Helv 12 Tf 0 g)")]),
    # the same with the value keys of the wrong type, one each, so the reader has to refuse them
    widget([(b"V", b"7"), (b"DV", b"[1 2]"), (b"MaxLen", b"(seven)"),
            (b"Q", b"(two)"), (b"Opt", b"(not an array)")]),
    # and with none of them, so the absent answer is measured on the same shape
    widget([]),
]

# /T (the field) PLUS one other key, one annotation each, because widget-t-literal.pdf reads its /T and
# widget-values.pdf does not - and both carry the SAME literal /T string on the same dictionary, so
# something else in the second is what stops the read.  One key per fixture finds which.
# The list is a LIST OF PAIRS and each extra key is APPENDED to it - the first version wrote
# (b"T", b"(the field)") + extra, which concatenates two TUPLES and makes a three-element one, so the
# fixture writer unpacked a pair and raised.  Silent until it did not, which is this family's habit.
# /DA IS ITS OWN ROW HERE and it is written as the format makes it: a TEXT STRING,
# /DA (/Helv 12 Tf 0 g).  The first version of this matrix wrote the content-stream operators
# BARE into the dictionary - /DA /Helv 12 Tf 0 g - which is a syntax error: CG_PDF_VERBOSE then
# says "encountered unexpected symbol `Tf'" and the host answers NO ANNOTATIONS for the page.
# That read as "a /DA is not readable in an annotation dictionary at all", which is a statement
# about the fixture and not about the host, and it is what made fieldName look synthesised on a
# widget that had /T in plain sight.
T_WITH_ONE_MORE_NAMES = ("nothing", "DAstring", "TU", "Opt", "Q", "MaxLen", "V", "DV", "F")
# each entry is a LIST of one annotation, because build() takes a list and the loop below hands it
# [annotations[0]] - a bare annotation is BYTES, and indexing into it gives an int, which is how the first
# version of this raised inside the fixture writer rather than in the probe
T_WITH_ONE_MORE = [
    [widget([(b"T", b"(the field)")] + list(extra))]
    for extra in ((), ((b"DA", b"(/Helv 12 Tf 0 g)"),), ((b"TU", b"(alternate)"),),
                 ((b"/Opt", b"[(one)]"),),
                 ((b"Q", b"2"),), ((b"MaxLen", b"7"),), ((b"V", b"(typed)"),),
                 ((b"DV", b"(preset)"),), ((b"F", b"4"),))]

# A page whose annotations are NOT all widgets, so the number in a synthesised name says what it counts:
# three annotations, only one of them a widget, and the widget is the THIRD.  A synthesised "text2" means
# it counts annotations, "text0" means it counts widgets, and the two differ here.
WIDGET_MIXED = [
    annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"F", b"4"), (b"Contents", b"(a link)")]),
    annot(b"Square", [(b"Rect", b"[40 40 140 140]"), (b"F", b"4"), (b"Contents", b"(a square)")]),
    widget([]),
    annot(b"Popup", [(b"Rect", b"[60 60 160 160]"), (b"F", b"4"), (b"Contents", b"(a popup)")]),
    widget([]),
]

# The number in a SYNTHESISED field name, which is what a nameless widget answers.  Three shapes, so
# the counter's subject is visible: three widgets alone, a link before two widgets, and a link BETWEEN
# two widgets.  If it counts annotations the first is 0,1,2 and the others shift; if it counts widgets the
# three are all 0,1,2.
SYNTH_COUNT_WIDGETS_ONLY = [widget([]), widget([]), widget([])]
SYNTH_COUNT_LINK_FIRST = [annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"F", b"4")]),
                          widget([]), widget([])]
SYNTH_COUNT_LINK_MIDDLE = [widget([]), annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"F", b"4")]),
                           widget([])]

# -buttonWidgetState's matrix.  The format splits a check box in two: the FIELD carries /V, the value, and
# the WIDGET carries /AS, the appearance state (Table 8.69), and PDFKit's member could read either or
# both.  So the fixtures are: a /Btn with /AS alone, a /Btn with /AS and /V on the same dictionary, and the
# MERGED shape with /V on the field and /AS on the widget - four states each, because /Off, /On and /Yes
# are the names the format uses and "absent" is the case that says which one the member defaults to.
BTN_STATES = (None, b"/Off", b"/On", b"/Yes")

def _as_pairs(state, key=b"AS"):
    """the (key, value) pairs for one state key, as the annotation helpers take them"""
    return [] if state is None else [(key, state)]


def _as_bytes(state, key=b"AS"):
    """the same one state key, as the merged writer's bytes - it builds a dictionary itself rather than
    going through annot(), so it wants " /AS /On" and not a pair.  The two spellings of the same thing in
    one file is fixture bug fourteen, and it raised on the first call rather than writing a bad file."""
    return b"" if state is None else b" /" + key + b" " + state


BUTTON_AS_ALONE = [widget(_as_pairs(state), field=b"/Btn") for state in BTN_STATES]
BUTTON_AS_AND_V = [widget(_as_pairs(state) + _as_pairs(state, b"V"), field=b"/Btn")
                   for state in BTN_STATES]
# and a /Tx beside them, because a text widget answered -1 on every /AS measured and that has to be a
# rule rather than an accident of the shape
TEXT_AS = [widget(_as_pairs(state)) for state in BTN_STATES]

# Two gaps the first /AS round left.  (a) Is /AS /Yes the on-state or is /V /On?  button-as-alone has /AS
# /On with no /V and answers 0; button-as-and-v has both equal and /On answers 1 - so one of the two keys
# carries it and that pair cannot say which.  Four fixtures, /AS and /V varied INDEPENDENTLY.
# (b) Is -buttonWidgetStateString ever anything but "Yes"?  It answered "Yes" on eighteen fixtures so far,
# including -1 answers and /Off answers, which reads as a constant - and the format names a check box's on
# state in the /AP dictionary's /N keys, so an /AP whose /N is keyed on something else is the case that
# would move it.
BUTTON_V_ONLY = [widget(_as_pairs(state, b"V"), field=b"/Btn") for state in BTN_STATES]
BUTTON_AS_YES_V_OFF = [widget(_as_pairs(b"/Yes") + _as_pairs(state, b"V"), field=b"/Btn")
                       for state in BTN_STATES]
BUTTON_AP_STATES = [
    widget([(b"AS", b"/Off"), (b"AP", b"<< /N << /On << >> /Off << >> >> >>")], field=b"/Btn"),
    widget([(b"AS", b"/On"), (b"AP", b"<< /N << /On << >> /Off << >> >> >>")], field=b"/Btn"),
    widget([(b"AS", b"/Yes"), (b"AP", b"<< /N << /Yes << >> /Off << >> >> >>")], field=b"/Btn"),
    widget([(b"AS", b"/Yes"), (b"AP", b"<< /N << /Marked << >> /Off << >> >> >>")], field=b"/Btn"),
    widget([(b"AS", b"/Marked"), (b"AP", b"<< /N << /Marked << >> /Off << >> >> >>")], field=b"/Btn"),
]

# The one combination the first two rounds did not derive: button-as-alone answers 0 for /AS /On with no
# /V, and button-as-and-v answers 1 for /AS /On WITH /V /On.  Two fixtures cross it - /AS /Off with /V /On
# and /AS /On with /V /Off - so a disjunction and a conjunction are told apart from one another.
BUTTON_AS_OFF_V_ON = [
    widget([(b"AS", b"/Off"), (b"V", b"/On")], field=b"/Btn"),
    widget([(b"AS", b"/On"), (b"V", b"/Off")], field=b"/Btn"),
    widget([(b"AS", b"/Yes"), (b"V", b"/On")], field=b"/Btn"),
    widget([(b"AS", b"/On"), (b"V", b"/Yes")], field=b"/Btn"),
]

# The THREE COLOURS and the FONT, one annotation per key, over the keys the 26.2 header NAMES.
#
# PDFAnnotationUtilities.h:280 says of -backgroundColor "Background color characteristics. Used by
# annotations type(s): /Widget (field type(s): /Btn, /Ch, /Tx)", and :131 says of -interiorColor
# "Interior color of the annotation. Used by annotations type(s): /Circle, /Line, /Square".  The first
# version of this fixture wrote /MK /BC for the background - and /BC is the BORDER colour of Table 8.40,
# which is the key -[PDFAnnotation border] reads - and /MK << /IC >> for the interior, and /IC is not an
# /MK key at all.  Both answered nil, which said nothing except that the wrong keys had been written.
#
# So: the background off /MK /BG on a widget, the interior off a /Square's and a /Circle's own /IC, and
# the /DA's FILL colour operand - g, rg and k - because text is painted with the fill colour and RG, G and
# K set the stroke (Table 8.68), which is why the first version's uppercase shapes answering black was the
# format and not a gap.
#
# EVERY ANNOTATION HERE CARRIES ITS OWN /NM, and that is the whole point of the list's shape.  The first
# version of this fixture was a bare list read by INDEX, and the host keeps 26 of its 27 - it drops the
# /Ch widget, whose /Opt Table 8.39 makes required and which therefore fails the choice-widget skip
# -[PDFPage annotations] already had.  So every reading after the seventh was a reading of the WRONG
# ANNOTATION: the "a /Ch field answers a green the array does not contain" line was the NEXT annotation's
# /BG [0 1 0], and every /DA shape after it was measured one annotation out of step.  /NM is the format's
# own unique-name key (PDF 1.7 Table 8.16), it travels with the annotation, and a reading keyed by it
# cannot shift.  /Rect cannot do the job either: the widgets here all share one rectangle - this list
# wrote [40 40 240 70] on every /Tx - which is why the name is the key and not the rectangle.
def named(name, body):
    """The annotation `annot` or `widget` already built, carrying the /NM every reading is keyed by.

    The name is the fixture's own and not one the format reserves: what matters is that it is a PDF
    string both sides can read back out of the dictionary, so a key built from it belongs to an
    annotation.  The assert is the helper's contract - the body is ONE dictionary and this writes into
    it, so anything else has to fail here rather than write a file the host cannot parse."""
    assert body.endswith(b" >>"), body[:60]
    return body[:-3] + b" /NM (" + name.encode("ascii") + b") >>"


COLOUR_SHAPES = [
    # -backgroundColor, off /MK /BG, one annotation per component count of Table 8.40
    named("bg-rgb",       widget([(b"MK", b"<< /BG [1 0 0] >>")], field=b"/Tx")),
    named("bg-gray",      widget([(b"MK", b"<< /BG [0.5] >>")], field=b"/Tx")),
    named("bg-cmyk-none", widget([(b"MK", b"<< /BG [0 0 0 0] >>")], field=b"/Tx")),
    named("bg-cmyk",      widget([(b"MK", b"<< /BG [0.1 0.2 0.3 0.4] >>")], field=b"/Tx")),
    named("bg-notarray",  widget([(b"MK", b"<< /BG (a string) >>")], field=b"/Tx")),
    # and off a /Btn and a /Ch, since the header names those field types too.  THE /Ch IS THE ONE THE HOST
    # DOES NOT SURFACE, and it is here on purpose: its /NM is the one name this fixture writes that no
    # annotation answers, which is how the drop is visible rather than inferred.
    named("bg-btn",       widget([(b"MK", b"<< /BG [0 0 1] >>")], field=b"/Btn")),
    named("bg-ch-noopt",  widget([(b"MK", b"<< /BG [0 0 1] >>")], field=b"/Ch")),
    # and with /BC beside it, to show the two keys are not confused with one another
    named("bg-bc-beside", widget([(b"MK", b"<< /BC [1 0 0] /BG [0 1 0] >>")], field=b"/Tx")),
    # -interiorColor, off a geometry annotation's own /IC
    named("ic-square-rgb",   annot(b"Square", [(b"Rect", b"[40 40 240 140]"), (b"F", b"4"),
                                                (b"IC", b"[0 1 0]")])),
    named("ic-square-gray",  annot(b"Square", [(b"Rect", b"[40 40 240 140]"), (b"F", b"4"),
                                                (b"IC", b"[0.25]")])),
    named("ic-square-none",  annot(b"Square", [(b"Rect", b"[40 40 240 140]"), (b"F", b"4")])),
    named("ic-circle-cmyk",  annot(b"Circle", [(b"Rect", b"[40 40 240 140]"), (b"F", b"4"),
                                                (b"IC", b"[0.1 0.2 0.3 0.4]")])),
    named("ic-link",         annot(b"Link", [(b"Rect", b"[20 700 60 720]"), (b"F", b"4"),
                                             (b"IC", b"[1 0 0]")])),
    named("ic-widget",       annot(b"Widget", [(b"Rect", b"[40 40 240 70]"), (b"F", b"4"),
                                                (b"FT", b"/Tx"), (b"IC", b"[1 0 0]")])),
    # -fontColor off the FILL operands, with two CMYK values whose conversion is NOT black, and the
    # stroking operands beside them to show the pair is not confused with one another
    named("da-fill-gray-0",    widget([(b"DA", b"(/Helv 12 Tf 0 g)")])),
    named("da-fill-gray-1",    widget([(b"DA", b"(/Helv 12 Tf 1 g)")])),
    named("da-fill-rgb",       widget([(b"DA", b"(/Helv 12 Tf 1 0 0 rg)")])),
    named("da-fill-cmyk-red",  widget([(b"DA", b"(/Helv 12 Tf 0 1 1 0 k)")])),
    named("da-fill-cmyk-cyan", widget([(b"DA", b"(/Helv 12 Tf 1 0 0 0 k)")])),
    named("da-stroke-rg",      widget([(b"DA", b"(/Helv 12 Tf 0 1 0 RG)")])),
    named("da-stroke-k",       widget([(b"DA", b"(/Helv 12 Tf 0 1 0 K)")])),
    named("da-stroke-g",       widget([(b"DA", b"(/Helv 12 Tf 0 1 0 G)")])),
    named("da-nooperand",      widget([(b"DA", b"(/Helv 12 Tf)")])),
    # and the two questions the /DA reader cannot answer from one operator each: whether the OPERAND'S
    # POSITION in the string matters, and whether a colour operator with the WRONG NUMBER OF OPERANDS is
    # read or refused.  A later fill must beat an earlier one, an earlier must beat a later one, and the
    # two-operand gray is not a colour the format defines.
    named("da-fill-gray-then-rgb", widget([(b"DA", b"(/Helv 12 Tf 0.5 g 1 0 0 rg)")])),
    named("da-fill-rgb-then-gray", widget([(b"DA", b"(/Helv 12 Tf 1 0 0 rg 0.5 g)")])),
    named("da-fill-gray-twice",    widget([(b"DA", b"(/Helv 12 Tf 1 g 0.25 g)")])),
    named("da-fill-badcount",      widget([(b"DA", b"(/Helv 12 Tf 0.5 0.25 g)")])),
    # and -font's shapes: a full PostScript name, no name, no size, and a font the system does not have
    named("font-courier-7",   widget([(b"DA", b"(/Courier 7 Tf 0 g)")])),
    named("font-size-only",   widget([(b"DA", b"(12 Tf 0 g)")])),
    named("font-name-only",   widget([(b"DA", b"(/Helv Tf 0 g)")])),
    named("font-unknown",     widget([(b"DA", b"(/Nonexistent 9 Tf 0 g)")])),
    # and the STANDARD FOURTEEN's own abbreviations, one per FACE, because -font has to MAP the name and
    # a rule written from Courier and Helvetica alone would be two data points and a guess.  PDF 1.7
    # 9.6.2.2 names these fourteen, and these fourteen annotations carry one abbreviation each - the
    # complete list, not a sample of it, because the first five of them already refused to be a rule:
    # /HeBo and /Cour come back as their own faces while /TiRo, /Symb and /ZaDb all answer Helvetica.
    # Which of the fourteen the host knows is then a measurement over the whole set rather than an
    # assumption from the format's list, and the sizes differ so a fallback that forgot the size shows.
    named("font-abbrev-helv",  widget([(b"DA", b"(/Helv 21 Tf 0 g)")])),
    named("font-abbrev-hebo",  widget([(b"DA", b"(/HeBo 11 Tf 0 g)")])),
    named("font-abbrev-heob",  widget([(b"DA", b"(/HeOb 12 Tf 0 g)")])),
    named("font-abbrev-hebo-bi", widget([(b"DA", b"(/HeBO 13 Tf 0 g)")])),
    named("font-abbrev-cour",  widget([(b"DA", b"(/Cour 14 Tf 0 g)")])),
    named("font-abbrev-cobo",  widget([(b"DA", b"(/CoBo 15 Tf 0 g)")])),
    named("font-abbrev-coob",  widget([(b"DA", b"(/CoOb 16 Tf 0 g)")])),
    named("font-abbrev-cbo-bi", widget([(b"DA", b"(/CBO 17 Tf 0 g)")])),
    named("font-abbrev-tiro",  widget([(b"DA", b"(/TiRo 18 Tf 0 g)")])),
    named("font-abbrev-tibo",  widget([(b"DA", b"(/TiBo 19 Tf 0 g)")])),
    named("font-abbrev-tiit",  widget([(b"DA", b"(/TiIt 20 Tf 0 g)")])),
    named("font-abbrev-tibi",  widget([(b"DA", b"(/TiBI 22 Tf 0 g)")])),
    named("font-abbrev-symb",  widget([(b"DA", b"(/Symb 23 Tf 0 g)")])),
    named("font-abbrev-zadb",  widget([(b"DA", b"(/ZaDb 24 Tf 0 g)")])),
    # and a FACE OF THE FOURTEEN spelled the way PostScript spells it, because "the name as given" and
    # "the abbreviation table" are two rules this has to tell apart and only one of them can answer for
    # a face the table does not carry.
    named("font-full-oblique", widget([(b"DA", b"(/Helvetica-Oblique 25 Tf 0 g)")])),
    named("font-full-roman",   widget([(b"DA", b"(/Times-Roman 26 Tf 0 g)")])),
    # and the SHAPE of the lookup, because "which fourteen does PDFKit know" is only half the question:
    # a rule written as a table of the three it answers needs to say what it does with everything else,
    # and the candidates are a prefix match, a case-insensitive match and an exact one.  These five
    # separate them - a PREFIX match would answer Courier, Times-Roman and Helvetica for /Co, /Ti and /H,
    # a CASE-INSENSITIVE table would answer Helvetica for /HELV, and an EXACT table answers Helvetica for
    # all five.  -[NSFont fontWithName:] is nil for every abbreviation (measured), so the platform's own
    # lookup is not what does this.
    named("font-prefix-h",     widget([(b"DA", b"(/H 27 Tf 0 g)")])),
    named("font-prefix-co",    widget([(b"DA", b"(/Co 28 Tf 0 g)")])),
    named("font-prefix-ti",    widget([(b"DA", b"(/Ti 29 Tf 0 g)")])),
    named("font-case-upper",   widget([(b"DA", b"(/HELV 30 Tf 0 g)")])),
    named("font-case-mixed",   widget([(b"DA", b"(/Hebo 31 Tf 0 g)")])),
]

# /T, spelled four ways, because -[PDFAnnotation fieldName] answers a SYNTHESISED name on the first
# version of the widget fixtures and the coordinator's challenge is right that this fits the
# fixture-defect pattern rather than a host behaviour: a widget that DOES carry /T must be read first,
# with /T as a literal string on the widget's own dictionary, then as a NAME, then on a PARENT field
# dictionary with the widget as its /Kid - which is the MERGED field+widget shape of PDF 1.7 Table 8.62,
# and the shape a /T is really written in.
T_LITERAL = [widget([(b"T", b"(the field)")])]
T_NAME = [widget([(b"T", b"/TheField")])]
T_EMPTY = [widget([(b"T", b"()")])]

def merged_field_child(field_extra, child_extra):
    """A FIELD dictionary holding /T with a WIDGET that names it as its /Parent, the other half of the
    merged shape.  The field is not in the page's /Annots: it is an indirect object the widget points at.
    """
    widget_body = annot(b"Widget", [(b"Rect", b"[40 40 240 70]"), (b"F", b"4"), (b"FT", b"/Tx")]
                        + child_extra)
    return widget_body, field_extra


def build_merged_field(directory, name, child_extra, field_extra=b"/T (parent field)",
                       field_type=b"/Tx", child_type=None):
    """One page whose /Annots holds a WIDGET whose /Parent is a FIELD dictionary, the merged shape.

    Laid out by hand because the two dictionaries reference each other: the field is object 7 and the
    widget object 8, the widget names 7 and the catalog is 1.  Both /Lengths and both xref offsets are
    measured as they are written, like every other fixture here.
    """
    font = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    text = b"BT /F1 12 Tf 72 720 Td (merged) Tj ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"",                       # the page, filled in once the widget's number is known
        b"<< /Length " + str(len(text)).encode() + b" >>\nstream\n" + text + b"\nendstream",
        b"",                       # the widget, filled in below
        font,
        b"",                       # the field, filled in below
    ]
    objects[4] = (b"<< /Type /Annot /Subtype /Widget /Rect [40 40 240 70] /F 4 /Parent 7 0 R "
                  + (b"/FT " + child_type if child_type else b"")
                  + child_extra + b" >>")
    objects[6] = (b"<< /FT " + field_type + b" /T " + field_extra + b" /Kids [5 0 R] >>")
    objects[2] = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [5 0 R] "
                  b"/Resources << /Font << /F1 6 0 R >> >> /Contents 4 0 R >>")
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += str(number).encode() + b" 0 obj\n" + body + b"\nendobj\n"
    start = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\nstartxref\n"
            + str(start).encode() + b"\n%%EOF\n")
    open(os.path.join(directory, name), "wb").write(bytes(out))
    return len(objects)


# ---- /Outlines: the outline tree of PDF 1.7 Table 8.2 -------------------------------------------
#
# An outline is a LINKED structure and not a tree of nested dictionaries: every item names its /Parent,
# its /Prev and its /Next, and a parent's children are its /First .. /Last chain.  So the fixtures
# cannot be written as a literal - the object numbers depend on how many items there are above them -
# and build_outline() below emits the whole tree from a nested spec and measures every number it writes.
#
# /Count is on the FIRST CHILD of an item with children and counts the item's visible descendants at
# every level.  A POSITIVE /Count means the item is CLOSED and a NEGATIVE one means it is OPEN, which is
# the opposite of what the sign suggests and is measured here rather than assumed: outline-closed.pdf and
# outline-open.pdf carry the same shape with the two signs.

def _outline_items(spec, root_number, first_number, signs=None):
    """(bodies, top-level numbers, next number) for a nested spec.

    Each spec entry is (title_bytes_or_None, [extra (key, value) pairs], [children]).  The bodies come
    back in the order the numbers were handed out, which is the order the numbers are assigned in.
    """
    bodies = {}
    number = first_number
    signs = signs or {}

    def emit(entries, parent_number):
        nonlocal number
        numbers = []
        for _title, _extra, _children in entries:
            numbers.append(number)
            number += 1
        for i, (title, extra, children) in enumerate(entries):
            here = numbers[i]
            body = b"<< /Type /Annot /Subtype /Link /Rect [0 0 10 10]"
            if title is not None:
                body += b" /Title (" + title + b")"
            body += b" /Parent " + str(parent_number).encode() + b" 0 R"
            if i > 0:
                body += b" /Prev " + str(numbers[i - 1]).encode() + b" 0 R"
            if i + 1 < len(entries):
                body += b" /Next " + str(numbers[i + 1]).encode() + b" 0 R"
            for key, value in extra:
                body += b" /" + key + b" " + value
            if children:
                child_numbers = emit(children, here)
                # the SIGN is per item and is what separates "has children" from "the sign of /Count":
                # by default every item with children is written NEGATIVE, and outline-signs.pdf writes
                # one POSITIVE beside one NEGATIVE with the same shape
                sign = signs.get(title, -1)
                body += (b" /First " + str(child_numbers[0]).encode() + b" 0 R /Last "
                         + str(child_numbers[-1]).encode() + b" 0 R /Count "
                         + str(sign * _visible_count(children)).encode())
            body += b" >>"
            bodies[here] = body
        return numbers

    root_numbers = emit(spec, root_number)
    return bodies, root_numbers, number


def _visible_count(entries):
    """The number a /Count carries for this shape, and the SIGN that says open or closed.

    An item with children counts its own descendants at every level, and the fixtures below write the
    count by hand instead - a positive one on a closed item and a negative one on an open one - so this
    is only the total, never the sign.
    """
    total = 0
    for _title, _extra, children in entries:
        total += 1
        if children:
            total += _visible_count(children)
    return total


def build_outline(directory, name, spec, open_sign=-1, page_count=1, signs=None, extra=()):
    """One fixture whose catalog carries an /Outlines tree, built from a nested spec."""
    # build()'s layout: 1 catalog, 2 pages, page_count pages, their page_count content streams, then the
    # page's own annotations, then 1 font - so the first object this fixture may write is
    # 3 + 2 * page_count + len(page_annotations) + 1.  The first version of this arithmetic said
    # 5 + page_count + 1 and every reference in every outline fixture was one too high, which the host
    # answered as NO outline root at all.
    page_annotations = [annot(b"Square", [(b"Rect", b"[0 0 10 10]"), (b"F", b"4"),
                                          (b"Contents", b"(filler)")])] * extra
    first = 3 + 2 * page_count + len(page_annotations) + 1
    # the outline ROOT dictionary takes that number and the items follow it, because a top-level item's
    # /Parent IS the root dictionary and its number has to be known before the items are written
    root_number = first
    bodies, roots, _last = _outline_items(spec, root_number, first + 1, signs or {})
    root_body = (b"<< /Type /Outlines /First " + str(roots[0]).encode() + b" 0 R /Last "
                 + str(roots[-1]).encode() + b" 0 R /Count "
                 + str(open_sign * _visible_count(spec)).encode() + b" >>")
    extra = [("outline-root", root_body)] + [(str(n), bodies[n]) for n in sorted(bodies)]
    catalog_extra = b" /Outlines " + str(root_number).encode() + b" 0 R"
    count, numbers = build(os.path.join(directory, name), list(page_annotations), extra,
                           catalog_extra, page_count=page_count)
    return count, numbers, root_number, sorted(bodies)


# a three-level tree, the sign written per item, and one sibling at the top
OUTLINE_OPEN = [
    (b"One", [(b"F", b"4"), (b"Dest", b"[3 0 R /XYZ 11 22 0.5]")], [
        (b"One One", [(b"F", b"4")], [
            (b"One One One", [(b"F", b"4")], []),
        ]),
        (b"One Two", [(b"F", b"4")], []),
    ]),
    (b"Two", [(b"F", b"4"), (b"A", b"<< /S /URI /URI (https://example.com/two) >>")], [
        (b"Two One", [(b"F", b"4"), (b"Dest", b"[3 0 R /Fit]")], []),
    ]),
]
OUTLINE_CLOSED = [
    (b"One", [(b"F", b"4")], [
        (b"One One", [(b"F", b"4")], []),
    ]),
]
# two items with the SAME shape - one child each - and opposite /Count signs, which is the fixture that
# tells "-isOpen is whether it has children" from "-isOpen is the sign of /Count"
OUTLINE_SIGNS = [
    (b"Positive", [(b"F", b"4")], [
        (b"Positive Child", [(b"F", b"4")], []),
        (b"Positive Child Two", [(b"F", b"4")], []),
    ]),
    (b"Negative", [(b"F", b"4")], [
        (b"Negative Child", [(b"F", b"4")], []),
        (b"Negative Child Two", [(b"F", b"4")], []),
    ]),
]
OUTLINE_SIGNS_SIGNS = {b"Positive": 1, b"Negative": -1}

# Four items with NO /Count at all, side by side.  The sign of /Count is what -isOpen reads, and an item
# that carries none is the case where the host's own answer has to be looked at before it is compared:
# in outline-shapes one such item answers YES and its neighbour answers NO.
OUTLINE_NO_COUNT = [
    (b"A", [(b"F", b"4")], []),
    (b"B", [(b"F", b"4")], []),
    (b"C", [(b"F", b"4")], []),
    (b"D", [(b"F", b"4")], []),
]

# the shapes the members above turn on: no /Title, a /Dest AND an /A on one item, a /Count of zero, an
# item with no /First at all, and a named destination
OUTLINE_SHAPES = [
    (None, [(b"F", b"4")], [
        (b"Child", [(b"F", b"4"), (b"Dest", b"[3 0 R /XYZ 1 2 3]"),
                    (b"A", b"<< /S /GoTo /D [3 0 R /Fit] >>")], []),
        (None, [(b"F", b"4")], []),
    ]),
    (b"Closed", [(b"F", b"4")], [
        (b"Closed Child", [(b"F", b"4")], []),
    ]),
    (b"Named", [(b"F", b"4"), (b"Dest", b"(chapter1)")], []),
    (b"Alone", [(b"F", b"4")], []),
]

# One item per hypothesis about -isOpen on an item with NO /Count, because that is the case where the
# host answered YES for one item in outline-shapes and NO for every other, and a rule has to be told
# from an artefact.  Every item here carries no /Count and no children, and they differ only in whether
# they are the FIRST in their chain, whether they are titled, and whether the item before them carries a
# /Dest or an /A.
OUTLINE_ISOPEN = [
    (b"P1", [(b"F", b"4")], [
        (b"C1", [(b"F", b"4"), (b"Dest", b"[3 0 R /Fit]")], []),
        (b"C2", [(b"F", b"4")], []),
    ]),
    (b"P2", [], [
        (b"C3", [(b"F", b"4")], []),
        (b"C4", [], []),
    ]),
    (b"P3", [(b"F", b"4")], [
        (b"C5", [], []),
        (b"C6", [(b"F", b"4"), (b"A", b"<< /S /URI /URI (https://example.com/c6) >>")], []),
    ]),
]

# A chain of four UNTITLED items, each with /F 4 and no /Count, and beside it a chain of four TITLED
# ones with the same shape.  This is the fixture that isolates the one -isOpen answer the host gives that
# the sign of /Count does not explain.
OUTLINE_UNTITLED = [
    (None, [(b"F", b"4")], [
        (None, [(b"F", b"4")], [
            (None, [(b"F", b"4")], [
                (None, [(b"F", b"4")], []),
            ]),
        ]),
    ]),
]
OUTLINE_TITLED = [
    (b"T", [(b"F", b"4")], [
        (b"U", [(b"F", b"4")], [
            (b"V", [(b"F", b"4")], [
                (b"W", [(b"F", b"4")], []),
            ]),
        ]),
    ]),
]

# Three leaves that differ ONLY in what /Title says, each with no /Count: no /Title at all, an EMPTY
# /Title (), and a real one.  That is the shape that says whether the host's -isOpen reads the PRESENCE of
# the key or its text.
OUTLINE_TITLE_KEY = [
    (b"None", [(b"F", b"4")], [(None, [(b"F", b"4")], [])]),
    (b"Empty", [(b"F", b"4")], [(b"", [(b"F", b"4")], [])]),
    (b"Text", [(b"F", b"4")], [(b"leaf", [(b"F", b"4")], [])]),
    (b"NoTitleNoF", [], [(None, [], [])]),
    (b"NoTitleWithDest", [(b"F", b"4")], [(None, [(b"F", b"4"), (b"Dest", b"[3 0 R /Fit]")], [])]),
]

# ---- /A, the action dictionary of PDF 1.7 Table 8.44, and the /Dest of Table 8.42 --------------
#
# The five /S names the six action classes of the 26.2 headers are built from - /GoTo, /Named, /URI,
# /GoToR and /ResetForm - plus an /S the format does not list and an action with no /S at all, because
# the class -[PDFAction type] answers and the class the host hands back for an unknown /S are both
# questions an action family has to have measured.
#
# Every explicit destination here is an ARRAY, [page /XYZ left top zoom], which is one of the two
# spellings PDF 1.7 Table 8.42 gives; the other, a dictionary naming /D, is what ann-dest-dict writes.
# The page is object 3 unless the fixture says otherwise, and the two-page fixture points at object 4 so
# that "the destination's page" is an index rather than a constant.
def link(extra):
    return annot(b"Link", [(b"Rect", b"[20 700 220 720]"), (b"Contents", b"(link)"), (b"F", b"4")]
                 + extra)


ACT_GOTO_XYZ = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ 100 200 1.5] >>")])
ACT_GOTO_FIT = link([(b"A", b"<< /S /GoTo /D [3 0 R /Fit] >>")])
ACT_GOTO_FITB = link([(b"A", b"<< /S /GoTo /D [3 0 R /FitB 0 0 612 792] >>")])
ACT_GOTO_FITH = link([(b"A", b"<< /S /GoTo /D [3 0 R /FitH 700] >>")])
ACT_GOTO_FITBH = link([(b"A", b"<< /S /GoTo /D [3 0 R /FitBH 12 34] >>")])
ACT_GOTO_FITBV = link([(b"A", b"<< /S /GoTo /D [3 0 R /FitBV 56 78] >>")])
# a zoom written as an integer, and a destination whose page is the SECOND page: the port's pages are
# objects 3 and 4 on a two-page fixture, so the index it must answer is 1
ACT_GOTO_ZOOM_INT = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ 0 0 2] >>")])
# the destination's page as an INDEX rather than a constant: on the two-page fixture the pages are
# objects 3 and 4, so a /D naming object 4 is the second page
ACT_GOTO_PAGE2 = link([(b"A", b"<< /S /GoTo /D [4 0 R /XYZ 0 0 1] >>")])
ACT_GOTO_BAD_PAGE = link([(b"A", b"<< /S /GoTo /D [99 0 R /Fit] >>")])
# the NAMED destination spelling: the catalog's /Dests names it and the action names the name
ACT_GOTO_NAMED = link([(b"A", b"<< /S /GoTo /D (chapter1) >>")])
# an action with no /S, an /S the format does not list, and an /S whose own payload is missing
ACT_NO_S = link([(b"A", b"<< /Type /Action /D [3 0 R /Fit] >>")])
ACT_UNKNOWN_S = link([(b"A", b"<< /S /Bogus /X 1 >>")])
ACT_GOTO_NO_D = link([(b"A", b"<< /S /GoTo >>")])
# the named actions, one per /N the header's enum names, and one the enum does not
ACT_NAMED_NEXT = link([(b"A", b"<< /S /Named /N /NextPage >>")])
ACT_NAMED_FIRST = link([(b"A", b"<< /S /Named /N /FirstPage >>")])
ACT_NAMED_ZOOMIN = link([(b"A", b"<< /S /Named /N /ZoomIn >>")])
ACT_NAMED_NONSENSE = link([(b"A", b"<< /S /Named /N /NotAName >>")])
ACT_URI = link([(b"A", b"<< /S /URI /URI (https://example.com/a b) >>")])
ACT_URI_NO_URI = link([(b"A", b"<< /S /URI >>")])
ACT_GOTOR = link([(b"A", b"<< /S /GoToR /F (other.pdf) /D [3 0 R /XYZ 5 6 2] >>")])
ACT_GOTOR_NO_F = link([(b"A", b"<< /S /GoToR /D [3 0 R /Fit] >>")])
ACT_GOTOR_F_DICT = link([(b"A", b"<< /S /GoToR /F (other.pdf) /D << /D [3 0 R /XYZ 7 8 1] /S /XYZ >> >>")])
ACT_RESET = link([(b"A", b"<< /S /ResetForm /Fields [(f1) (f2)] >>")])
ACT_RESET_NO_FIELDS = link([(b"A", b"<< /S /ResetForm >>")])
ACT_RESET_FLAGS = link([(b"A", b"<< /S /ResetForm /Flags 1 /Fields [(f1)] >>")])

# /Dest on the annotation itself, in both of the format's spellings and through the named one
ANN_DEST_ARRAY = link([(b"Dest", b"[3 0 R /XYZ 11 22 0.5]")])
ANN_DEST_DICT = link([(b"Dest", b"<< /D [3 0 R /XYZ 33 44 2.5] /S /XYZ >>")])
ANN_DEST_FIT = link([(b"Dest", b"[3 0 R /Fit]")])
ANN_DEST_NAMED = link([(b"Dest", b"(chapter1)")])
ANN_DEST_AND_A = link([(b"Dest", b"[3 0 R /XYZ 1 2 3]"), (b"A", b"<< /S /GoTo /D [3 0 R /Fit] >>")])

# The page a /GoToR names, as an INDEX: on the two-page fixture the pages are objects 3 and 4, so this
# says whether -pageIndex is read out of the /D at all or is a constant
ACT_GOTOR_PAGE2 = link([(b"A", b"<< /S /GoToR /F (other.pdf) /D [4 0 R /Fit] >>")])
# /XYZ with fewer than its three numbers: which of the three members still answers
ACT_GOTO_XYZ_TWO = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ 5 6] >>")])
ACT_GOTO_XYZ_ONE = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ 7] >>")])
ACT_GOTO_XYZ_ZERO = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ 0 0 0] >>")])
# a /D whose /XYZ is spelled with the page in the SECOND position, which the format does not allow, so
# the port does not have to answer it but the harness says whether it was asked
ACT_GOTO_NO_PAGE_ARRAY = link([(b"A", b"<< /S /GoTo /D [/XYZ 1 2 3] >>")])
# a /D that is not an array and not a name at all
ACT_GOTO_D_NUMBER = link([(b"A", b"<< /S /GoTo /D 3 >>")])
ACT_GOTO_D_DICT = link([(b"A", b"<< /S /GoTo /D << /D [3 0 R /XYZ 1 2 3] /S /XYZ >> >>")])
# a negative zoom, to tell "nonzero" from "positive", and a name the format does not list
ACT_GOTO_XYZ_NEGATIVE = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ -1 -2 -3] >>")])
ACT_GOTO_UNKNOWN_NAME = link([(b"A", b"<< /S /GoTo /D [3 0 R /Bogus 1 2] >>")])
ACT_GOTO_NAME_ONLY = link([(b"A", b"<< /S /GoTo /D [3 0 R /XYZ] >>")])
# a /D that names a page and no parameters at all
ACT_GOTO_PAGE_ONLY = link([(b"A", b"<< /S /GoTo /D [3 0 R] >>")])
# a /D that names a page and the wrong /XYZ name
ACT_GOTO_WRONG_NAME = link([(b"A", b"<< /S /GoTo /D [3 0 R /Zoom 3] >>")])
# a /D that names a page reference which is not a page, beside a /D whose parameters ARE readable: the
# two are separate questions and one fixture each keeps them separate
ACT_GOTO_BADPAGE_XYZ = link([(b"A", b"<< /S /GoTo /D [99 0 R /XYZ 1 2 3] >>")])
# the /Flags of a /ResetForm, every combination Table 8.44 gives, with and without /Fields
def reset(flags, fields):
    body = b"<< /S /ResetForm"
    if flags is not None:
        body += b" /Flags " + str(flags).encode()
    if fields is not None:
        body += b" /Fields [(" + fields + b")]"
    return link([(b"A", body + b" >>")])


ACT_RESET_FLAG_TABLE = [reset(None, b"f1"), reset(0, b"f1"), reset(1, b"f1"), reset(2, b"f1"),
                        reset(3, b"f1"), reset(1, None), reset(2, None)]
# a relative /URI and one with a fragment, because -URL answers an NSURL and not the raw string
ACT_URI_RELATIVE = link([(b"A", b"<< /S /URI /URI (relative/path.pdf) >>")])
ACT_URI_FRAGMENT = link([(b"A", b"<< /S /URI /URI (https://example.com/a#frag) >>")])
ACT_GOTOR_HTTP = link([(b"A", b"<< /S /GoToR /F (https://example.com/other.pdf) /D [3 0 R /Fit] >>")])

# The NAMED destination, in BOTH of the spellings PDF 1.7 Table 8.42 gives the catalog's /Dests: a
# plain dictionary of name to destination, and a name tree.  The port's fixture puts /Dests at object 8,
# which holds for a fixture carrying one annotation.
DESTS_TREE = b"<< /Names [(chapter1) [3 0 R /XYZ 77 88 0]] >>"
DESTS_DICT = b"<< /chapter1 [3 0 R /XYZ 77 88 0] >>"
DESTS = DESTS_TREE

# every name PDFActionNamed.h's enum declares, and one it does not: which of them the host builds an
# action for is a measurement and not the enum, so all thirteen are here
NAMED_NAMES = [None, b"NextPage", b"PreviousPage", b"FirstPage", b"LastPage", b"GoBack", b"GoForward",
               b"GoToPage", b"Find", b"Print", b"ZoomIn", b"ZoomOut", b"NotAName"]
NAMED_ACTIONS = [link([(b"A", b"<< /S /Named" + (b"" if name is None else b" /N /" + name)
                        + b" >>")]) for name in NAMED_NAMES]

# a /GoToR whose /D is a page INDEX rather than a page reference, which Table 8.44 allows for that
# action, and the reset form's /Flags on its own
ACT_GOTOR_INDEX = link([(b"A", b"<< /S /GoToR /F (other.pdf) /D 1 >>")])
ACT_RESET_FLAGS_ONLY = link([(b"A", b"<< /S /ResetForm /Flags 1 >>")])
ACT_RESET_EXCLUDE = link([(b"A", b"<< /S /ResetForm /Flags 2 /Fields [(f1)] >>")])


def dest_array(page_number, tail):
    return b"[" + str(page_number).encode() + b" 0 R " + tail + b"]"


def main():
    directory = sys.argv[1]
    os.makedirs(directory, exist_ok=True)
    shapes = [
        ("border-plain.pdf", [BORDER_PLAIN]),
        ("border-radii.pdf", [BORDER_RADII]),
        ("border-zero.pdf", [BORDER_ZERO]),
        ("border-negative.pdf", [BORDER_NEGATIVE]),
        ("border-bs.pdf", [BORDER_BS]),
        ("border-short.pdf", [BORDER_SHORT]),
        ("border-long.pdf", [BORDER_LONG]),
        ("border-none.pdf", [BORDER_NONE]),
        ("border-link.pdf", [BORDER_LINK]),
        ("border-radii-only.pdf", [BORDER_RADII_ONLY]),
    ]
    for _name in (b"S", b"D", b"B", b"I", b"U", b"Q"):
        shapes.append(("bs-%s.pdf" % _name.decode().lower(), [globals()["BS_" + _name.decode()]]))
    shapes += [
        ("bs-dash-solid.pdf", [BS_DASH_SOLID]),
        ("bs-no-width.pdf", [BS_NO_WIDTH]),
        ("bs-width-only.pdf", [BS_WIDTH_ONLY]),
        ("bs-style-only.pdf", [BS_STYLE_ONLY]),
        ("bs-dash-custom.pdf", [BS_DASH_CUSTOM]),
        ("bs-dash-string.pdf", [BS_DASH_STRING]),
        ("bs-width-string.pdf", [BS_WIDTH_STRING]),
    ]
    for _kind in (b"Text", b"FreeText", b"Line", b"Circle", b"Highlight", b"Underline", b"StrikeOut",
                  b"Ink", b"Stamp", b"Popup"):
        shapes.append(("noborder-%s.pdf" % _kind.decode().lower(),
                       [globals()["NOBORDER_" + _kind.decode()]]))
    shapes += [
        ("noborder-widget.pdf", [NOBORDER_Widget]),
        ("noborder-widget-t.pdf", [NOBORDER_WidgetT]),
        ("noborder-widget-bg.pdf", [NOBORDER_WidgetBG]),
        ("noborder-widget-bc.pdf", [NOBORDER_WidgetBC]),
        ("noborder-widget-bc-gray.pdf", [NOBORDER_WidgetBCgray]),
        ("noborder-widget-bc-empty.pdf", [NOBORDER_WidgetEmptyBC]),
        ("noborder-line-l.pdf", [NOBORDER_LineL]),
        ("noborder-widget-tm.pdf", [NOBORDER_WidgetTm]),
        ("border-on-nontype.pdf", BORDER_ON_NONTYPE),
        ("bs-on-nontype.pdf", BS_ON_NONTYPE),
        ("act-goto-xyz.pdf", [ACT_GOTO_XYZ]),
        ("act-goto-fit.pdf", [ACT_GOTO_FIT]),
        ("act-goto-fitb.pdf", [ACT_GOTO_FITB]),
        ("act-goto-fith.pdf", [ACT_GOTO_FITH]),
        ("act-goto-fitbh.pdf", [ACT_GOTO_FITBH]),
        ("act-goto-fitbv.pdf", [ACT_GOTO_FITBV]),
        ("act-goto-zoom-int.pdf", [ACT_GOTO_ZOOM_INT]),
        ("act-goto-named.pdf", [ACT_GOTO_NAMED], [("dests", DESTS_TREE)], b" /Dests 8 0 R"),
        ("act-goto-named-dict.pdf", [ACT_GOTO_NAMED], [("dests", DESTS_DICT)], b" /Dests 8 0 R"),
        ("act-named-all.pdf", NAMED_ACTIONS),
        ("act-gotor-index.pdf", [ACT_GOTOR_INDEX, ACT_RESET_FLAGS_ONLY, ACT_RESET_EXCLUDE]),
        ("act-no-s.pdf", [ACT_NO_S]),
        ("act-unknown-s.pdf", [ACT_UNKNOWN_S]),
        ("act-goto-no-d.pdf", [ACT_GOTO_NO_D]),
        ("act-named.pdf", [ACT_NAMED_NEXT, ACT_NAMED_FIRST, ACT_NAMED_ZOOMIN, ACT_NAMED_NONSENSE]),
        ("act-uri.pdf", [ACT_URI, ACT_URI_NO_URI]),
        ("act-gotor.pdf", [ACT_GOTOR, ACT_GOTOR_NO_F, ACT_GOTOR_F_DICT]),
        ("act-reset.pdf", [ACT_RESET, ACT_RESET_NO_FIELDS, ACT_RESET_FLAGS]),
        ("act-goto-page2.pdf", [ACT_GOTO_PAGE2], (), b"", b"", 2),
        ("act-goto-bad-page.pdf", [ACT_GOTO_BAD_PAGE], (), b"", b"", 2),
        ("act-goto-badpage-xyz.pdf", [ACT_GOTO_BADPAGE_XYZ]),
        ("act-goto-shapes.pdf", [ACT_GOTO_XYZ_TWO, ACT_GOTO_XYZ_ONE, ACT_GOTO_XYZ_ZERO,
                                 ACT_GOTO_NO_PAGE_ARRAY, ACT_GOTO_D_NUMBER, ACT_GOTO_D_DICT,
                                 ACT_GOTO_PAGE_ONLY, ACT_GOTO_WRONG_NAME,
                                 ACT_GOTO_XYZ_NEGATIVE, ACT_GOTO_UNKNOWN_NAME,
                                 ACT_GOTO_NAME_ONLY]),
        ("act-goto-page2.pdf", [ACT_GOTOR_PAGE2], (), b"", b"", 2),
        ("act-reset-flags.pdf", ACT_RESET_FLAG_TABLE),
        ("act-uri-shapes.pdf", [ACT_URI_RELATIVE, ACT_URI_FRAGMENT]),
        ("act-gotor-http.pdf", [ACT_GOTOR_HTTP]),
        ("ann-dest-array.pdf", [ANN_DEST_ARRAY]),
        ("ann-dest-dict.pdf", [ANN_DEST_DICT]),
        ("ann-dest-fit.pdf", [ANN_DEST_FIT]),
        ("ann-dest-named.pdf", [ANN_DEST_NAMED], [("dests", DESTS_TREE)], b" /Dests 8 0 R"),
        ("ann-dest-named-dict.pdf", [ANN_DEST_NAMED], [("dests", DESTS_DICT)], b" /Dests 8 0 R"),
        ("ann-dest-and-a.pdf", [ANN_DEST_AND_A]),
        ("drops.pdf", DROPS),
        ("widget-bc.pdf", [BC_CMYK, BC_STRING, BC_NUMBER, BC_RGB]),
        ("popup-flags.pdf", [POPUP_F4, POPUP_F0, POPUP_F2, POPUP_NOF, SQUARE_F4, STAMP_F4]),
        ("widget-names.pdf", [WIDGET_T, WIDGET_T_NOFT, WIDGET_T_TX, WIDGET_TU_TX, WIDGET_NO_T,
                              SQUARE_T]),
        ("mk-full.pdf", [MK_FULL]),
        ("mk-bare.pdf", [MK_BARE]),
        ("mk-none.pdf", [MK_NONE]),
        ("mk-gray.pdf", [MK_GRAY]),
        ("mk-cmyk.pdf", [MK_CMYK]),
        ("mk-none-c.pdf", [MK_NONE_C]),
        ("mk-two.pdf", [MK_TWO]),
        ("mk-rot-real.pdf", [MK_ROT_REAL]),
        ("mk-r-zero.pdf", [MK_R_ZERO]),
    ]
    for name, annotations in (("annotation-colours.pdf", COLOUR_SHAPES),):
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, %d annotations" % (name, count, len(annotations)))
    for name, annotations in (("button-asoff-von.pdf", BUTTON_AS_OFF_V_ON),
                              ("button-v-only.pdf", BUTTON_V_ONLY),
                              ("button-asyes-voff.pdf", BUTTON_AS_YES_V_OFF),
                              ("button-ap-states.pdf", BUTTON_AP_STATES),
                              ("button-as-alone.pdf", BUTTON_AS_ALONE),
                              ("button-as-and-v.pdf", BUTTON_AS_AND_V),
                              ("text-as.pdf", TEXT_AS)):
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, %d annotations" % (name, count, len(annotations)))
    for value in (b"/Yes", b"/Off"):
        for state in (b"/Off", b"/On", b"/Yes"):
            name = "button-merged-v%s-as%s.pdf" % (value.decode().strip("/").lower(),
                                                  state.decode().strip("/").lower())
            count = build_merged_field(directory, name, _as_bytes(state),
                                       field_extra=b"/V " + value, field_type=b"/Btn")
            print("  wrote %-20s %d objects, a /Btn field /V %s and a widget /AS %s"
                  % (name, count, value.decode(), state.decode()))
    for index, annotations in enumerate(T_WITH_ONE_MORE):
        name = "widget-t-extra-%s.pdf" % T_WITH_ONE_MORE_NAMES[index]
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, /T plus one more key" % (name, count))
    for name, annotations in (("widget-t-literal.pdf", T_LITERAL),
                              ("widget-t-name.pdf", T_NAME),
                              ("widget-t-empty.pdf", T_EMPTY)):
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, %d annotations" % (name, count, len(annotations)))
    for name, child_extra in (("widget-t-merged.pdf", b""),
                              ("widget-t-mergedname.pdf", b" /T (child too)")):
        count = build_merged_field(directory, name, child_extra)
        print("  wrote %-20s %d objects, a widget whose /Parent is a field" % (name, count))
    for name, annotations in (("widget-flags.pdf", WIDGET_FLAGS),
                              ("widget-noflags.pdf", WIDGET_NO_FLAGS),
                              ("widget-allflags.pdf", WIDGET_ALL_FLAGS),
                              ("widget-fieldtypes.pdf", WIDGET_FIELD_TYPES),
                              ("widget-states.pdf", WIDGET_STATES),
                              ("widget-values.pdf", WIDGET_VALUES),
                              ("widget-mixed.pdf", WIDGET_MIXED),
                              ("synth-widgets.pdf", SYNTH_COUNT_WIDGETS_ONLY),
                              ("synth-linkfirst.pdf", SYNTH_COUNT_LINK_FIRST),
                              ("synth-linkmiddle.pdf", SYNTH_COUNT_LINK_MIDDLE)):
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, %d annotations" % (name, count, len(annotations)))
    for position, (field_type, annotations) in enumerate(WIDGET_FIELD_TYPES_ONE):
        # numbered, because the three /Ch fixtures share a field type and the first version of this named
        # them all widget-ftch.pdf, so each overwrote the last and only the first was ever measured
        name = "widget-ft%s%d.pdf" % (field_type.decode().strip("/").lower(), position)
        count, _ = build(os.path.join(directory, name), annotations)
        print("  wrote %-20s %d objects, %d annotations" % (name, count, len(annotations)))
    for name, spec, sign, signs, extra in (("outline-collapsed.pdf", OUTLINE_OPEN, -1, None, 0),
                                    ("outline-expanded.pdf", OUTLINE_CLOSED, 1, None, 0),
                                    ("outline-shapes.pdf", OUTLINE_SHAPES, -1, None, 0),
                                    ("outline-signs.pdf", OUTLINE_SIGNS, -1, OUTLINE_SIGNS_SIGNS, 0),
                                    ("outline-nocount.pdf", OUTLINE_NO_COUNT, -1, None, 0),
                                    ("outline-isopen.pdf", OUTLINE_ISOPEN, -1, None, 0),
                                    # the SAME shapes as outline-shapes.pdf with ONE annotation added to
                                    # the page, which shifts every object number after it.  Nothing about
                                    # the outline changes, so if -isOpen moves with it, the host's answer
                                    # for an item with no /Count is not a property of the document.
                                    ("outline-shapes2.pdf", OUTLINE_SHAPES, -1, None, 1),
                                    ("outline-untitled.pdf", OUTLINE_UNTITLED, -1, None, 0),
                                    ("outline-titled.pdf", OUTLINE_TITLED, -1, None, 0),
                                    ("outline-titlekey.pdf", OUTLINE_TITLE_KEY, -1, None, 0)):
        count, numbers, root, items = build_outline(directory, name, spec, sign, signs=signs,
                                                    extra=extra)
        print("  wrote %-20s %d objects, outline root %d, items %s" % (name, count, root,
                                                                       ",".join(str(i) for i in items)))
    for shape in shapes:
        name, annotations = shape[0], shape[1]
        extra = shape[2] if len(shape) > 2 else ()
        catalog_extra = shape[3] if len(shape) > 3 else b""
        page_count = shape[5] if len(shape) > 5 else 1
        count, _ = build(os.path.join(directory, name), annotations, extra, catalog_extra,
                         page_count=page_count)
        print("  wrote %-20s %d objects" % (name, count))


main()