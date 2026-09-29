#!/usr/bin/env python3
"""cldr-map-test.py - the controls for the mapper, as tests that fail.

The mapping is a comparison of two scales - the port's coefficients are relative to the port's own base
unit, CLDR's factors to CLDR's base of that quantity - so the controls below are the cases where the
answer is known without reading the data: a unit's ratio to its class's base, computed both ways, must be
the port's own coefficient.

There is also a floor: every row the committed mapping has must still be produced. A mapper that
silently drops a row is worse than one that refuses to run, and the floor is what catches that.

    cldr-map-test.py            run every control
    cldr-map-test.py --trace NSUnitVolume litre     print the one unit's steps
"""

import argparse
import os
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import cldr_factors  # noqa: E402
import cldr_map  # noqa: E402

FOUNDATION = os.path.join(REPO, "packages/a/apple-backports/Foundation")
COMMITTED = os.path.join(HERE, "unit-map.tsv")

# (class, method, the CLDR id it must reach, the ratio the port's own coefficient is)
CONTROLS = [
    ("NSUnitVolume", "liters", "volume-liter", "the base unit against itself"),
    ("NSUnitVolume", "milliliters", "volume-milliliter", "a thousandth of the base"),
    ("NSUnitVolume", "cubicMeters", "volume-cubic-meter", "a thousand times the base"),
    ("NSUnitMass", "grams", "mass-gram", "a thousandth of the kilogram base"),
    ("NSUnitDuration", "hours", "duration-hour", "sixty times the seconds base"),
]


def rows_for(cldr, name):
    rows, reasons, port = cldr_map.map_class(cldr, FOUNDATION, name)
    return rows, reasons, port


def trace(cldr, class_name, method):
    port = cldr_map.Port(FOUNDATION, class_name)
    quantity = port.quantity()
    print("class %s, quantity %s" % (class_name, quantity))
    print("  the port's base: +[%s %s] symbol %r factor %s"
          % (class_name, port.base_method, port.base["symbol"], port.base["factor"]))
    by_symbol = [k for k in cldr.identifiers_in(quantity) if cldr.symbol_of(k) == port.base["symbol"]]
    print("  CLDR ids of %s whose en symbol is %r: %s" % (quantity, port.base["symbol"], by_symbol))
    if len(by_symbol) != 1:
        print("  and that is not one, so no ratio is computed at all")
        return
    base_id = by_symbol[0]
    base_factor = cldr.factor(base_id)
    print("  base id %s, CLDR's factor for it: %s" % (base_id, base_factor))
    if base_factor is None:
        print("  and it is None, so every ratio below is against None")
    row = next((r for r in port.rows if r["method"] == method), None)
    if row is None:
        print("  the port has no +[%s]" % method)
        return
    print("  the unit: %r factor %s offset %s" % (row["symbol"], row["factor"], row["offset"]))
    for kind in cldr.identifiers_in(quantity):
        if cldr.symbol_of(kind) != row["symbol"]:
            continue
        got = cldr.factor(kind)
        print("  candidate %s: factor %s" % (kind, got))
        if got is None:
            print("    CLDR has no conversion for it")
            continue
        if base_factor is None:
            print("    and the base's factor is None, so the ratio is not computable")
            continue
        ratio = got[0] / base_factor[0]
        shift = got[1] - base_factor[1]
        print("    ratio %s  shift %s  float(ratio) %r  the port's %r  equal %s"
              % (ratio, shift, float(ratio), row["factor"], float(ratio) == row["factor"]))
        print("    offsets: float(shift) %r  the port's %r  equal %s"
              % (float(shift), float(row["offset"] or 0), float(shift) == float(row["offset"] or 0)))


