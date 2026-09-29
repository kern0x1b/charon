#!/usr/bin/env python3
"""cldr-factors.py - CLDR's own conversion data, evaluated exactly.

The unit *identifiers* live in the locale files, `common/main/<locale>.xml`, as
`<unit type="length-mile">`; the *conversions* live in `common/supplemental/units.xml`, as
`<convertUnit source='mile' baseUnit='meter' factor='ft_to_m*5280'/>` - the bare id, not the
quantity-prefixed one - with the factors written as expressions over `<unitConstant>` entries and,
for temperature, an offset beside them. So the join is: take the id from the locale file, strip the
quantity prefix, and look the bare id up here.

Everything is a `Fraction`, so `ft_to_m*5280` and `5/9` and `2298.35/9` are exact and not
floats. Nothing here guesses: an id CLDR does not carry is reported as absent, and a factor that
is not an expression of the constants is refused rather than evaluated as text.

    cldr-factors.py --verify                 the three controls, which fail the script if wrong
    cldr-factors.py --list length            every length id with its base unit and factor
    cldr-factors.py --factor mile            one id's factor and offset, exact
"""

import argparse
import hashlib
import io
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_PIN = os.path.join(HERE, "PIN")
DEFAULT_ARCHIVE = os.path.join(os.path.dirname(HERE), "..", ".agent-work", "downloads",
                               "cldr-release-48.zip")
TOP = "cldr-release-48/"

# a constant may carry status= and description= beside its name and value, and its value may be
# written in scientific notation (AMU), which is a decimal here and is turned into its exact rational
CONSTANT = re.compile(r"<unitConstant\s+constant=\"([^\"]+)\"\s+value=\"([^\"]+)\"")
# the quantity names of this release, which are what a hyphen in an id separates: the ids that
# carry one of them are quantity-prefixed and convertUnit knows only the bare name
UNIT_QUANTITY = re.compile(r"<unitQuantity[^>]*quantity='([^']+)'")
# The port's own class-to-quantity table names three quantities by a short form this release does not
# use: it writes electric-charge, electric-current and electric-resistance, and the port groups all
# three classes under electric; it writes concentration and concentration-mass where the port says
# concentr; and it writes light-radiance and light-luminance where the port says light. So the set of
# names a leading segment may be is the archive's own quantities and these, declared here rather than
# imported, because cldr_factors is below cldr_map in the tool and does not know the port's classes.
PORT_QUANTITIES = ("concentr", "electric", "light")
CONVERT = re.compile(r"<convertUnit\s+source='([^']+)'\s+baseUnit='([^']+)'\s*(factor='([^']*)')?"
                    r"\s*(offset='([^']*)')?\s*[^/]*/>")
LOCALE_UNIT = re.compile(r'<unit type="([^"]+)"')
# the metric prefix multiples - length-kilometer, length-millimeter - carry no convertUnit at all: CLDR
# derives them from the base unit and the prefix's own power10, and both are in this same file. So a
# factor is computed the way CLDR computes it, and compared exactly like the rest.
PREFIX = re.compile(r"<unitPrefix type='([^']+)'\s+symbol='?([^'\s]*)\s*'?\s*power10='(-?\d+)'")


def pinned_sha(pin):
    with open(pin, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("- sha256:"):
                return line.split(":", 1)[1].strip()
    return None


def verify_archive(archive, pin):
    """the pin's whole sha, and the archive has to be it, before anything is read"""
    import hashlib
    wanted = pinned_sha(pin)
    if wanted is None or len(wanted) != 64:
        print("the pin at %s does not name a 64-character sha256" % pin, file=sys.stderr)
        return False
    digest = hashlib.sha256()
    with open(archive, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 22), b""):
            digest.update(block)
    if digest.hexdigest() != wanted:
        print("the archive is %s and the pin says %s" % (digest.hexdigest(), wanted), file=sys.stderr)
        return False
    return True



