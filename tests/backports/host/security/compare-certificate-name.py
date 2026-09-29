#!/usr/bin/env python3
"""The port's Name DER against the HOST'S OWN accessors, and the difference NAMED.

    python3 compare-certificate-name.py <the binary's output>

The host's copy is reached by dlopen of the system framework and dlsym off that handle, NOT by calling
the name: the case defines the same function, so a call to the name resolves to the port and the first
version of this case compared the port with itself and passed. Both lengths are printed, because "the
bytes are not the host's" does not say whether the host has different bytes or a different NUMBER of
them - and that is how the two-byte header came to be found.
"""
import sys

# label: (port length, host length, must match)
SAME = {"issuer": 68, "subject": 68}
# label: must be refused
REFUSED = ["malformed-runs-out", "malformed-wrong-tag", "malformed-indefinite",
           "malformed-long-form", "malformed-short-tbs"]
NULLS = ["null-cert", "null-subject"]


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-certificate-name.py: pass the binary's output")
    rows, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            parts = line.split("\t")
            rows[parts[0]] = parts[1:]
    bad = list(wrong)
    for label, want in SAME.items():
        got = rows.get(label)
        if not got or len(got) < 3:
            bad.append("%s: the case did not compare it" % label)
        elif got[2] != "same":
            bad.append("%s: port %s bytes, host %s bytes, and the port claims the host's %d"
                       % (label, got[0], got[1], want))
    if rows.get("selfsigned-same", [None])[0] != "yes":
        bad.append("selfsigned-same: this fixture is self-signed, so issuer and subject MUST match")
    for label in REFUSED:
        got = rows.get(label)
        if not got:
            bad.append("%s: the case did not ask" % label)
        elif got[0] != "refused":
            bad.append("%s: the walk ACCEPTED bytes that are not a certificate" % label)
    for label in NULLS:
        if rows.get(label, [None])[0] != "NULL":
            bad.append("%s: a NULL certificate must answer NULL, not a crash" % label)
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d Names against the host's own accessors, %d malformed shapes refused, %d NULLs"
          % (len(SAME), len(REFUSED), len(NULLS)))


if __name__ == "__main__":
    sys.exit(main())
