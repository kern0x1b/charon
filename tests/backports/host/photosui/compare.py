#!/usr/bin/env python3
"""Compare the host's answers with the port's, line for line, and say what differs.

    python3 tests/backports/host/photosui/compare.py HOST.ANSWERS PORT.ANSWERS stated-differences.tsv

Exits 0 when every question was asked on both sides, every answer is the same, and every stated
difference is really a difference; 1 otherwise, naming what it is. The stated file is a comment block
of "name<TAB>reason" lines, a question the host's own implementation does not answer at all.

Three things fail the comparison, and each of them is a failure a plain diff would report as a pass:

  - a question on one side and not the other. Both sides are asked the same questions, so a missing
    line is a probe that stopped early, and a comparison that skips it is a comparison of fewer
    questions than it claims.
  - a difference nobody stated. The stated list is the whole of what may differ, so a new one is a
    change in behaviour and not a detail.
  - a stated difference that no longer differs. The statement is about a measurement, and a
    measurement that moved leaves the statement wrong; passing on it would keep a claim in the tree
    that its own harness no longer supports.
"""
import sys


def read(path):
    """{name: answer} from a file of "name<TAB>answer" lines, in order."""
    answers, order = {}, []
    with open(path) as stream:
        for line in stream:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, answer = line.partition("\t")
            if name in answers:
                print("FAIL  %s is asked twice on this side, at %s" % (name, path))
                return None, None
            answers[name] = answer
            order.append(name)
    return answers, order


def stated(path):
    """{name: reason} from the stated file, skipping the block that explains it."""
    out = {}
    with open(path) as stream:
        for line in stream:
            line = line.rstrip("\n")
            if not line or line.startswith("//"):
                continue
            name, _, reason = line.partition("\t")
            out[name] = reason
    return out


def main():
    if len(sys.argv) != 4:
        print(__doc__.strip())
        return 2
    host, host_order = read(sys.argv[1])
    port, port_order = read(sys.argv[2])
    if host is None or port is None:
        return 1
    differences = 0
    only_host = [name for name in host_order if name not in port]
    only_port = [name for name in port_order if name not in host]
    for name in only_host:
        print("FAIL  %s is asked of the host and not of the port" % name)
    for name in only_port:
        print("FAIL  %s is asked of the port and not of the host" % name)
    differences += len(only_host) + len(only_port)
    if host_order != [name for name in port_order if name in host]:
        print("FAIL  the two sides ask the questions in a different order")
        differences += 1

    told = stated(sys.argv[3])
    for name in host_order:
        if name not in port:
            continue
        if host[name] == port[name]:
            if name in told:
                print("FAIL  %s is stated as a difference and both sides now answer %s, so the "
                      "statement is stale" % (name, host[name]))
                differences += 1
            continue
        if name in told:
            print("stated  %s: host %s, port %s - %s" % (name, host[name], port[name], told[name]))
            continue
        print("FAIL  %s: the host answers %s, the port answers %s, and nobody stated why"
              % (name, host[name], port[name]))
        differences += 1
    for name in told:
        if name not in host:
            print("FAIL  %s is stated as a difference and is asked of neither side" % name)
            differences += 1

    asked = len(host_order)
    if asked == 0:
        print("FAIL  no question was asked of either side, so nothing was compared")
        return 1
    if differences:
        print("not ok: %d questions, %d unstated differences" % (asked, differences))
        return 1
    print("ok: %d questions, the host's and the port's answers agree on %d and %d differences are "
          "stated with their reasons" % (asked, asked - len(told), len(told)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
