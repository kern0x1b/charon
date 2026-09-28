#!/usr/bin/env python3
"""check_records.py — refuse a record that does not look like one, before it is written over the
expectations a device test reads.

A recorder that writes its expectations on every run must not write a run that did not answer: the
smallapis2 appearance cases need the windowed host's run loop to have run before the colours are
read, and a run that starts too early records "none" or an all-zero colour where the answer is a
colour. That is not an answer changing; it is a run that did not get to ask.

A record is refused when a case's answer is one of the values that means "not asked": empty, "nil" or
"null". A colour that is absent records "none", which is an answer and is left alone. Exits 0 when
every case looks answered, 1 otherwise, and says which.
"""
import json
import sys

# The values that mean a run never asked. A leaf with no colour set has none, and that is an
# answer -- "none" for a colour is a real answer and is not in this set. What is refused is a
# record with no entries at all, or one whose value is empty, which is a run that stopped before
# the case.
NOT_ANSWERED = {"", "nil", "(nil)", "null"}


def main(path):
    with open(path) as handle:
        records = json.load(handle)
    if not isinstance(records, dict) or not records:
        print("%s: no records at all" % path)
        return 1
    refused = [name for name, value in records.items() if str(value).strip() in NOT_ANSWERED]
    if refused:
        print("%s: %d case(s) did not answer: %s" % (path, len(refused), ", ".join(sorted(refused)[:6])))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
