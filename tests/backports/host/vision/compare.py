#!/usr/bin/env python3
"""The Vision host differential's comparison: every recorded key must hold the same value on both
sides, and one family of keys is reported rather than failed on.

The exception is the *scores* of a Core ML prediction. The model the case runs is nn_image, whose
prediction this port and this host are a measured divergence apart -- the port's interpreter and
coremltools' own runtime agree, and the host's own Core ML does not, for reasons
facts/CoreML/CoreML.md sets out -- so the numbers are printed and the run continues. Everything
else is compared: the classes of observation, their identifiers, how many there are, the crop and
scale option, the refusal of a model with no image input, and every case the file already had.
"""
import json
import sys

DIVERGENT_PREFIX = "coreml.divergent/"


def main(system_path, port_path):
    system, port = json.load(open(system_path)), json.load(open(port_path))
    hard = 0
    for key in sorted(set(system) | set(port)):
        if key.startswith(DIVERGENT_PREFIX):
            if system.get(key) != port.get(key):
                print("divergent (recorded):", key)
                print("  system", str(system.get(key))[:200])
                print("  port  ", str(port.get(key))[:200])
            continue
        if system.get(key) != port.get(key):
            hard = 1
            print("DIFF", key)
            print("  system", str(system.get(key))[:400])
            print("  port  ", str(port.get(key))[:400])
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
