#!/usr/bin/env python3
"""Fixtures whose /Widths and whose EMBEDDED FONT PROGRAM disagree, on purpose.

    make-font-fixtures.py <conforming-fixture.pdf> <directory>

`-[PDFSelection boundsForPage:]` is still `missing` because the width it answers cannot be
reproduced from what the file says: cgfixture-1.pdf's `/Widths` sum to 3058 per 1000 em (36.696pt at
12pt), its embedded `/FontFile2` program's own advances sum to 6264 units per 2048 em (36.7031pt at
12pt), and the host answers 36.7080 - a third number.  Two candidates 0.007pt apart cannot say
WHICH is read, because a rounding step in either reader explains the gap.

So the disagreement is made enormous instead of delicate.  Every fixture here writes the SAME text
("page 1") through the SAME embedded program, and moves `/Widths` far away from it, one direction per
fixture, named for the direction:

  widths-vs-program-wide      the six widths are 1000 each (72.0000pt), the program says 36.7031pt.
                              An answer near 72 read /Widths; an answer near 36.7031 read the PROGRAM.
  widths-vs-program-narrow    the six widths are 250 each (18.0000pt), the same program.  The same
                              three candidates from the other side, so one of the two fixtures is a
                              check on the other rather than a second reading of the first.
  no-font-program             no /FontFile2 at all, and the six widths are 1000 each (72.0000pt).
                              The system's own Helvetica advances for those codes come to 36.696pt, so
                              this asks the third question: does the host fall back to the font by
                              NAME over /BaseFont, with the "ABCDEF+" subset prefix stripped?
  broken-font-program         /FontFile2 at the right LENGTH and the wrong BYTES - the real program's
                              bytes with its sfnt version and table directory overwritten, so the
                              length is honest and the program is not a font.  This is the fixture
                              that decides whether the row is implemented-with-a-stated-boundary or
                              inert: it is what the host answers when NO reader can open the font.

WHY A BYTE-LEVEL WRITER AND NOT CGPDFContext: a conforming writer emits a CONSISTENT font - it
computes /Widths from the program it embeds - so it cannot write a disagreement, which is the whole
point of these four.  What is kept from the conforming writer is the PROGRAM, lifted verbatim out of
the /FontFile2 stream of a fixture it wrote, so it is a real font a real writer produced rather than
one synthesised here.  Every offset and every /Length below is measured from the bytes as they are
written, which is what `make-object-fixtures.py` does and what CGPDFScannerScan needs: the
hand-written annotation fixtures carry a /Length that does not match what the stream consumes, and
that is where the scanner stops returning.

The /Widths array is /FirstChar 32 .. /LastChar 112, all 81 codes, the same span cgfixture-1.pdf
writes, so the six codes the text uses are set here and the other 75 keep the conforming writer's own
0.  /Encoding /MacRomanEncoding and the descriptor's /Ascent 770 /Descent -230 are the same on all
four, so the y, the height and the x of every answer are the ones already measured.
"""
import re
import sys
import zlib

# The text every fixture draws, and where: make-pdf.m's own position, at /F1 12 Tf.  One show operator,
# six characters, and the codes are the ones whose /Widths entries move.
TEXT = b"BT /F1 12 Tf 72 720 Td (page 1) Tj ET\n"

# The codes "page 1" is made of, with what the conforming writer's /Widths says for each.  The six are
# every character in the string, so the answer's width is the sum of these six and nothing else.
CODES = [112, 97, 103, 101, 32, 49]                       # p a g e space 1

# The three candidate widths, in units of 1000 em, and the width each predicts at 12pt.  The gap
# between them is the point: 72.0000, 18.0000 and 36.6960 cannot be confused by any rounding.
WIDE = 1000
NARROW = 250

# The composite fixture's show operator: two-byte codes for "page 1", hex, no parentheses.  0x0070 p,
# 0x0061 a, 0x0067 g, 0x0065 e, 0x0020 space, 0x0031 one.
CID_TEXT = b"BT /F1 12 Tf 72 720 Td <006100650067006500200031> Tj ET\n"

# The STANDARD FOURTEEN of PDF 1.7 Table 7.21, in the spelling a /BaseFont name uses.  Symbol and
# ZapfDingbats are in the list because the format has them, and their code-to-glyph direction is not the
# Latin one - which the measurement over the fixtures settles rather than this comment.
BASE_FOURTEEN = ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique",
                 "Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
                 "Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic",
                 "Symbol", "ZapfDingbats"]


