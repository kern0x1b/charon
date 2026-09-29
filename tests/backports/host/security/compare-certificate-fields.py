#!/usr/bin/env python3
"""The common name and the addresses, against the HOST'S OWN accessors, differences NAMED.

    python3 compare-certificate-fields.py <the binary's output>

The host's copies come off the system framework handle, not by calling the name - this case defines the
same names, and a case that called them would compare the port with itself. Every address the port
produced is printed against the host's at the same index, so a missing one and an extra one are different
failures and are named differently.
"""
import sys

EXPECTED_CN = "charon-der-test"
EXPECTED_MAIL = "charon-der-test@example.invalid"


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-certificate-fields.py: pass the binary's output")
    rows, wrong, port_mail, host_mail = {}, [], [], []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            parts = line.split("\t")
            rows[parts[0]] = parts[1:]
            if parts[0].startswith("email-port-"):
                port_mail.append(parts[1] if len(parts) > 1 else "")
            elif parts[0].startswith("email-host-"):
                host_mail.append(parts[1] if len(parts) > 1 else "")
    bad = list(wrong)
    if rows.get("host-symbols", [None])[0] != "both":
        bad.append("host-symbols: the host's own accessors were not both found, so nothing was compared")
    cn = rows.get("common-name", [])
    if len(cn) < 2:
        bad.append("common-name: the case did not read it")
    elif cn[0] != EXPECTED_CN or cn[1] != EXPECTED_CN:
        bad.append("common-name: port [%s] host [%s] and the certificate's own CN is [%s]"
                   % (cn[0], cn[1], EXPECTED_CN))
    counts = rows.get("email-count", [])
    if len(counts) < 2:
        bad.append("email-count: the case did not read it")
    else:
        if counts[0] != counts[1]:
            bad.append("email-count: the port found %s addresses and the host found %s"
                       % (counts[0], counts[1]))
        if port_mail != host_mail:
            bad.append("email: the port's %r are not the host's %r" % (port_mail, host_mail))
        elif port_mail != [EXPECTED_MAIL]:
            bad.append("email: the fixture's rfc822Name is [%s] and the port gave %r"
                       % (EXPECTED_MAIL, port_mail))
    if rows.get("null-out", [None])[0] != "-50":
        bad.append("null-out: a NULL out-parameter is errSecParam (-50)")
    if rows.get("null-cert", [None])[0] != "-50":
        bad.append("null-cert: a NULL certificate is errSecParam (-50), not a crash")
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared the common name and %d address against the host's own accessors, and 2 refusals"
          % len(port_mail))


if __name__ == "__main__":
    sys.exit(main())
