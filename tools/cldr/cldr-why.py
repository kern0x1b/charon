#!/usr/bin/env python3
"""cldr-why.py - why each declaration did not map, printed rather than summarised.

The reasons file says what went wrong in one line per declaration. This says it in the numbers: the port's
own factor, the CLDR identifier that carries the spelling, its exact ratio against the class's base, and
which of the three things fails - the base's display name, the width, or the factor. A reader defect and a
CLDR gap look the same in a reason and are not the same thing.

    cldr-why.py NSUnitInformationStorage      one class
    cldr-why.py --no-base                      the classes whose base the reader cannot see
    cldr-why.py --powers                       CLDR's unit-id power components, which area and volume use
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cldr_factors  # noqa: E402
import cldr_map  # noqa: E402

ARCHIVE = cldr_map.ARCHIVE


def why(cldr, class_name, port):
    quantity = cldr_map.QUANTITY.get(class_name)
    print("=== %s, CLDR quantity %s, the port's base +[%s] symbol %r factor %s"
          % (class_name, quantity, port.base_method, port.base["symbol"], port.base["factor"]))
    base_ids = [k for k in cldr.identifiers_in(quantity or "")
                if cldr.width_of(k, port.base["symbol"]) is not None] if quantity else []
    base_factor = cldr.factor(base_ids[0]) if base_ids else None
    if base_factor is None and base_ids:
        # the class's own base has no conversion of its own: it is the quantity's base, 1 by construction
        base_factor = (cldr_factors.Fraction(1), cldr_factors.Fraction(0))
    for row in port.rows:
        if row["factor"] is None and row["offset"] is None and row["reciprocal"] is None:
            print("  %-7s the declaration carries no coefficient, offset or reciprocal" % row["symbol"])
            continue
        ids = [k for k in cldr.identifiers_in(quantity or "") if cldr.width_of(k, row["symbol"])]
        if not ids:
            print("  %-7s no CLDR id carries that spelling - searched %s" % (row["symbol"], quantity))
            continue
        printed = False
        for kind in ids:
            got = cldr.factor(kind) or (cldr_factors.Fraction(1), cldr_factors.Fraction(0))
            ratio = got[0] / base_factor[0] if base_factor else None
            ok = ratio is not None and float(ratio) == row["factor"]
            if printed and ok:
                continue
            print("  %-7s port %-20s cldr %-28s ratio %-26s %s"
                  % (row["symbol"], row["factor"], kind, ratio,
                     "agrees" if ok else "factor differs"))
            printed = True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("one", nargs="?")
    parser.add_argument("--no-base", action="store_true")
    parser.add_argument("--powers", action="store_true")
    parser.add_argument("--archive", default=ARCHIVE)
    arguments = parser.parse_args(argv)

    if not cldr_factors.verify_archive(arguments.archive, os.path.join(HERE, "PIN")):
        return 2
    cldr = cldr_factors.Cldr(arguments.archive)

    if arguments.powers:
        # the components CLDR composes an id from, which area and volume need and the prefix set does not
        with cldr_factors.zipfile.ZipFile(arguments.archive) as z:
            text = z.read(cldr_factors.TOP + "common/supplemental/units.xml").decode("utf-8", "replace")
        for kind, values in re.findall(r'<unitIdComponent type="([^"]+)" values="([^"]*)"', text):
            print("%-10s %s" % (kind, values))
        return 0

    if arguments.no_base:
        for name in sorted(cldr_map.QUANTITY):
            port = cldr_map.Port(cldr_map.FOUNDATION, name)
            if port.base is None or port.base["factor"] is None:
                print("=== %s: the reader sees base %r factor %s, and the port writes:"
                      % (name, port.base and port.base["symbol"], port.base and port.base["factor"]))
                with open(os.path.join(cldr_map.FOUNDATION, name + ".m"), encoding="utf-8") as handle:
                    for line in handle:
                        if "initWith" in line and "converter" in line:
                            print("     %s" % line.strip()[:116])
        return 0

    if arguments.one:
        why(cldr, arguments.one, cldr_map.Port(cldr_map.FOUNDATION, arguments.one))
        return 0

    parser.error("nothing to do: a class name, --no-base or --powers")
    return 2


if __name__ == "__main__":
    sys.exit(main())
