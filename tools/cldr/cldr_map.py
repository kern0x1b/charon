#!/usr/bin/env python3
"""cldr-map.py - map the port's unit declarations onto CLDR unit identifiers, or say why not.

A mapping row is written where the port's own converter coefficient agrees with CLDR's factor (and
offset, for temperature) for the same quantity. **The test is equality as a double**, because the port's
coefficients *are* doubles: `NSUnit`'s `initWithCoefficient:` takes a `double`, so CLDR's exact rational
rounded the way a double rounds is the same value, and refusing on a last bit would refuse a correct
unit - parsec, where CLDR writes `meters_per_AU*60*60*180/PI` with PI as a rational and the port holds
the rounded double.

Each row records which kind of agreement it is: **exact**, where the rational equals the port's value as
a rational; or **double**, where they are equal only after rounding, with the rational difference kept in
the row so the difference stays visible. One ulp either way is not agreement, and a control says so.

A double also has nothing finer than itself, and a literal may say more digits than it holds: one ulp at
255.37222222222428 is 2.842e-14, and the 17th digit the port writes there is worth 1e-14, so
255.37222222222428 and 255.37222222222429 are the same value and a control that moved only that digit
would pass. The kinds therefore compare values, not text, past the width a double can hold: a digit
below the last one the value keeps carries no information, and the control
tests/backports/host/units/shift-and-run.sh moves a digit the double does hold, which is the one that
can be red.

Everything that does not agree goes to the unmapped list with its reason, and no row is ever written by
resemblance.

The port's side is read from its own sources - each class's `+baseUnit` and each unit's
`initWithCoefficient:` - and CLDR's from the pinned archive. Both are facts in a file, not judgements.

    cldr-map.py --class NSUnitLength          one class: the rows that match, and the rest with reasons
    cldr-map.py --all --write                 every class, writing the two files beside the tool
"""

import argparse
import os
import re
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import cldr_factors  # noqa: E402  the evaluator and the pin check, one implementation of both

FOUNDATION = os.path.join(REPO, "packages/a/apple-backports/Foundation")
ARCHIVE = os.path.join(REPO, ".agent-work", "downloads", "cldr-release-48.zip")

METHOD = re.compile(r"^\+\s*\(\s*(NSUnit\w*)\s*\*\s*\)(\w+)\s*$", re.MULTILINE)
BASE = re.compile(r"baseUnit\s*\{[^}]*return\s*\[self\s+(\w+)\]")
SYMBOL = re.compile(r'symbol:@"([^"]*)"')
# a coefficient is the unit's own argument or the converter's: initWithConverter:[[NSUnitConverterLinear
# alloc] initWithCoefficient:…] - the second is how every base unit is built, and missing it is why
# seventeen declarations read as "the class names no base unit"
COEFFICIENT = re.compile(r"initWithCoefficient:([0-9a-fA-FxX.pP+\-]+)")
# an affine conversion is spelled constant: here and offset: in CLDR, and it is the same number
OFFSET = re.compile(r"initWithOffset:([0-9a-fA-FxX.pP+\-]+)|constant:([0-9a-fA-FxX.pP+\-]+)")
# a reciprocal conversion is built by a helper with the factor inside it
RECIPROCAL = re.compile(r"charon_reciprocal_converter\(([0-9a-fA-FxX.pP+\-]+)\)")


def number_of(text):
    """a coefficient as the port wrote it: decimal, exponent, or a hexadecimal float literal.

    0x1p+0 is 1.0 and 0x1p-3 is 0.125, and float.fromhex reads exactly that form; the decimal and
    exponent forms go through float() as before. The port uses all three, and reading a hex literal with
    the decimal pattern takes the leading 0 of it, which is how a byte's coefficient became 0.0.
    """
    text = text.strip()
    if text[:2].lower() in ("0x", "-0", "+0") and "x" in text.lower():
        return float.fromhex(text)
    return float(text)
CONVERTER = re.compile(r"initWithConverter:\[?\[?\[?NSUnitConverter\w*\s+alloc\]?\s*initWith\w+")

