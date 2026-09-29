#!/usr/bin/env python3
"""The table's answers, expected, and the pairs that answer wrongly NAMED.

    python3 compare-supported.py <the binary's output>

The expectation is written here rather than derived, because these are the port's CLAIMS and not the
SDK's constants: what iOS 6.1.3 can carry, one pair at a time. A case that printed a passing message
because it compared nothing would be a check in name only, so every pair is named here and a difference
names the pair.
"""
import sys

EXPECTED = {
    "rsa-sign-sha256": "YES",     # SecKeyRawSign over kSecPaddingPKCS1SHA1 carries a digest
    "rsa-verify-sha256": "YES",   # and SecKeyRawVerify verifies what it signed
    "rsa-sign-sha1": "YES",
    "rsa-encrypt-oaep": "YES",    # SecKeyEncrypt
    "rsa-decrypt-pkcs1": "YES",   # SecKeyDecrypt
    "ec-sign-sha256": "NO",       # the release has no EC primitive to sign with
    "rsa-keyexchange": "NO",      # and no key-exchange primitive at all
    "rsa-sign-unknown": "NO",     # an EC algorithm asked of an RSA key is not a thing it carries
}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-supported.py: pass the binary's output")
    seen = {}
    for line in open(sys.argv[1]):
        if "\t" in line:
            name, value = line.rstrip("\n").split("\t", 1)
            seen[name] = value
    bad = []
    for name, want in EXPECTED.items():
        got = seen.get(name)
        if got != want:
            bad.append("%s: the table answered [%s] and the port claims [%s]" % (name, got, want))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d operation/algorithm pairs: every one is what the port claims" % len(EXPECTED))


if __name__ == "__main__":
    sys.exit(main())