def widths_for(values, first=32, last=112):
    """The /Widths array over /FirstChar `first` .. /LastChar `last`, with `values` (by code) set.

    The span is a parameter because a font carrying a code at 0x80 or above has to reach it: a
    /FirstChar 32 /LastChar 112 array cannot hold code 0xE9, and a real /WinAnsiEncoding font spans
    0 .. 255, which is what the high-byte fixture writes.
    """
    row = [0] * (last - first + 1)
    for code, width in values.items():
        if not (first <= code <= last):
            raise SystemExit("code %d is outside the /Widths span %d..%d" % (code, first, last))
        row[code - first] = width
    return b"[" + b" ".join(b"%d" % v for v in row) + b"]"


def font_dict(descriptor_number, widths, program_number=None):
    body = (b"<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAB+Helvetica /FontDescriptor "
            + str(descriptor_number).encode() + b" 0 R /Encoding /MacRomanEncoding /FirstChar 32 "
            b"/LastChar 112 /Widths " + widths)
    if program_number is not None:
        body += b" /FontFile2 " + str(program_number).encode() + b" 0 R"
    return body + b" >>"


def descriptor(program_number=None):
    # The descriptor cgfixture-1.pdf's conforming writer wrote, with the numbers that decide the y and
    # the height: /Descent -230 gives 720 - 230 * 12 / 1000 = 717.24 and /Ascent 770 is the one that
    # would give 710.76, so a fixture that moves neither keeps every answer comparable.
    body = (b"<< /Type /FontDescriptor /FontName /AAAAAB+Helvetica /Flags 32 "
            b"/FontBBox [-951 -481 1445 1122] /ItalicAngle 0 /Ascent 770 /Descent -230 "
            b"/CapHeight 717 /StemV 0 /XHeight 523 /StemH 85 /AvgWidth 441 /MaxWidth 1500")
    if program_number is not None:
        body += b" /FontFile2 " + str(program_number).encode() + b" 0 R"
    return body + b" >>"


def build(path, widths, program, program_stream_bytes=None, text=TEXT):
    """1 catalog, 1 pages, 1 page, its content stream, the font, its descriptor, and the program.

    `program` is the sfnt bytes, or None for the fixture with no /FontFile2 at all.
    `program_stream_bytes` overrides what goes IN the stream, which is how the broken fixture keeps
    the right /Length and the wrong bytes.
    """
    # 1 catalog, 2 pages, 3 page, 4 content, 5 font, 6 descriptor, and 7 the program when there is one.
    has_program = program is not None
    program_number = 7 if has_program else None
    contents = b"<< /Length " + str(len(text)).encode() + b" >>\nstream\n" + text + b"\nendstream"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
         b"/Resources << /Font << /F1 5 0 R >> >> >>"),
        contents,
        font_dict(6, widths, program_number),
        descriptor(program_number),
    ]
    if has_program:
        raw = program if program_stream_bytes is None else program_stream_bytes
        if program_stream_bytes is None:
            # the real program, DEFLATEd because the fixture it came from was, and /Length1 beside
            # /Length is what names the UNCOMPRESSED size - a reader that trusts /Length1 on a
            # program that is not compressed gets the wrong bytes, which is the broken fixture's own
            # trick and not this one's.
            body = zlib.compress(raw)
            objects.append(b"<< /Length " + str(len(body)).encode() + b" /Length1 "
                           + str(len(raw)).encode() + b" /Filter /FlateDecode >>\nstream\n" + body
                           + b"\nendstream")
        else:
            objects.append(b"<< /Length " + str(len(raw)).encode() + b" >>\nstream\n" + raw
                           + b"\nendstream")
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
    return len(objects)


def lift_program(conforming):
    """The /FontFile2 stream of a fixture a CONFORMING writer wrote, decompressed.

    Not synthesised: a real font program, out of a real document, and the four fixtures differ from
    each other only in /Widths and in whether the /FontFile2 key is there at all.
    """
    data = open(conforming, "rb").read()
    match = re.search(rb"/FontFile2 (\d+) 0 R", data)
    if match is None:
        raise SystemExit("%s carries no /FontFile2, so there is no program to lift" % conforming)
    number = int(match.group(1))
    start = data.index(b"\n%d 0 obj" % number)
    body = data[start:data.index(b"endobj", start)]
    if b"/FlateDecode" in body:
        begin = body.index(b"stream\n") + len(b"stream\n")
        end = body.index(b"\nendstream", begin)
        return zlib.decompress(body[begin:end])
    begin = body.index(b"stream\n") + len(b"stream\n")
    return body[begin:body.index(b"\nendstream", begin)]