# CLDR's own grammar, from the DTD the archive carries (common/dtd/ldmlSupplemental.dtd, verbatim):
#   <!ATTLIST convertUnit factor CDATA #IMPLIED >
#     <!--@MATCH:regex/[-+*/\._ 0-9a-zA-Z]+-->
#   <!ATTLIST convertUnit offset CDATA #IMPLIED >
#     <!--@MATCH:regex/[-+*/\._ 0-9a-zA-Z]+-->
# So an expression is made of numbers, identifiers, the four operators, and parentheses, with '.' for the
# decimal point and '_' inside a constant's name. The DTD fixes the alphabet and says nothing about
# precedence, so the one rule below is settled by the file's own data: a '/' divides by the PRODUCT of the
# factors that follow it, which is what turns the file's
#   <convertUnit source='teaspoon' baseUnit='cubic-meter' factor='gal_to_m3/16*48' systems="ussystem"/>
# into a US teaspoon of gallon/768 - 16 times 48 is 768 - where reading it left to right gives three
# gallons, which is three tablespoons.
TOKEN = re.compile(r"0[xX][0-9a-fA-F.]+[pP][-+]?[0-9]+"          # a hex float, 0x1p+0
                   r"|[0-9]*\.[0-9]+(?:[eE][-+]?[0-9]+)?"         # a decimal, 1. and 1.6
                   r"|[0-9]+(?:\.[0-9]*)?(?:[eE][-+]?[0-9]+)?"   # an integer or 1e-9
                   r"|[A-Za-z][A-Za-z0-9_]*"                        # a named constant
                   r"|[-+*/()]")


def factor_eval(text, constants):
    """one factor or offset string, evaluated exactly, over Fractions."""
    tokens = [m.group(0) for m in TOKEN.finditer(text)]
    if "".join(tokens) != "".join(text.split()):
        raise ValueError("not a whole expression: %r" % text)
    at = [0]

    def peek():
        return tokens[at[0]] if at[0] < len(tokens) else None

    def take():
        token = peek()
        at[0] += 1
        return token

    def number(token):
        return _number(token)

    def atom():
        token = take()
        if token == "(":
            value = expr()
            if take() != ")":
                raise ValueError("no closing parenthesis in %r" % text)
            return value
        if token == "-":
            return -atom()
        if token == "+":
            return atom()
        if token in constants:
            return constants[token]
        try:
            return number(token)
        except (ValueError, ZeroDivisionError):
            raise ValueError("not a number and not a constant: %r" % token)

    def term():
        value = atom()
        while peek() in ("*", "/"):
            if take() == "*":
                value = value * atom()
                continue
            # the rule: a slash divides by the product of the factors that follow it
            divisor = atom()
            while peek() == "*":
                take()
                divisor = divisor * atom()
            value = value / divisor
        return value

    def expr():
        value = term()
        while peek() in ("+", "-"):
            operator = take()
            right = term()
            value = value + right if operator == "+" else value - right
        return value

    value = expr()
    if at[0] != len(tokens):
        raise ValueError("trailing text in %r" % text)
    return value


def expression(text, constants):
    """an expression of the constants, exactly: products, quotients, and a fraction's denominator.

    Only what CLDR writes is accepted - numbers, one named constant or another, `*` and `/` - and
    anything else is refused, so a value never comes from evaluating text.
    """
    # A slash divides by the PRODUCT of everything after it. The file writes
    #   <convertUnit source='teaspoon' baseUnit='cubic-meter' factor='gal_to_m3/16*48' systems="ussystem"/>
    # and a US teaspoon is a gallon over 768, and 16 times 48 is 768. Read left to right the expression
    # is three gallons - three tablespoons - and that is what put 235.48 in the table and made CLDR's own
    # data look like it was in a foreign scale. Every other line has one term after the slash, so only the
    # teaspoon was wrong, and it was wrong by exactly that factor.
    return factor_eval(text, constants)


def _number(text):
    """a number, exactly, including the scientific notation CLDR writes its constants in"""
    text = text.strip()
    if re.match(r"^[0-9.]+[eE][-+]?[0-9]+$", text):
        mantissa, exponent = re.split("[eE]", text)
        sign = -1 if exponent.startswith("-") else 1
        return Fraction(mantissa) * Fraction(10) ** (sign * int(exponent.lstrip("-+")))
    return Fraction(text)


def _value(token, constants):
    token = token.strip()
    if token in constants:
        return constants[token]
    return _number(token)


def _is_number(text):
    try:
        _number(text)
        return True
    except (ValueError, ZeroDivisionError):
        return False


def _units_by_width(stream):
    """(id, width) -> the text after "{0} " in that unit's pattern, from en's parsed unit data.

    The three widths are siblings under the locale's <units>, and the file has no ldml wrapper in this
    release, so the walk is <units>/<unitLength type=…>/<unit type=…>/<unitPattern count=…>. The
    "other" count is the one a formatter uses for a value, and the "one" form is kept when there is no
    other.
    """
    root = ET.parse(stream).getroot()
    units = root.find("units")
    if units is None:
        units = root.find("ldml/units")
    found = {}
    if units is None:
        return found
    for length in units.findall("unitLength"):
        width = length.get("type") or "long"
        for unit in length.findall("unit"):
            patterns = {}
            for pattern in unit.findall("unitPattern"):
                if pattern.get("count") in ("other", "one") and pattern.text:
                    patterns[pattern.get("count")] = pattern.text.strip()
            text = patterns.get("other") or patterns.get("one")
            if not text:
                continue
            head, _, tail = text.partition("{0}")
            name = tail.strip() or head.strip()
            if name:
                found.setdefault(unit.get("type"), {})[width] = name
    return found


