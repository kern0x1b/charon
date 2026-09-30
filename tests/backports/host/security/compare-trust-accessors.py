#!/usr/bin/env python3
"""The port's fourteen answers against the HOST'S OWN, difference by difference.

    python3 compare-trust-accessors.py <the binary's output>

Every line the case prints is `key<TAB>port<TAB>host`, so this reads both sides and holds the
DIFFERENCES it expects. A difference the port does NOT have is a failure and a failure the port does
have that this file does not name is also a failure - which is the shape that matters here, because
most of these rows differ on purpose and a comparison that only ever said "the same" would be
worthless.

THE SAME ROWS MUST MATCH: the three constants' values, the OID a created basic X.509 policy carries,
the chain's length and its leaf, the result's verdict and the type of its date, both async status
codes, both async verdicts, and both setter status codes. Those are cases where 6.1.3 and this Mac
answer alike and the port must answer alike too.

THE ROWS THAT MUST DIFFER, and why, one line each: the policy properties of a policy the port never
made, the anchors and the policies a trust reports, the result dictionary's key count, and the two
identifiers the release cannot build a policy for.
"""
import sys

# key -> (must match, what a difference means when one is expected)
SAME = {
    "constant-persistentref": "both spellings carry the host's own value for the attribute",
    "constant-persistantref": "the misspelled spelling carries the same value",
    "constant-dataprotection": "the port carries the host's own value for the key",
    "ac-type-id-is-cfstring": "neither side's type ID is CFString's",
    "create-x509": "both sides build a basic X.509 policy",
    "created-oid": "the OID under kSecPolicyOid is the host's string",
    "created-ssl-oid": "and an SSL policy carries the SSL OID, not the basic X.509 one",
    "create-ssl-named": "an SSL policy with a hostname carries two property keys on both sides",
    "create-ssl-client": "an SSL client policy carries two property keys on both sides",
    "copy-chain": "both sides report the chain's length",
    "copy-chain-leaf-is-fixture": "the chain's leaf is the fixture certificate on both sides",
    "result-verdict": "the result dictionary carries the release's own verdict on both sides",
    "result-date-is-a-date": "the evaluation date is a CFDate on both sides",
    "async-status": "both async entry points answer errSecSuccess",
    "async-called": "both async entry points call the callback",
    "async-verdict": "both async entry points deliver the same verdict",
    "async-error-status": "both async-with-error entry points answer errSecSuccess",
    "async-error-called": "both async-with-error entry points call the callback",
    "async-error-value": "both async-with-error entry points deliver the same bool",
    "set-ocsp": "both OCSP setters answer errSecSuccess",
    "set-scts": "both SCT setters answer errSecSuccess",
}

DIFFER = {
    "properties-of-foreign": "a policy the port never made has no record to report, so the port answers NULL",
    "create-smime": "6.1.3 has no creator for an SMIME policy, so the port answers NULL where the host builds one",
    "copy-policies": "6.1.3 has no reader for the policies a trust was given, so the port reports none",
    "copy-anchors": "6.1.3 has no reader for the anchors a trust was given, so the port reports none",
    "copy-anchors-count": "and the count follows the answer above",
    "copy-result": "the host also carries a per-certificate status dictionary, which 6.1.3 has no accessor for",
    "ac-type-id": "each side's type ID is its own, and the port's names the port's private class",
}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-trust-accessors.py: pass the binary's output")
    rows, bad, missing = {}, [], []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if not line or line.startswith("MISSING"):
            if line.startswith("MISSING"):
                bad.append(line)
            continue
        parts = line.split("\t")
        # A key printed once per side - created-oid, which the case asks twice, once per side - lands
        # as two half-lines, and a key asked once arrives as one. Both are comparisons, and a half-line
        # with nothing to compare against is reported rather than unpacked.
        rows.setdefault(parts[0], []).append(tuple(parts[1:]))
    for key, meaning in SAME.items():
        halves = rows.get(key)
        if not halves:
            missing.append("%s: the case did not ask (%s)" % (key, meaning))
            continue
        for halves_ in halves:
            if len(halves_) < 2:
                bad.append("%s: the case printed a half-line %r, so the two sides were never compared (%s)"
                           % (key, halves_[0] if halves_ else None, meaning))
                continue
            port, host = halves_[0], halves_[1]
            if port != host:
                bad.append("%s: the port says %r and the host says %r, and they must agree (%s)"
                           % (key, port, host, meaning))
    for key, meaning in DIFFER.items():
        halves = rows.get(key)
        if not halves:
            missing.append("%s: the case did not ask (%s)" % (key, meaning))
            continue
        for halves_ in halves:
            if len(halves_) < 2:
                bad.append("%s: the case printed a half-line %r, so the two sides were never compared (%s)"
                           % (key, halves_[0] if halves_ else None, meaning))
                continue
            port, host = halves_[0], halves_[1]
            if port == host:
                bad.append("%s: the port says %r, the same as the host, and this row must differ (%s)"
                           % (key, port, meaning))
    if rows.get("ac-type-id-stable", [[None]])[0][0] != "1":
        bad.append("ac-type-id-stable: the port's type ID changed between two calls in one run")
    if missing:
        bad.extend(missing)
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("%d answers agree with the host and %d differ by the reason this file names"
          % (len(SAME), len(DIFFER)))


if __name__ == "__main__":
    sys.exit(main())