#!/usr/bin/env python3
"""cldr-units.py - the port's own unit symbols, and the CLDR identifiers they map to.

The port declares its own `NSUnit` subclasses with their own symbols, and a unit's *name* in a locale is
CLDR's data, not Apple's: the 6.1.3 release carries no unit-name data at all - no `unitsNew`, no
`measunit`, no CLDR identifier, and not one of the strings the host's formatter answers
(`.agent-work/runs/host/icudata-6.1.3.log`) - so the table this builds comes from CLDR, under the Unicode
licence, and never from strings copied off a host.

This is the first half: read every `NSUnit*.m` in the port and print the symbols it declares, with the
class and the file each came from. The second half - the CLDR half, under a pinned release with its
sha256 - is `cldr-table.py`, which consumes what this prints.

    tools/cldr-units.py --print-port-symbols
    tools/cldr-units.py --print-port-symbols --summary
"""

import argparse
import hashlib
import json
import os
import re
import sys

# A unit is declared as a class method that returns one, and the symbol is inside its body:
#   + (NSUnitLength *)kilometers
#   { ... initWithSpecifier:1282 symbol:@"km" converter:... }
# so the class comes from the method's signature and the symbol from the initialiser in its body. All
# three spellings the port uses are read: initWithSymbol:, initWithSpecifier:symbol: and
# initWithConverter:symbol:.
CLASS_METHOD = re.compile(r'^\+\s*\(\s*(NSUnit\w*)\s*\*\s*\)(\w+)\s*$', re.MULTILINE)
SYMBOL_IN_CALL = re.compile(r'(?:initWithSymbol:|symbol:)\s*@"([^"]*)"')


def port_symbols(foundation):
    """every symbol the port's unit classes declare, with the class and the file it came from"""
    found = {}
    for name in sorted(os.listdir(foundation)):
        if not (name.startswith("NSUnit") and name.endswith(".m")):
            continue
        path = os.path.join(foundation, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        methods = list(CLASS_METHOD.finditer(text))
        for index, method in enumerate(methods):
            end = methods[index + 1].start() if index + 1 < len(methods) else len(text)
            body = text[method.end():end]
            for symbol in SYMBOL_IN_CALL.findall(body):
                found.setdefault(symbol, []).append((method.group(1), name, method.group(2)))
    return found


def main(argv=None):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--foundation",
                        default=os.path.join(here, "packages/a/apple-backports/Foundation"),
                        help="the port's Foundation directory")
    parser.add_argument("--print-port-symbols", action="store_true",
                        help="print every symbol the port's unit classes declare")
    parser.add_argument("--summary", action="store_true", help="print only the counts")
    parser.add_argument("--json", action="store_true", help="print the symbols as JSON")
    parser.add_argument("--archive", help="the CLDR archive to read, when building the table")
    parser.add_argument("--verify-only", action="store_true",
                        help="check an archive against the pin and read nothing from it")
    parser.add_argument("--pin", default=os.path.join(here, "tools/cldr/PIN"),
                        help="the pin to check against")
    arguments = parser.parse_args(argv)

    if arguments.archive:
        # Before anything is read: the pin's own sha256 must be 64 characters, and the archive must be
        # the one it names. A pin typed by hand is a pin that can be a sha of 63 characters, and a
        # generator that reads a mismatched archive builds a table nobody can reproduce.
        pinned = None
        with open(arguments.pin, encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("- sha256:"):
                    pinned = line.split(":", 1)[1].strip()
        if pinned is None:
            print("the pin at %s names no sha256" % arguments.pin, file=sys.stderr)
            return 2
        if len(pinned) != 64:
            print("the pin's sha256 is %d characters, and a sha256 is 64" % len(pinned), file=sys.stderr)
            return 2
        digest = hashlib.sha256()
        with open(arguments.archive, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 22), b""):
                digest.update(block)
        if digest.hexdigest() != pinned:
            print("the archive is %s and the pin says %s" % (digest.hexdigest(), pinned), file=sys.stderr)
            return 2
        if arguments.verify_only:
            print("%s matches the pin (%d bytes, sha256 %s)" % (arguments.archive, os.path.getsize(arguments.archive), pinned))
            return 0
        print("the archive matches the pin; the table half is not written yet", file=sys.stderr)
        return 3

    if not arguments.print_port_symbols:
        parser.error("nothing to do: --print-port-symbols, or --archive with --verify-only")

    found = port_symbols(arguments.foundation)
    symbols = sorted(found)

    if arguments.json:
        print(json.dumps({symbol: found[symbol] for symbol in symbols}, indent=2, ensure_ascii=False))
        return 0

    if arguments.summary:
        classes = sorted({cls for places in found.values() for cls, _, _ in places})
        files = sorted({file for places in found.values() for _, file, _ in places})
        print("symbols %d over %d classes in %d files" % (len(symbols), len(classes), len(files)))
        return 0

    for symbol in symbols:
        for cls, name, method in found[symbol]:
            print("%-8s %-26s +[%s %s]  %s" % (symbol, cls, cls, method, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