class Cldr(object):
    def __init__(self, archive):
        with zipfile.ZipFile(archive) as z:
            self.units_xml = z.read(TOP + "common/supplemental/units.xml").decode("utf-8", "replace")
            self.root_xml = z.read(TOP + "common/main/root.xml").decode("utf-8", "replace")
            # The symbols come from en's unit data, parsed and not grepped: it keeps each unit's
            # pattern at three widths - long "{0} hours", short "{0} hr", narrow "{0}h" - and the
            # port's spellings are the short ones. A regex over this file finds the long form and
            # misses the width the port uses, which is the whole of the difference between an hour
            # named "h" and one named "hr".
            self.en_units = _units_by_width(io.BytesIO(z.read(TOP + "common/main/en.xml")))
        # a constant may be written over the ones above it - ft2_to_m2 is ft_to_m*ft_to_m - so they are
        # resolved in the order the file writes them, each against those already resolved
        self.constants = {}
        for name, value in CONSTANT.findall(self.units_xml):
            self.constants[name] = expression(value, self.constants)
        self.quantities = set(UNIT_QUANTITY.findall(self.units_xml)) | set(PORT_QUANTITIES)
        self.conversions = {}
        for source, base, _factor, factor, _offset, offset in CONVERT.findall(self.units_xml):
            self.conversions[source] = (base,
                                        expression(factor, self.constants) if factor else Fraction(1),
                                        expression(offset, self.constants) if offset else Fraction(0))
        # the locale files carry the quantity-prefixed id and the display name; the join strips the
        # quantity to reach the bare id convertUnit uses
        self.prefixes = {}
        for kind, symbol, power in PREFIX.findall(self.units_xml):
            self.prefixes[kind] = (symbol, int(power))
        self.identifiers = {}
        for kind, body in re.findall(r'<unit type="([^"]+)">(.*?)</unit>', self.root_xml, re.S):
            display = re.search(r"<displayName>([^<]*)</displayName>", body)
            self.identifiers[kind] = (None, display.group(1) if display else None)

    def symbols_of(self, kind):
        """every width en writes for the unit, short first: {0} hr, {0} h, {0} hours.

        The port's symbols are the short ones, so the order the widths are tried in is the order the
        port is matched in, and the width that matched is kept on the row.
        """
        return self.en_units.get(kind) or {}

    def symbol_of(self, kind):
        """the symbol the port would spell it with, which is the first width that carries one"""
        widths = self.symbols_of(kind)
        for width in ("short", "narrow", "long"):
            if width in widths:
                return widths[width]
        return None

    def width_of(self, kind, symbol):
        """the width the given spelling matched at, or None when no width has it"""
        return next((width for width, value in self.symbols_of(kind).items() if value == symbol), None)

    def quantity(self, kind):
        return kind.split("-", 1)[0] if "-" in kind else None

    def bare(self, kind):
        """the id convertUnit is written under: a quantity-prefixed id loses its quantity segment.

        Only a quantity of this release is a segment: gallon-imperial and mile-per-gallon are one name
        each, and stripping the first word of them asked convertUnit for a unit called "imperial", which
        is why the imperial gallon read as carrying no conversion while the table held it exactly.
        """
        head, _, tail = kind.partition("-")
        if tail and head in self.quantities:
            return tail
        return kind

    def factor(self, kind):
        """(factor, offset) to CLDR's own base unit, exactly, or None when CLDR has no entry.

        A plain id comes from convertUnit. A prefix multiple has no convertUnit of its own: its factor is
        the base unit's times the prefix's power10, which is CLDR's own arithmetic. Its id is the *prefix
        name and the base name joined into one segment* - length-kilometer is "kilo" + "meter", not
        length-kilo-meter - so each base of the quantity is tried against each prefix.
        """
        entry = self.conversions.get(self.bare(kind))
        if entry is not None:
            return entry[1], entry[2]
        quantity = self.quantity(kind)
        if quantity is None:
            return None
        tail = self.bare(kind)
        scales = dict(self.prefixes)
        for base_kind in self.identifiers_in(quantity):
            base_tail = self.bare(base_kind)
            if not base_tail or tail == base_tail or not tail.endswith(base_tail) or len(base_tail) >= len(tail):
                continue
            lead = tail[:-(len(base_tail))]
            base = self.factor(base_kind)
            if base is None:
                continue
            if lead in scales:
                return base[0] * (Fraction(10) ** scales[lead][1]), base[1]
            if lead in self.powers:
                # a composed id: the power multiplies the factor, the way CLDR means it
                return base[0] * (Fraction(10) ** self.powers[lead]), base[1]
        return None

    def identifiers_in(self, quantity):
        return sorted(k for k in self.identifiers if self.quantity(k) == quantity)