def committed_rows():
    """(class, symbol, method, identifier, kind) every row the committed mapping has.

    The kind is in the tuple on purpose. A row's kind is the column that says which kind of agreement
    the row is, and a floor that compared only the identifier would not notice a row whose kind had
    been edited: a review changed one to `reciprocal` and all seventeen controls stayed green. The
    column layout is fixed by band-api-foundation-swift's reader - column 2 is the port's symbol,
    column 4 the file, column 5 the CLDR identifier, column 9 the agreement - and nothing here moves a
    column; the kind is read from the ninth and no assertion depends on where.
    """
    rows = set()
    with open(COMMITTED, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or line.startswith("class\t") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 9:
                rows.add((parts[0], parts[1], parts[2], parts[4], parts[8]))
    return rows


def archive_message(archive):
    """why the pinned archive is not here, naming where the pin fetches it from and what it must hash to.

    The pin's three facts are markdown list items - `- url:`, `- bytes:`, `- sha256:` - and a value may
    be written in backticks, so the leading marker and the backticks both come off before a key is
    matched. A reader that misses one of them falls back to "the pin does not say", which is worse than
    useless: it looks like a fact and says nothing.
    """
    pin = os.path.join(HERE, "PIN")
    url = sha = where = None
    if os.path.isfile(pin):
        for line in open(pin, encoding="utf-8"):
            key = line.strip()
            if key.startswith("-"):
                key = key[1:].strip()
            if key.startswith("`") and key.endswith("`"):
                key = key[1:-1].strip()
            for name in ("url", "sha256", "local"):
                if key.startswith(name + ":"):
                    value = key.split(":", 1)[1].strip().strip("`").strip()
                    if name == "url":
                        url = value
                    elif name == "sha256":
                        sha = value
                    else:
                        where = value
    return ("cldr-map-test: the pinned archive is not here\n"
            "  the pin fetches it from %s\n"
            "  it is unpacked at %s, and the tools do not fetch it for you\n"
            "  it must be the release's own file: sha256 %s\n"
            "  pass it with --archive, or unpack that file beside this tool"
            % (url or "(the pin does not say)", where or "(the pin does not say)",
               sha or "(the pin does not say)"))


def archive_or_name(archive):
    """the pinned archive, or the message that says where it is fetched from and what it must hash to."""
    if os.path.isfile(archive):
        return archive
    raise SystemExit(archive_message(archive))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--trace", nargs=2, metavar=("CLASS", "METHOD"),
                        help="print one unit's steps")
    parser.add_argument("--archive", default=cldr_map.ARCHIVE)
    arguments = parser.parse_args(argv)

    arguments.archive = archive_or_name(arguments.archive)
    if not cldr_factors.verify_archive(arguments.archive, os.path.join(HERE, "PIN")):
        return 2
    cldr = cldr_factors.Cldr(arguments.archive)

    if arguments.trace:
        trace(cldr, arguments.trace[0], arguments.trace[1])
        return 0

    failed = 0
    for class_name, method, wanted, description in CONTROLS:
        rows, reasons, port = rows_for(cldr, class_name)
        got = [r for r in rows if r["method"] == "+[" + method + "]"]
        if not got:
            said = next((why for _n, r, why, _d in reasons if r["method"] == "+[" + method + "]"),
                        "(no reason recorded)")
            print("FAIL %-20s +[%s] (%s): no row; %s" % (class_name, method, description, said))
            failed += 1
            continue
        row = got[0]
        if row["identifier"] != wanted:
            print("FAIL %-20s +[%s] (%s): reached %s, not %s"
                  % (class_name, method, description, row["identifier"], wanted))
            failed += 1
            continue
        print("ok   %-20s +[%s] -> %-22s ratio %s (%s)"
              % (class_name, method, row["identifier"], row["factor"], description))

    # a hyphen in a unit id is only a quantity boundary when the first word is a quantity of this release:
    # gallon-imperial is one name, and the old split asked convertUnit for a unit called "imperial"
    hyphenated = (("gallon-imperial", "454609/100000000"), ("gallon", "473176473/125000000000"),
                  ("mile-per-gallon", None), ("mile-per-gallon-imperial", None),
                  ("liter-per-100-kilometer", None))
    for kind, wanted in hyphenated:
        entry = cldr.factor(kind)
        if wanted is None:
            # a composed id: CLDR states it as mile over gallon and writes no convertUnit for it, so no
            # entry is the archive's own answer and asking for one would invent it
            if entry is not None:
                print("FAIL %-28s has an entry %s, which the archive does not write" % (kind, entry))
                failed += 1
            else:
                print("ok   %-28s looked up under its own name, and the archive writes no entry" % kind)
        elif entry is None:
            print("FAIL %-28s has no factor: the reader stripped the %s of it"
                  % (kind, kind.split("-", 1)[0]))
            failed += 1
        elif str(entry[0]) != wanted:
            print("FAIL %-28s is %s, not the exact %s" % (kind, entry[0], wanted))
            failed += 1
        else:
            print("ok   %-28s -> %s exactly" % (kind, entry[0]))
    for kind, tail in (("length-kilometer", "kilometer"), ("acceleration-meter-per-second-squared",
                                                           "meter-per-second-squared")):
        if getattr(cldr, "bare", lambda k: k)(kind) != tail:
            print("FAIL %-38s does not strip its quantity: bare is %s" % (kind, cldr.bare(kind)))
            failed += 1
        else:
            print("ok   %-38s strips to %s" % (kind, tail))
    # getattr, not cldr.quantities: on a reader without the table this has to FAIL and say so, not raise
    absent = [q for q in set(cldr_map.QUANTITY.values())
              if q and q not in (getattr(cldr, "quantities", ()) or ())]
    if absent:
        print("FAIL the class table names quantities this release does not declare: %s" % ", ".join(sorted(absent)))
        failed += 1
    else:
        print("ok   every quantity the class table names is one this release declares")

    # The host oracle, from the fixtures: the real one has every unit equal to the host, and the derived
    # one has exactly one row flipped, so that unit falls to the named failure and the rest do not.
    fixtures = os.path.join(HERE, "fixtures")
    real = os.path.join(fixtures, "host-values-real.tsv")
    one = os.path.join(fixtures, "host-values-one-different.tsv")
    _samples, real_units, header = cldr_map.host_values(real)
    if header is None or "checks" not in header:
        print("FAIL the real fixture names no run: its first lines must carry the checks and the command")
        failed += 1
    elif real_units.get(("NSUnitTemperature", "°F"), (False, None))[0] is not True:
        print("FAIL the real fixture: the port's Fahrenheit is not the host's, so the control proves nothing")
        failed += 1
    else:
        print("ok   the real fixture: °F is the host's to the bit, and the run is named")
    _samples, one_units, _header = cldr_map.host_values(one)
    fahrenheit = one_units.get(("NSUnitTemperature", "°F"), (True, None))
    if fahrenheit[0] is not False:
        print("FAIL the derived fixture: one flipped row did not make °F fall out of the host")
        failed += 1
    elif not fahrenheit[1] or fahrenheit[1][0] != "base":
        print("FAIL the derived fixture: the named failure does not name the sample: %s" % (fahrenheit[1],))
        failed += 1
    else:
        print("ok   the derived fixture: %s %s at v=%s falls to the named failure" % fahrenheit[1][:3])
    moved = [u for u, (same, _f) in one_units.items() if u != ("NSUnitTemperature", "°F") and not same]
    if moved:
        print("FAIL the derived fixture moved %d unit(s) besides °F: %s" % (len(moved), moved[:4]))
        failed += 1
    else:
        kept = len([u for u, (same, _f) in one_units.items() if same])
        print("ok   every other unit stays the host's: %d of %d" % (kept, len(one_units)))

    # One row per kind, named, with the kind the mapper produces and the kind the table carries compared: a
    # kind edited in the table is then red by its own row rather than by a count. The six kinds of the brief are
    # four here and two fixtures: affine and host are how the °C and °F rows are judged, and decimal has no
    # committed row to name, so it is pinned by the digits rule on the port's own literal.
    for cls, symbol, kind in (("NSUnitAcceleration", "m/s²", "exact"),
                              ("NSUnitAngle", "rad", "double"),
                              ("NSUnitFuelEfficiency", "mpg", "reciprocal"),
                              ("NSUnitTemperature", "°C", "affine"),
                              ("NSUnitTemperature", "°F", "port = host to the bit")):
        said = [(r[2], r[4]) for r in committed_rows() if r[0] == cls and r[1] == symbol]
        if not said:
            print("FAIL the %-22s row: %s %s is not in the table" % (kind, cls, symbol))
            failed += 1
            continue
        method, said_kind = said[0]
        rows, _reasons, _port = rows_for(cldr, cls)
        got = [r for r in rows if r["method"] == method]
        if not got:
            print("FAIL the %-22s row: %s +[%s] is not produced" % (kind, cls, method.strip("+[]")))
            failed += 1
            continue
        made = got[0]["how"]
        if not made.startswith(kind) or not said_kind.startswith(kind):
            print("FAIL the %-22s row: %s %s +[%s] is made %r and the table says %r"
                  % (kind, cls, symbol, method.strip("+[]"), made[:40], said_kind[:40]))
            failed += 1
        else:
            print("ok   the %-22s row: %s %s" % (kind, cls, symbol))
    if cldr_map.rounded_matches(Fraction(0.0049289216), "0.00492892") is not True:
        print("FAIL the decimal fixture: the port's 0.00492892 is not CLDR's 0.0049289216 at the digits it wrote")
        failed += 1
    elif cldr_map.rounded_matches(Fraction(0.0049289216), "0.0049288") is not False:
        print("FAIL the decimal fixture: a literal that is not the value at its own digits passes the digits rule")
        failed += 1
    else:
        print("ok   the decimal fixture: 0.00492892 is 0.0049289216 at six digits, and one digit short is not")

    # The missing-archive message must carry the pin's own sha256 and url: a reader that misses the pin's
    # "- " marker falls back to "the pin does not say", which looks like a fact and says nothing.
    message = archive_message(os.path.join(HERE, "no-such-archive.zip"))
    pinned = [line for line in open(os.path.join(HERE, "PIN"), encoding="utf-8")
              if line.strip().lstrip("-").strip().startswith("sha256:")][0]
    sha = pinned.split(":", 1)[1].strip().strip("`")
    if sha not in message:
        print("FAIL the archive message does not carry the pin's sha256 (%s): %s" % (sha, message.splitlines()[3]))
        failed += 1
    elif "does not say" in message:
        print("FAIL the archive message falls back: %s" % message.replace("\n", " | "))
        failed += 1
    else:
        print("ok   the archive message carries the pin's sha256 and names where it is fetched from")

    # the floor: every row the committed mapping has must still be produced
    before = committed_rows()
    after = set()
    classes = sorted(n[:-2] for n in os.listdir(FOUNDATION)
                     if n.startswith("NSUnit") and n.endswith(".m")
                     and n[:-2] in cldr_map.QUANTITY)
    for name in classes:
        rows, _reasons, _port = rows_for(cldr, name)
        for row in rows:
            after.add((row["class"], row["symbol"], row["method"], row["identifier"], row["how"]))
    dropped = sorted(before - after)
    if dropped:
        print("FAIL the floor: %d of the committed %d rows are not produced:" % (len(dropped), len(before)))
        for row in dropped[:12]:
            print("     %s %s %s -> %s, kind %s" % row)
        failed += 1
    else:
        print("ok   the floor: all %d committed rows are produced" % len(before))

    print("%d controls, %d failed" % (len(CONTROLS) + 13, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