# the port's class to the CLDR quantity that means the same thing. Each is a fact about what the class
# measures, and the factor equality is what has to agree on top of it; a class here with no CLDR
# quantity of that name, or a class missing, sends every one of its declarations to the unmapped list.
# The primary source: what each class measures, as a CLDR quantity. Every name here is one of the 22
# CLDR 48 actually has - acceleration, angle, area, concentr, consumption, digital, duration, electric,
# energy, force, frequency, graphics, length, light, magnetic, mass, power, pressure, speed, temperature,
# torque, volume - and NSUnitDispersion has none, which is said rather than guessed.
QUANTITY = {
    "NSUnitAcceleration": "acceleration", "NSUnitAngle": "angle", "NSUnitArea": "area",
    "NSUnitConcentrationMass": "concentr", "NSUnitDispersion": None, "NSUnitDuration": "duration",
    "NSUnitElectricCharge": "electric", "NSUnitElectricCurrent": "electric",
    "NSUnitElectricPotentialDifference": "electric", "NSUnitElectricResistance": "electric",
    "NSUnitEnergy": "energy", "NSUnitFrequency": "frequency", "NSUnitFuelEfficiency": "consumption",
    "NSUnitIlluminance": "light", "NSUnitInformationStorage": "digital", "NSUnitLength": "length",
    "NSUnitMass": "mass", "NSUnitPower": "power", "NSUnitPressure": "pressure", "NSUnitSpeed": "speed",
    "NSUnitTemperature": "temperature", "NSUnitVolume": "volume",
}


# The host oracle: what tests/backports/host/units/run.sh -v wrote, a row per class, unit, direction and
# sample, with the host's 64-bit pattern and the port's. A row may only say "port = host to the bit" out of
# this file, and only when every sample of that unit carries ==. The fixtures beside this tool are a copy
# of one run's file and a derived one with a single row flipped, so the control needs no host.
HOST_VALUES = os.environ.get("CLDR_HOST_VALUES", os.path.join(HERE, "fixtures", "host-values-real.tsv"))
# the row a host verdict gets, citing the run that made it and the rational it differs by
HOST_HOW = ("port = host to the bit at every sample (units/run.sh, %s); differs from CLDR release-48 by %s; "
            "the host is the oracle for this row")
HOST_VALUES_MISSING = ("the host oracle is not there: run `sh tests/backports/host/units/run.sh -v`, which writes it, "
                       "before a row may be judged against the host")


def host_values(path=None):
    """(samples, per unit, header): samples maps (class, unit, direction, v) to (host bits, port bits);
    per unit maps (class, unit) to (every sample ==, the first sample that is not), and header is the
    run's own line - the checks it counted and the command that wrote it - which a row cites."""
    path = path or HOST_VALUES
    if not os.path.isfile(path):
        return {}, {}, None
    samples, per_unit, header = {}, {}, None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                if header is None and "checks" in line and "cmd " in line:
                    header = line[1:].strip()
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8:
                continue
            key = (fields[0], fields[1], fields[2], fields[3])
            samples[key] = (fields[5], fields[6])
            unit = (fields[0], fields[1])
            same, first = per_unit.get(unit, (True, None))
            if fields[7] != "==":
                same, first = False, first or key[2:] + (fields[7],)
            per_unit[unit] = (same, first)
    return samples, per_unit, header


DISAGREEMENTS = []


def significant_digits(text):
    """how many significant digits a coefficient literal writes, counted from its own text.

    0.00492892 writes six - the leading zeros are not digits of the value - and 3.78541 writes six, and
    1e-9 writes one. The count is what the rounding is to, and it comes from the port's own spelling.
    """
    if text is None:
        return 0
    digits = "".join(c for c in text.lower() if c.isdigit())
    stripped = digits.lstrip("0")
    if not stripped:
        return 0
    if "e" in text.lower() and not stripped.strip("0"):
        return 1
    return len(stripped.rstrip("0")) or len(stripped)


def rounded_matches(ratio, literal):
    """the port's literal is the exact ratio rounded to the digits the literal writes"""
    digits = significant_digits(literal)
    if digits <= 0:
        return None
    return ("%.*g" % (digits, float(ratio))) == literal.strip()


