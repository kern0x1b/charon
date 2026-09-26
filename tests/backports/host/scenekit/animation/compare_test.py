#!/usr/bin/env python3
"""compare_test.py <oracle-dir> : compare.py must fail a device series that is empty, cut short or unparsed, and pass
SceneKit's own series against itself. Takes the oracle series of record.sh; needs no device."""
import os, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare

def failing(oracle_dir, device_dir, name, kind):
    bad, event_bad, _, _ = compare.check(os.path.join(oracle_dir, name + ".txt"), os.path.join(device_dir, name + ".txt"), kind,
                                         clock={"shimmer": "phase", "opacity-later": "add"}.get(name, "first frame"),
                                         timed_end=name != "remove-midway")
    return bool(bad or event_bad)

def variant(oracle_dir, make):
    out = tempfile.mkdtemp()
    for name, _ in compare.CASES:
        lines = open(os.path.join(oracle_dir, name + ".txt")).read().splitlines(True)
        open(os.path.join(out, name + ".txt"), "w").writelines(make(lines))
    return out

def main(oracle_dir):
    status = 0
    variants = {
        "the oracle itself": (lambda lines: lines, False),
        "empty": (lambda lines: [], True),
        "two samples": (lambda lines: [l for l in lines if not l.startswith("t=")] + [l for l in lines if l.startswith("t=")][:2], True),
        "unparsed values": (lambda lines: [" ".join(l.split()[:2] + ["x"] + l.split()[2:]) + "\n" if l.startswith("t=") else l for l in lines], True),
    }
    for label, (make, must_fail) in variants.items():
        device_dir = variant(oracle_dir, make)
        for name, kind in compare.CASES:
            got = failing(oracle_dir, device_dir, name, kind)
            if got != must_fail:
                status = 1
                print("FAIL %s, %s: %s" % (label, name, "passes" if must_fail else "fails"))
    print("compare.py holds" if status == 0 else "compare.py does NOT hold")
    return status

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