def build_type1(path, basefont, encoding, text, widths=None, descriptor=True, first=32, last=112):
    """A SIMPLE font whose /Widths may be absent, over one of the base fourteen.

    `widths=None` writes NO /Widths at all, which is the shape every base-fourteen font in a real
    document has and the shape the /Widths rule above cannot answer by itself.  The base font is a
    parameter and not always Helvetica because the candidates have to be FAR APART: Helvetica's AFM
    widths for "page 1" are 3058 per 1000 em and Courier's are 3600, so a font with no /Widths answers
    one number or the other and a reader that cannot tell them apart has not been asked anything.
    """
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
         b"/Resources << /Font << /F1 5 0 R >> >> >>"),
        b"<< /Length " + str(len(text)).encode() + b" >>\nstream\n" + text + b"\nendstream",
        (b"<< /Type /Font /Subtype /Type1 /BaseFont /" + basefont + b" /Encoding /" + encoding
         + (b" /FirstChar " + str(first).encode() + b" /LastChar " + str(last).encode()
            + b" /Widths " + widths if widths is not None else b"")
         + (b" /FontDescriptor 6 0 R" if descriptor else b"") + b" >>"),
        (b"<< /Type /FontDescriptor /FontName /" + basefont + b" /Flags 32 "
         b"/FontBBox [-166 -225 1000 931] /ItalicAngle 0 /Ascent 770 /Descent -230 "
         b"/CapHeight 717 /StemV 88 /XHeight 523 /StemH 88 /AvgWidth 441 /MaxWidth 1500 >>"),
    ]
    write_pdf(path, objects)


def build_cid(path, widths_w, program, encoding=b"Identity-H"):
    """A COMPOSITE (Type0) font: a two-byte code, a /W array by CID, and a /CIDToGIDMap.

    The text is a hex string of two-byte codes, so the show operator carries six 2-byte codes where
    every other fixture here carries six 1-byte ones, and the widths come from /W rather than
    /Widths.  It is the shape that decides whether the row needs the CID direction at all.
    """
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
         b"/Resources << /Font << /F1 5 0 R >> >> >>"),
        b"<< /Length " + str(len(CID_TEXT)).encode() + b" >>\nstream\n" + CID_TEXT + b"\nendstream",
        (b"<< /Type /Font /Subtype /Type0 /BaseFont /AAAAAB+Helvetica /Encoding /" + encoding
         + b" /DescendantFonts [7 0 R] >>"),
        b"<< /Length 1 >>\nstream\n \nendstream",      # 6 0 obj, a stream nothing reads
        (b"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /AAAAAB+Helvetica "
         b"/FontDescriptor 8 0 R /DW 1000 /W " + widths_w + b" /CIDToGIDMap /Identity >>"),
        (b"<< /Type /FontDescriptor /FontName /AAAAAB+Helvetica /Flags 4 "
         b"/FontBBox [-951 -481 1445 1122] /ItalicAngle 0 /Ascent 770 /Descent -230 "
         b"/CapHeight 717 /StemV 0 /XHeight 523 /StemH 85 /AvgWidth 441 /MaxWidth 1500 "
         b"/FontFile2 9 0 R >>"),
        b"<< /Length " + str(len(zlib.compress(program))).encode() + b" /Length1 "
        + str(len(program)).encode() + b" /Filter /FlateDecode >>\nstream\n"
        + zlib.compress(program) + b"\nendstream",
    ]
    write_pdf(path, objects)


def write_pdf(path, objects):
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
    return len(objects)