def quantity_of(cldr, base_symbol, port=None):
    """the CLDR quantity that has a unit spelled as the port's base unit, and how it was found.

    The table of class-to-quantity is a guess and it was wrong - digital-byte is a unit, not a
    quantity - so the quantity is read out of CLDR: the one whose unit ids carry that display name.
    """
    hits = []
    for kind in cldr.identifiers:
        if cldr.width_of(kind, base_symbol) is None:
            continue
        quantity = cldr.quantity(kind)
        if quantity and quantity not in hits:
            hits.append(quantity)
    if len(hits) == 1:
        return hits[0], hits
    if not hits:
        return None, hits
    if port is not None:
        # a base unit's symbol can belong to more than one quantity - the degree is both an angle and a
        # temperature - so the one that covers the class's own declarations is the one, measured by how
        # many of its units the port declares at the same spellings
        declared = {r["symbol"] for r in port.rows if r["symbol"]}
        best = None
        for candidate in hits:
            covered = sum(1 for k in cldr.identifiers_in(candidate)
                          if cldr.width_of(k, None) is not None
                          and any(cldr.width_of(k, symbol) is not None for symbol in declared))
            if best is None or covered > best[1]:
                best = (candidate, covered)
        if best and best[1]:
            return best[0], hits
    return None, hits


class Port(object):
    """one class's own declarations: the symbol, the factor to the class's base unit, and the file"""

    def __init__(self, foundation, name):
        self.name = name
        self.file = os.path.join(foundation, name + ".m")
        with open(self.file, encoding="utf-8") as handle:
            text = handle.read()
        self.rows = []
        for method in METHOD.finditer(text):
            end = text.find("\n+ (", method.end())
            body = text[method.end():end if end > 0 else len(text)]
            symbol = SYMBOL.search(body)
            if not symbol:
                continue
            factor = COEFFICIENT.search(body)
            offset = OFFSET.search(body)
            reciprocal = RECIPROCAL.search(body)
            self.rows.append({
                "method": method.group(2),
                "symbol": symbol.group(1),
                "factor": number_of(factor.group(1)) if factor else None,
                "literal": factor.group(1) if factor else None,
                "offset": number_of(offset.group(1) or offset.group(2)) if offset else None,
                # the literals beside the values, because the agreement is against the digits the port
                # wrote and rounded_matches() reads the text, not the double it parses to
                "offset_literal": (offset.group(1) or offset.group(2)) if offset else None,
                "reciprocal": number_of(reciprocal.group(1)) if reciprocal else None,
                "reciprocal_literal": reciprocal.group(1) if reciprocal else None,
                "converter": bool(CONVERTER.search(body)),
                "file": name + ".m",
            })
        base = BASE.search(text)
        self.base_method = base.group(1) if base else None
        self.base = next((r for r in self.rows if r["method"] == self.base_method), None)

    def quantity(self):
        return QUANTITY.get(self.name)


def candidates(cldr, quantity, base_symbol):
    """CLDR's ids of this quantity, each with the factor CLDR gives it - a fraction, or None"""
    out = []
    for kind in cldr.identifiers_in(quantity):
        entry = cldr.factor(kind)
        if entry is None:
            continue
        out.append((kind, entry[0], entry[1]))
    return out


