#!/usr/bin/env python3
"""page-check.py - every claim the CNN facts page makes about the last run, against that run.

`Matrix.md` has its own checker, `tests/backports/host/mpsmatrix/page-check.py`, wired into that runner.
This is the same idea for the CNN slice, and it exists because the page named a case among the
bit-identical ones that the transcript contradicts: it listed `batch-normalization` among four, and the
run's own `port.txt` carries a ninth element of that case where the two sides differ, with
`8.05928898` against `8.05928993` - which the same page printed twelve lines lower down. A document that
quotes a run is a claim about it, and a claim a transcript can falsify has to be checked somewhere.

Two things are checked, both from the transcripts the run just wrote and not from a log:

  * which cases are **bit-identical**, as a set. The page must name exactly the run's set, and nothing
    else, and a case the page calls identical that the run shows as differing fails.
  * the **largest relative distance** the page quotes, against the largest the transcripts carry over
    the elements both sides wrote.

    page-check.py <run-dir> <page>

Exit 0 when both hold. A page that states neither is not a page this check can clear, and says so.
"""
import re
import struct
import sys


def cases(path):
    """A transcript's cases: the name, and its values as the case file printed them.

    The CNN case file prints one line per case, `name count` and then the values, and the lines that
    report the classes the two builds resolved and the cases that were not compared are results and not
    cases, so they are skipped rather than parsed.
    """
    out, name, values = {}, None, []
    for line in open(path):
        if line.startswith("image ") or " NOT COMPARED:" in line or line.startswith("compared: "):
            if name:
                out[name] = values
            name, values = None, []
            continue
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            if name:
                out[name] = values
            name, values = parts[0], []
        elif parts and name is not None:
            values.extend(parts)
    if name:
        out[name] = values
    return out


def measure(system, port):
    """(the identical set, the largest relative distance over the elements both sides wrote)"""
    identical, worst = set(), 0.0
    for name, a in system.items():
        b = port.get(name)
        if b is None:
            continue
        if len(a) != len(b):
            continue
        if a == b:
            identical.add(name)
            continue
        for x, y in zip(a, b):
            if x == y:
                continue
            fx, fy = float(x), float(y)
            if fx == 0.0 or fy == 0.0:
                continue
            worst = max(worst, abs(fx - fy) / max(abs(fx), abs(fy)))
    return identical, worst


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    rundir, page = argv[1], argv[2]
    system_path, port_path = rundir + "/system.txt", rundir + "/port.txt"
    for p in (system_path, port_path):
        try:
            open(p).close()
        except OSError:
            sys.stderr.write("cnn page-check: %s is not there, so nothing was measured and this check "
                             "cannot pass\n" % p)
            return 2
    system, port = cases(system_path), cases(port_path)
    if not system:
        sys.stderr.write("cnn page-check: %s carries no case, so nothing was measured\n" % system_path)
        return 2
    identical, worst = measure(system, port)

    text = open(page).read()
    print("measured over %s: %d cases, %d bit-identical, largest relative distance %.3g"
          % (rundir, len(system), len(identical), worst))
    print("  bit-identical: %s" % ", ".join(sorted(identical)))

    bad = 0
    # the page's own list, in the form it writes it: `name` and `name` in one backticked run
    m = re.search(r"\*\*Five of the six cases are bit-identical\*\*, and they are the run's own list: (.+?)\n"
                  r"`batch-normalization` is", text, re.S)
    if not m:
        print("  FAIL  the page does not say which cases are bit-identical, in the form this check reads")
        return 1
    said = set(re.findall(r"`([^`]+)`", m.group(1)))
    if said == identical:
        print("  ok    the page names exactly the run's bit-identical cases")
    else:
        print("  FAIL  the page names %s and the run's bit-identical cases are %s"
              % (", ".join(sorted(said)), ", ".join(sorted(identical))))
        bad += 1
    # a case the page calls identical that the run shows as differing is the failure that matters, and
    # it is named on its own so a reader does not have to diff the two sets to find it
    for name in sorted(said - identical):
        print("       the page calls %s bit-identical and the transcript says otherwise" % name)

    d = re.search(r"largest\s+distance anywhere in the slice at\s+(\d(?:\.\d+)?(?:e[-+]?\d+)?) relative", text)
    if not d:
        print("  FAIL  the page quotes no largest distance, so this check examined nothing about it")
        bad += 1
    else:
        said_value = float(d.group(1))
        # 1.18e-07 is the page's rounding of 1.175e-07; compare at the precision the page wrote
        if abs(said_value - worst) <= 0.02 * worst:
            print("  ok    the page's largest distance %.3g is what the transcripts carry (%.3g)"
                  % (said_value, worst))
        else:
            print("  FAIL  the page says %.3g and the transcripts carry %.3g" % (said_value, worst))
            bad += 1

    print("%d claim(s) checked, %d wrong" % (2, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