def main():
    args = [a for a in sys.argv[1:] if a != "--with-matrix"]
    with_matrix = "--with-matrix" in sys.argv[1:]
    if len(args) != 2:
        raise SystemExit("usage: make-font-fixtures.py [--with-matrix] <conforming.pdf> <directory>")
    conforming, directory = args[0], args[1]
    program = lift_program(conforming)
    all_six = {code: WIDE for code in CODES}
    small_six = {code: NARROW for code in CODES}

    # 1. /Widths wide, the program as lifted
    build(directory + "/cgfixture-widths-vs-program-wide.pdf", widths_for(all_six), program)
    # 2. /Widths narrow, the same program
    build(directory + "/cgfixture-widths-vs-program-narrow.pdf", widths_for(small_six), program)
    # 3. NO /FontFile2 at all
    build(directory + "/cgfixture-no-font-program.pdf", widths_for(all_six), None)
    # 4. /FontFile2 at the right LENGTH and the wrong BYTES: the sfnt version and the table directory
    #    overwritten with zeros, so the stream is the program's size and not a font.
    broken = bytearray(program)
    broken[0:12] = b"\0" * 12
    build(directory + "/cgfixture-broken-font-program.pdf", widths_for(all_six), bytes(broken), bytes(broken))

    # 5 and 6. THE CHARACTER SPACING, which is the whole of cgfixture-1.pdf's 0.012pt excess and the one
    #    text-state operator the /Widths rule above does not model.  cgfixture-1.pdf's own content
    #    stream is
    #
    #        BT 0.0002 Tc 12 0 0 12 20 360 Tm /TT1 1 Tf (page 1) Tj 0 Tc ET
    #
    #    so it draws with Tc = 0.0002 and its /Widths sum to 36.6960 while the host answers 36.7080 -
    #    0.0120 more.  Both fixtures here carry THE SAME /Widths and THE SAME program as each other
    #    and differ only in that operator, so the difference between their answers is the operator and
    #    nothing else:
    #
    #      text-tc     Tc 0.0002, exactly cgfixture-1.pdf's own stream
    #      text-no-tc  no Tc at all
    #
    #    0.0002 is not a round number by accident: CGPDFContext writes it, and it is small enough that
    #    a reader that rounds its advance to 1/1000 em (the quantum the answers below are on) keeps
    #    it, which is why the excess is measurable at all.
    helv_six = {code: (556 if code != 32 else 278) for code in CODES}
    helv = widths_for(helv_six)
    build(directory + "/cgfixture-text-tc.pdf", helv, program,
          text=b"BT 0.0002 Tc 12 0 0 12 72 720 Tm /F1 1 Tf (page 1) Tj 0 Tc ET\n")
    build(directory + "/cgfixture-text-no-tc.pdf", helv, program,
          text=b"BT 12 0 0 12 72 720 Tm /F1 1 Tf (page 1) Tj ET\n")
    #    and the same stream with Tc TEN TIMES bigger, which is the one measurement that says whether
    #    the excess is a term in Tc or a rounding artefact that happens to land there: a linear term
    #    answers 36.6960 + 0.1200 = 36.8160.
    #
    #    ALL THREE CARRY AN IDENTITY TEXT MATRIX and /F1 12 Tf, so that Tf's operand IS the effective
    #    size and Tc is the only thing that varies between them.  An earlier draft of these three wrote
    #    `/F1 1 Tf` under a `12 0 0 12` Tm, which is the same twelve effective points - and that is how
    #    the run showed the effective size is Tf TIMES Tm's scale rather than Tf alone.  The three below
    #    are the clean versions, and the two after them are what pins the scale.
    helv = widths_for(helv_six)
    build(directory + "/cgfixture-text-tc.pdf", helv, program,
          text=b"BT 0.0002 Tc /F1 12 Tf 72 720 Td (page 1) Tj 0 Tc ET\n")
    build(directory + "/cgfixture-text-no-tc.pdf", helv, program,
          text=b"BT /F1 12 Tf 72 720 Td (page 1) Tj ET\n")
    build(directory + "/cgfixture-text-tc10.pdf", helv, program,
          text=b"BT 0.002 Tc /F1 12 Tf 72 720 Td (page 1) Tj 0 Tc ET\n")
    #    The TEXT MATRIX'S SCALE, which is the second thing the first round got wrong.  `Tm` is 12 0 0 12
    #    with /F1 1 Tf, so the effective size is twelve and the answer is the /Widths sum at twelve.  The
    #    flat one is 24 0 0 6 with /F1 12 Tf: horizontal scale 24 and vertical 6, which separates "the
    #    scale is a and d separately" from "the scale is d alone" - 880.7040 against 220.1760 - and the
    #    skew one has b and c non-zero with a and d at 12, which is a control on the family.
    #
    #    The last two are MEASUREMENT ONLY and --with-matrix is what writes them, so the differential does
    #    not carry them.  The reason is measured and it is not this row's business: with a non-uniform or a
    #    skewed Tm the HOST's own text extraction stops early - it answers "page" for the flat one and
    #    "pag" for the skew one, where the stream draws "page 1" - so there is no selection over those
    #    glyphs to ask -boundsForPage: about, and putting them in the differential would report a
    #    -string divergence about a text-extraction behaviour neither this row nor the walk has measured.
    build(directory + "/cgfixture-text-matrix-scale.pdf", helv, program,
          text=b"BT 12 0 0 12 72 720 Tm /F1 1 Tf (page 1) Tj ET\n")
    if with_matrix:
        build(directory + "/cgfixture-text-matrix-flat.pdf", helv, program,
              text=b"BT 24 0 0 6 72 720 Tm /F1 12 Tf (page 1) Tj ET\n")
        build(directory + "/cgfixture-text-matrix-skew.pdf", helv, program,
              text=b"BT 12 6 0 12 72 720 Tm /F1 12 Tf (page 1) Tj ET\n")
    # 7. A BASE-FOURTEEN FONT WITH NO /Widths AT ALL, which is the shape every document that relies on
    #    one of the standard fourteen carries, and the shape the /Widths rule cannot answer.  Courier is
    #    the font and not Helvetica because the candidates have to be far apart: Courier's AFM widths
    #    for these six codes are 600 each (43.2000pt at 12pt) and Helvetica's are 556/278 (36.6960pt),
    #    so an answer near 43.2 is a reader that reached the font BY NAME and an answer near 36.696 is
    #    a reader with a table of its own.
    build_type1(directory + "/cgfixture-base14-no-widths.pdf", b"Courier", b"WinAnsiEncoding",
                b"BT /F1 12 Tf 72 720 Td (page 1) Tj ET\n")
    # 8. THE SAME, WITH /Widths, so the pair says whether the name is consulted only when /Widths is
    #    absent - the one shape that decides whether the port needs CGFontCreateWithFontName at all.
    build_type1(directory + "/cgfixture-base14-with-widths.pdf", b"Courier", b"WinAnsiEncoding",
                b"BT /F1 12 Tf 72 720 Td (page 1) Tj ET\n",
                widths=b"[" + b" ".join(b"600" for _ in range(81)) + b"]")
    # 9. A CODE AT 0x80 OR ABOVE: one byte 0xE9 in a /WinAnsiEncoding font, which the encoding resolves
    #    to U+00E9.  It is asked as its own needle and as part of a word, because the two answers are
    #    different questions: what the walk KEEPS for the character, and what WIDTH the rect gives it.
    build_type1(directory + "/cgfixture-high-byte.pdf", b"Helvetica", b"WinAnsiEncoding",
                b"BT /F1 12 Tf 72 720 Td (caf\351) Tj ET\n",
                widths=widths_for({99: 500, 97: 556, 102: 278, 233: 556}, first=0, last=255),
                first=0, last=255)
    # NOT WRITTEN: A COMPOSITE (Type0) FONT.  The code for it is here and it is switched off, because the
    # fixture does not measure what it was built to measure: with /Identity-H, a /CIDFontType2
    # descendant, /W by CID and /CIDToGIDMap /Identity, and a hex show string of two-byte codes, the
    # HOST'S OWN page text is "page" for one of them and "pag" for the other, where the stream draws
    # "page 1" - so there is no selection over those glyphs for -boundsForPage: to be asked about, and
    # what the fixture would have added to the differential is a -numberOfCharacters divergence about a
    # text-extraction behaviour neither this row nor the walk has measured.  The /W and /CIDToGIDMap
    # direction is therefore NOT measured and NOT claimed: facts/PDFKit/Selection11.md says so, and the
    # row's boundary names it.
    #
    # build_cid(directory + "/cgfixture-cid.pdf", b"[1 [700 700 700 700 700 700]]", program)
    print("wrote %d font fixtures into %s from a %d byte program"
          % (13 + 4 * len(BASE_FOURTEEN), directory, len(program)))


if __name__ == "__main__":
    main()