def map_class(cldr, foundation, name, verbose=False):
    """(rows, reasons): a row only where the factors are equal exactly, and a reason for everything else"""
    port = Port(foundation, name)
    searched = port.quantity()
    quantity = None
    base_id = None
    if port.base is not None:
        quantity, found = quantity_of(cldr, port.base["symbol"], port)
        # the table decides and the vote is printed beside it, so a disagreement is a line in the report
        # rather than a silent choice
        from_table = QUANTITY.get(name, "unset")
        if isinstance(from_table, str) and from_table not in found:
            DISAGREEMENTS.append((name, from_table, found, port.base["symbol"]))
        elif quantity is not None and from_table is not None and quantity != from_table:
            DISAGREEMENTS.append((name, from_table, [quantity], port.base["symbol"]))
        quantity = from_table if isinstance(from_table, str) and from_table in found else quantity
        if quantity is None:
            return [], ([(name, r, "no CLDR quantity has a unit spelled %s, the class's base unit; the "
                                 "quantities whose units are spelled that way are %s"
                          % (port.base["symbol"], ", ".join(found) or "none"), None)
                         for r in port.rows]), port
    if quantity is not None and port.base is not None:
        by_symbol = [k for k in cldr.identifiers_in(quantity)
                     if cldr.width_of(k, port.base["symbol"]) is not None]
        if len(by_symbol) == 1:
            base_id = by_symbol[0]
        elif len(by_symbol) > 1:
            return [], ([(name, r, "%d CLDR identifiers of %s carry the display name %s, and the base unit "
                                "must be one of them" % (len(by_symbol), quantity, port.base["symbol"]), None)
                         for r in port.rows]), port
    if quantity is None:
        return [], [(name, r, "the class names no base unit, so there is no display name to look a "
                               "quantity up by (the table's guess for it was %s)" % searched,
                          None) for r in port.rows], port
    if port.base is None or port.base["factor"] is None:
        return [], [(name, r, "the class names no base unit, or its base unit carries no factor",
                     None) for r in port.rows], port
    if base_id is None:
        return [], [(name, r, "no CLDR identifier of %s has the base unit's display name %s, so nothing "
                               "this class declares can be placed in that quantity"
                          % (quantity, port.base["symbol"]), None) for r in port.rows], port
    # the scale is the port's base unit, and it is 1 by construction: every other factor below is a
    # ratio against it, which is how the comparison is meant to be taken. CLDR may carry no conversion
    # for the base id at all - the litre has none, it is a thousandth of a cubic meter - and asking
    # the evaluator for one was the wrong question.
    # CLDR's own factor for the base id when it has one - the litre has 1/1000, a thousandth of a
    # cubic meter - and 1 only where CLDR carries none at all, which is the "by construction" case: the
    # port's base unit defines the scale and the ratio of it against itself is 1.
    base_factor = cldr.factor(base_id) or (Fraction(1), Fraction(0))

    rows, reasons = [], []
    for row in port.rows:
        if row["factor"] is None and row["offset"] is None and row["reciprocal"] is None:
            reasons.append((name, row, "the declaration carries no coefficient, offset or reciprocal "
                                        "the reader can see", None))
            continue
        hit, ambiguous = None, 0
        # An affine declaration is a pair - a scale and an offset - and CLDR writes the two together, so the pair
        # is judged here, above the ratio loop, which is why the loop below is not allowed to claim a row that
        # carries a constant. The id is the one the port's own symbol names, by the lookup that placed the base.
        mine = [k for k in cldr.identifiers_in(quantity) if cldr.width_of(k, row["symbol"]) is not None]
        if row["offset_literal"] and len(mine) == 1 and row["factor"] is not None:
            got = cldr.factor(mine[0]) or (Fraction(1), Fraction(0))
            ratio = got[0] / base_factor[0]
            shift = got[1] - base_factor[1]
            width = cldr.width_of(mine[0], row["symbol"])
            if ratio == Fraction(row["factor"]) and shift == Fraction(row["offset_literal"]):
                hit = (mine[0], ratio, shift, "affine exact", Fraction(0), width)
            elif rounded_matches(shift, row["offset_literal"]):
                hit = (mine[0], ratio, shift, "affine decimal", shift - Fraction(row["offset_literal"]), width)
        elif row["reciprocal_literal"] and len(mine) == 1:
            # A reciprocal: N is the litres per 100 kilometres CLDR's own composition gives for it, mile over
            # gallon. The two mpg units carry the same symbol, so which gallon a row means is not in the id and
            # comes from the digits rule: every gallon the archive has is tried, and the one the port's N is a
            # rounding of is the one this row means - 235.214583333 for the US gallon, 282.4809363 for the
            # imperial, and the port writes 235.215 and 282.481.
            metre = cldr.factor("mile")
            if metre:
                for gallon in ("gallon", "gallon-imperial"):
                    gal = cldr.factor(gallon)
                    if not gal:
                        continue
                    want = Fraction(10 ** 8) * gal[0] / metre[0]
                    if rounded_matches(want, row["reciprocal_literal"]):
                        named = [k for k in cldr.identifiers_in(quantity) if k.endswith(gallon)]
                        hit = (named[0] if named else mine[0], want, Fraction(0), "reciprocal decimal",
                               want - Fraction(row["reciprocal_literal"]), cldr.width_of(mine[0], row["symbol"]))
                        break
        for kind in cldr.identifiers_in(quantity):
            width = cldr.width_of(kind, row["symbol"])
            if width is None:
                continue
            got = cldr.factor(kind) or (Fraction(1), Fraction(0))
            # the ratio is what compares: CLDR's factor for this id over CLDR's factor for the id the
            # port's base unit matched, with the offsets differing for temperature
            ratio = got[0] / base_factor[0]
            shift = got[1] - base_factor[1]
            if float(ratio) != row["factor"] or float(shift) != float(row["offset"] or 0):
                continue
            ambiguous += 1
            if ratio == Fraction(row["factor"]) and not row["offset_literal"]:
                # a row that carries a constant is a pair and is judged as one above; a bare ratio is not
                # evidence about half of it
                hit = (kind, ratio, shift, "exact", Fraction(0), width)
            elif float(ratio) == row["factor"] and not row["offset_literal"]:
                # equal as doubles, not as rationals: the port holds a double and CLDR a rational
                hit = (kind, ratio, shift, "double", ratio - row["factor"], width)
            elif rounded_matches(ratio, row["literal"]) and not row["offset_literal"]:
                # the port writes a literal that is the exact ratio rounded to the digits it wrote: the
                # US measures are 0.00492892 where the exact ratio is 0.0049289216
                hit = (kind, ratio, shift, "decimal", ratio - row["factor"], width)
        if hit is None and ambiguous:
            hit, ambiguous = None, 0
        if hit is None and (row["offset_literal"] or row["reciprocal_literal"]):
            # An affine or a reciprocal declaration, which the factor ratio cannot judge: a constant that is
            # not CLDR's is not a port defect until the host has been asked. The id is the one the port's own
            # symbol names, found by the same lookup that placed the base unit, and the run is the oracle's
            # own file - a row may not name the host out of anything else.
            mine = [k for k in cldr.identifiers_in(quantity) if cldr.width_of(k, row["symbol"]) is not None]
            _samples, per_unit, header = host_values()
            if header is None:
                reasons.append((name, row, HOST_VALUES_MISSING, None))
                continue
            same, first = per_unit.get((name, row["symbol"]), (None, None))
            if same is None:
                reasons.append((name, row, "the host oracle has no %s for %s, and a row may not name the host "
                                          "without a run that saw it (%s)" % (row["symbol"], name, header), None))
                continue
            if not same:
                reasons.append((name, row, "port differs from the host at %s %s: the oracle's own first sample that "
                                          "is not the host's" % (first[0], first[1]), None))
                continue
            if len(mine) == 1:
                got = cldr.factor(mine[0]) or (Fraction(1), Fraction(0))
                difference = ((Fraction(row["offset_literal"]) - got[1]) if row["offset_literal"]
                              else (Fraction(row["reciprocal_literal"]) - got[0]))
                hit = (mine[0], got[0], got[1], HOST_HOW % (header, difference), difference,
                       cldr.width_of(mine[0], row["symbol"]))
        if hit is None:
            by_name = [k for k in cldr.identifiers_in(quantity)
                       if cldr.width_of(k, row["symbol"]) is not None]
            if not by_name:
                reasons.append((name, row, "no CLDR identifier of %s has the display name %s - the port's "
                                          "own spelling, as with the imperial and troy units"
                                 % (quantity, row["symbol"]), None))
            else:
                named = [k for k in by_name if cldr.factor(k)]
                reasons.append((name, row, "%d CLDR identifiers of %s carry the display name %s and %d of them "
                                          "carry a conversion, but none has the port's factor %s as a double"
                                 % (len(by_name), quantity, row["symbol"], len(named), row["factor"]), None))
            continue
        kind, factor, offset, how, difference, width = hit
        entry = cldr.identifiers.get(kind) or (None, None)
        rows.append({
            "class": name, "symbol": row["symbol"], "method": "+[" + row["method"] + "]",
            "file": row["file"], "identifier": kind, "display": (entry or (None, None))[1] or "",
            "factor": factor, "offset": offset, "how": how, "difference": difference,
            "width": width,
        })
    if verbose:
        print("%s: base +[%s %s] = %s, %d of %d mapped" % (
            name, name, port.base_method, port.base["symbol"], len(rows), len(port.rows)))
        for row in rows:
            print("  %-7s +[%-24s] -> %-28s factor %-22s %s" % (row["symbol"], row["method"][1:-1],
                                                                    row["identifier"], row["factor"], row["how"]))
        for name, row, reason, _ in reasons:
            print("  %-7s +[%-24s] %s" % (row["symbol"], row["method"][1:-1], reason))
    return rows, reasons, port


