#!/usr/bin/env python3
"""Write the generator's vocabulary of why a member is not answered, as JSON.

gen-registry.py writes an absent entry's reason from this, so the reason names the **cause** - a
class of a later group, a value this delivery does not carry, a chain the SDK forbids, a factory
that answers an array, a class the headers only forward declare - and not the owner class's group,
which is what N3 was about.
"""

import argparse
import importlib.util
import json
import os


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True)
    options = parser.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("gen_intents", os.path.join(here, "gen-intents.py"))
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    with open(options.out, "w") as handle:
        json.dump(generator.CAUSES, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print("%s: %d causes" % (options.out, len(generator.CAUSES)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main() or 0)
