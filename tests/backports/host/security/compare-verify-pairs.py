#!/usr/bin/env python3
"""The (operation, algorithm) pairs the table claims for VERIFY, and the broken pair NAMED.

    python3 compare-verify-pairs.py <the binary's output>

Four pairs, and they are the ones where verify could go wrong in a way signing would not: an RSA key
asked to verify an ECDSA signature, an EC key asked to sign anything at all, and the two digest paddings
the release really does carry. The padding column is there so a difference in the TABLE and a difference
in the PADDING are reported separately - they are different mistakes.
"""
import sys

# label: (whether the table carries it, the padding it must check with)
EXPECTED = {
    "verify-rsa-sha256": (True, 32772),    # 0x8004, the release carries it
    "verify-rsa-sha384": (True, 32773),    # 0x8005
    # CARRIED, for the same measured reason as compare-supported.py's ec-sign-sha256: the release has
    # an EC key type (kSecAttrKeyTypeEC, ios(4.0), SecItem.h:802-803) and SecKeyRawVerify takes it. The
    # padding stays kSecPaddingNone, which is 0 - a curve has no padding scheme - and this pair is the
    # one that says so.
    "verify-ec-sha256": (True, 0),
    "verify-rsa-ecdsa": (False, 0),        # an ECDSA algorithm asked of an RSA key is not a thing
}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-verify-pairs.py: pass the binary's output")
    seen, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            parts = line.split("\t")
            seen[parts[0]] = (parts[1], parts[2])
    bad = list(wrong)
    for label, (want_carry, want_pad) in EXPECTED.items():
        got = seen.get(label)
        if got is None:
            bad.append("%s: the case did not ask about it" % label)
            continue
        if (got[0] == "1") != want_carry:
            bad.append("%s: the table said [%s] and the port claims [%s]"
                       % (label, "carries" if got[0] == "1" else "cannot",
                          "carries" if want_carry else "cannot"))
        elif got[1] != str(want_pad):
            bad.append("%s: carried, but the padding is [%s] and the header's enumerator is %d"
                       % (label, got[1], want_pad))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d verify pairs, and the padding each carried one checks with" % len(EXPECTED))


if __name__ == "__main__":
    sys.exit(main())