# The three controls. They fail the script when they do not hold, because a factor that is
# approximately right is a table that is wrong for some locale and nobody can see which.
CONTROLS = [
    # the grammar, on the file's own line: a slash divides by the PRODUCT of everything after it, which
    # is why a teaspoon is written gal_to_m3/16*48 and is a gallon over 768
    ("teaspoon", None, None, "gal_to_m3/16*48 = gal_to_m3/(16*48), the grammar on a/b*c"),
    # the US gallon in cubic metres, from 231 inches of 0.0254 m
    ("gallon", None, None, "gallon = 473176473/125000000000 m3"),
    # the prefix multiples, computed rather than read: the file has no convertUnit for them
    ("length-kilometer", Fraction(1000), Fraction(0), "kilometer -> 1000 (kilo x meter)"),
    ("length-millimeter", Fraction(1, 1000), Fraction(0), "millimeter -> 1/1000 (milli x meter)"),
    ("foot", Fraction("0.3048"), Fraction(0), "foot -> 0.3048"),
    ("mile", Fraction(3048, 10000) * 5280, Fraction(0), "mile -> 1609.344"),
    ("fahrenheit", Fraction(5, 9), Fraction("2298.35") / 9, "fahrenheit -> 5/9, offset 2298.35/9"),
    ("celsius", Fraction(1), Fraction("273.15"), "celsius -> offset 273.15, factor 1"),
]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--archive", default=DEFAULT_ARCHIVE)
    parser.add_argument("--pin", default=DEFAULT_PIN)
    parser.add_argument("--verify", action="store_true", help="run the controls and stop")
    parser.add_argument("--list", help="every id of a quantity, with its factor and offset")
    parser.add_argument("--factor", help="one id's factor and offset, exact")
    arguments = parser.parse_args(argv)

    if not verify_archive(arguments.archive, arguments.pin):
        return 2
    cldr = Cldr(arguments.archive)

    if arguments.verify:
        bad = 0
        for kind, factor, offset, description in CONTROLS:
            if factor is None and offset is None and "=" in description:
                # a grammar control: the expression itself, not an entry
                left, _, right = description.partition(" = ")
                if left.startswith("gal_to_m3/"):
                    value = expression(left, cldr.constants)
                    want = expression("gal_to_m3/(16*48)", cldr.constants)
                    if value == want:
                        print("ok   %s" % description)
                    else:
                        print("FAIL %s: %s is not %s" % (description, value, want))
                        bad += 1
                    continue
                if left == "gallon":
                    inch = Fraction(254, 10000)
                    want = 231 * inch ** 3
                    if cldr.constants.get("gal_to_m3") == want:
                        print("ok   %s" % description)
                    else:
                        print("FAIL %s: the file says %s" % (description, cldr.constants.get("gal_to_m3")))
                        bad += 1
                    continue
            got = cldr.factor(kind)
            if got is None:
                print("FAIL %s: the evaluator has no factor for it" % description)
                bad += 1
                continue
            base = cldr.conversions.get(cldr.bare(kind), (None, None, None))[0]
            want_factor, want_offset = got
            if want_factor != factor or want_offset != offset:
                print("FAIL %s: the file says factor %s offset %s" % (description, want_factor, want_offset))
                bad += 1
            else:
                print("ok   %s (base %s)" % (description, base))
        print("%d controls, %d failed" % (len(CONTROLS), bad))
        return 1 if bad else 0

    if arguments.list:
        for kind in cldr.identifiers_in(arguments.list):
            entry = cldr.factor(kind)
            print("%-28s %-18s factor %s%s" % (kind, (cldr.identifiers[kind][0] or ""),
                                                entry[0] if entry else "(no conversion)",
                                                (" offset %s" % entry[1]) if entry and entry[1] else ""))
        return 0

    if arguments.factor:
        entry = cldr.factor(arguments.factor)
        if entry is None:
            print("CLDR carries no conversion for %s" % arguments.factor, file=sys.stderr)
            return 2
        print("%s: factor %s offset %s" % (arguments.factor, entry[0], entry[1]))
        return 0

    parser.error("nothing to do: --verify, --list <quantity> or --factor <id>")
    return 2


if __name__ == "__main__":
    sys.exit(main())