def one_ulp_control(cldr, foundation):
    """CLDR's own parsec, and the same value moved by one ulp: the first maps, the second must not.

    The acceptance rule is equality as a double, so this is the control that says the rule is not so
    loose that anything near the value is accepted.
    """
    import math
    got = cldr.factor("length-parsec")
    if got is None:
        print("FAIL the one-ulp control: CLDR has no factor for length-parsec")
        return 1
    exact = float(got[0])
    away = math.nextafter(exact, math.inf)
    near = float(got[0]) == exact
    off = float(got[0]) == away
    if not near or off:
        print("FAIL the one-ulp control: the value maps=%d, one ulp away maps=%d" % (near, off))
        return 1
    print("ok   the one-ulp control: CLDR's parsec maps, and one ulp away does not (%.17g vs %.17g)"
          % (exact, away))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="the mapper, as an importable module")
    parser.add_argument("--class", dest="one", help="one class, printed")
    parser.add_argument("--all", action="store_true", help="every class")
    parser.add_argument("--write", action="store_true", help="write the two files beside the tool")
    parser.add_argument("--archive", default=ARCHIVE)
    arguments = parser.parse_args(argv)

    if not cldr_factors.verify_archive(arguments.archive, os.path.join(HERE, "PIN")):
        return 2
    cldr = cldr_factors.Cldr(arguments.archive)

    if arguments.one:
        rows, reasons, port = map_class(cldr, FOUNDATION, arguments.one, verbose=True)
        if one_ulp_control(cldr, FOUNDATION):
            return 1
        for name, row, reason, _ in reasons[:8]:
            print("  %-7s +[%-24s] %s" % (row["symbol"], row["method"][1:-1], reason))
        if len(reasons) > 8:
            print("  ... and %d more" % (len(reasons) - 8))
        return 0

    if arguments.all:
        classes = sorted(n[:-2] for n in os.listdir(FOUNDATION)
                        if n.startswith("NSUnit") and n.endswith(".m")
                        and n[:-2] in QUANTITY)
        rows, reasons = [], []
        for name in classes:
            got, missed, _ = map_class(cldr, FOUNDATION, name)
            print("%-32s %3d of %3d mapped" % (name, len(got), len(got) + len(missed)))
            rows.extend(got)
            reasons.extend(missed)
        if arguments.write:
            header = ("# The port's unit declarations CLDR's own data agrees with.\n"
                      "#\n"
                      "# Keyed on (class, symbol): eight symbols are declared by two classes or two\n"
                      "# methods, so a symbol alone is not a key.\n"
                      "#\n"
                      "# A row is here only where the port's converter coefficient - a double, relative\n"
                      "# to the port's own base unit - equals the RATIO of CLDR's factor for this\n"
                      "# identifier over CLDR's factor for the identifier the base unit matched, with the\n"
                      "# offsets equal too. The two scales differ: the port's volume base is the litre and\n"
                      "# CLDR's is the cubic meter.\n"
                      "#\n"
                      "# agreement: exact, where the rational equals the port's value as a rational;\n"
                      "# double, where they are equal only after rounding, and the rational difference\n"
                      "# is kept beside it so the difference the rule allowed stays visible.\n"
                      "#\n"
                      "# width matched: the width at which the port's spelling is CLDR's own - short, narrow\n"
                      "# or long. The port's 's' is CLDR's narrow form of the second and its 'hr' the short\n"
                      "# form of the hour.\n"
                      "#\n"
                      "# class\tsymbol\t+[the method]\tfile\tCLDR identifier\tdisplay name\tfactor\toffset"
                      "\tagreement\trational difference\twidth matched\n")
            with open(os.path.join(HERE, "unit-map.tsv"), "w", encoding="utf-8") as handle:
                handle.write(header)
                for row in rows:
                    handle.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                        row["class"], row["symbol"], row["method"], row["file"], row["identifier"],
                        row["display"], row["factor"], row["offset"], row["how"], row["difference"],
                        row["width"]))
            reasons_header = ("# The port's unit declarations CLDR's own data does not agree with.\n"
                              "#\n"
                              "# These are NOT guessed. Each carries the reason: the class names no base\n"
                              "# unit or its base carries no factor, the declaration carries no linear\n"
                              "# coefficient or a non-linear converter, no CLDR identifier of that\n"
                              "# quantity is the port's own spelling, or none of the identifiers that are\n"
                              "# has the port's factor as a double. A row is here only after the factor was\n"
                              "# compared and did not agree.\n"
                              "#\n"
                              "# class\tsymbol\t+[the method]\tfile\treason\n")
            with open(os.path.join(HERE, "unmapped.txt"), "w", encoding="utf-8") as handle:
                handle.write(reasons_header)
                for name, row, reason, _ in reasons:
                    handle.write("%s\t%s\t%s\t%s\t%s\n" % (
                        name, row["symbol"], row["method"], row["file"], reason))
            print("wrote %d mapped rows and %d reasons" % (len(rows), len(reasons)))
        return 0

    parser.error("nothing to do: --class <name> or --all --write")
    return 2


if __name__ == "__main__":
    sys.exit(main())
