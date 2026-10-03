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


def annot(kind, extra):
    body = b"<< /Type /Annot /Subtype /" + kind
    for key, value in extra:
        body += b" /" + key + b" " + value
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
    for shape in shapes:
        name, annotations = shape[0], shape[1]
        extra = shape[2] if len(shape) > 2 else ()
        catalog_extra = shape[3] if len(shape) > 3 else b""
        page_count = shape[5] if len(shape) > 5 else 1
        count, _ = build(os.path.join(directory, name), annotations, extra, catalog_extra,
                         page_count=page_count)
        print("  wrote %-20s %d objects" % (name, count))


main()