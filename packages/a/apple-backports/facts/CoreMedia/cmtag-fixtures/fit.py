#!/usr/bin/env python3
"""Every measured pair against every candidate order, and the hash samples against every candidate
hash. One table in, one verdict out, no rule chosen by hand.

Run from this directory: ./pairs > pairs.tsv, then python3 fit.py
"""
import itertools, struct, sys

def _unused():
    return None

def read_table(path):
    """The tags come out of the table, never out of this file: two hand-maintained copies of the same
    data is how the first derivation of this rule came out wrong."""
    tags, pairs, hashes = {}, [], []
    for line in open(path):
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if fields[0] == "T":
            tags[int(fields[1])] = (int(fields[2]), int(fields[3]), int(fields[4]))
        elif fields[0] == "H":
            hashes.append((int(fields[1]), int(fields[2])))
        else:
            pairs.append((int(fields[0]), int(fields[1]), int(fields[2])))
    return tags, pairs, hashes


def signed(category): return category - (1 << 32) if category & 0x80000000 else category

def order(fields, category_signed, value_bits):
    """fields is a permutation of (0,1,2) naming category, dataType, value."""
    def key(tag):
        category, dataType, value = tag
        if value_bits == "raw":
            third = struct.pack(">Q", value)
        elif value_bits.startswith("own-type"):
            # the value as a signed number of its own type, with a NaN equal to EVERYTHING - which is
            # what all fourteen unexplained pairs show - and -0.0 equal to 0.0
            if dataType == 3:
                number = struct.unpack(">d", struct.pack(">Q", value))[0]
                # a NaN becomes its own sentinel, so two NaNs are equal to each other and, with the
                # rule below, to everything else; -0.0 becomes +0.0, which is what the host answers
                if number != number:
                    # a NaN is a position for own-type and an equality for own-type-nan-equal; the
                    # two names must reach different code, which the score check above now proves
                    third = float("-inf") if value_bits == "own-type" else 0.0
                else:
                    third = 0.0 if number == 0.0 else number
            elif dataType == 2:
                third = value - (1 << 64) if value & 0x8000000000000000 else value
            else:
                third = value
        else:
            third = value
        raw = [signed(category) if category_signed else category, dataType, third]
        return tuple(raw[i] for i in fields)
    return key

def pair_compare(a, b):
    """The rule as a comparator over a pair, which is the shape the host's answer has: category as a
    signed 32-bit integer, then data type, then the value - a NaN equal to the other within one category
    and data type, and -0.0 equal to 0.0."""
    # category and data type FIRST, and only then the NaN equality: the list of unexplained pairs is
    # entirely a NaN against a different category or data type, where the host orders by those and the
    # NaN does not override them. A NaN ties only within one category and data type.
    left, right = signed(a[0]), signed(b[0])
    if left != right:
        return -1 if left < right else 1
    if a[1] != b[1]:
        return -1 if a[1] < b[1] else 1
    if is_nan(a) or is_nan(b):
        return 0
    if a[1] == 2:  # SInt64: the value UNSIGNED - the last pair, 7 against 0xffffffffffffffff, is -1 on the
        # host, and only an unsigned reading of an int64 gives that; signed would put 0xffff...ff at -1
        va, vb = a[2], b[2]
    elif a[1] == 3:  # Float64: the value as a signed double, with -0.0 equal to 0.0
        va = struct.unpack(">d", struct.pack(">Q", a[2]))[0] or 0.0
        vb = struct.unpack(">d", struct.pack(">Q", b[2]))[0] or 0.0
    else:
        va, vb = a[2], b[2]
    if va != vb:
        return -1 if va < vb else 1
    return 0


def is_nan(tag):
    """A NaN read out of the tag itself, not out of a key: a key cannot carry the fact, because the
    sentinel that would carry it is a number and the host's answer is an equality rather than a place."""
    category, dataType, value = tag
    if dataType != 3:
        return False
    return struct.unpack(">d", struct.pack(">Q", value))[0] != struct.unpack(">d", struct.pack(">Q", value))[0]


def compare(a, b, fields, category_signed, value_bits):
    # the host answers EQUAL for a NaN against anything, measured over every pair that involves one
    if value_bits == "own-type-nan-equal" and (is_nan(a) or is_nan(b)):
        return 0
    ka, kb = order(fields, category_signed, value_bits)(a), order(fields, category_signed, value_bits)(b)
    return 0 if ka == kb else (-1 if ka < kb else 1)

def memcmp_fields(a, b, fields, big_endian):
    def key(tag):
        out = []
        for index in fields:
            size = 4 if index < 2 else 8
            raw = struct.pack(">I" if big_endian else "<I", tag[index] & 0xffffffff) if size == 4 else \
                  struct.pack(">Q" if big_endian else "<Q", tag[index])
            out.append(raw)
        return b"".join(out)
    ka, kb = key(a), key(b)
    return 0 if ka == kb else (-1 if ka < kb else 1)

def main():
    TAGS, pairs, hashes = read_table("pairs.tsv")
    # the value may be compared as a number, as its raw bits, or as the CFNumberCompare of a rendered
    # value whose type is the tag's own - the coordinator's hint, and the only candidate left standing
    # after the field order is fixed.

    print("=== orders: %d pairs, both argument orders" % len(pairs))
    results = []
    for fields in itertools.permutations(range(3)):
        for category_signed in (True, False):
            for value_bits in ("number", "raw", "own-type", "own-type-nan-equal"):
                mismatches = sum(1 for a, b, host in pairs
                                 if compare(TAGS[a], TAGS[b], fields, category_signed, value_bits) != host)
                reversed_mismatches = sum(1 for a, b, host in pairs
                                          if compare(TAGS[b], TAGS[a], fields, category_signed, value_bits) != host)
                name = "order %s category %s value %s" % (
                    "-".join("category dataType value".split()[i] for i in fields),
                    "signed" if category_signed else "unsigned", value_bits)
                results.append((min(mismatches, reversed_mismatches), mismatches, reversed_mismatches, name))
    for fields in itertools.permutations(range(3)):
        for big_endian in (True, False):
            mismatches = sum(1 for a, b, host in pairs
                             if memcmp_fields(TAGS[a], TAGS[b], fields, big_endian) != host)
            reversed_mismatches = sum(1 for a, b, host in pairs
                                      if memcmp_fields(TAGS[b], TAGS[a], fields, big_endian) != host)
            results.append((min(mismatches, reversed_mismatches), mismatches, reversed_mismatches,
                            "memcmp of %s fields %s-endian" % ("-".join("category dataType value".split()[i] for i in fields),
                                                                "big" if big_endian else "little")))
    for best, forward, backward, name in sorted(results):
        print("  %4d mismatches  (%d forward, %d reversed)  %s" % (best, forward, backward, name))
    comparator = [(a, b, host) for a, b, host in pairs if pair_compare(TAGS[a], TAGS[b]) != host]
    comparator_reversed = [(a, b, host) for a, b, host in pairs if pair_compare(TAGS[b], TAGS[a]) != host]
    print("=== the comparator as a pair function, over %d pairs: %d mismatched forward, %d reversed"
          % (len(pairs), len(comparator), len(comparator_reversed)))
    for a, b, host in comparator:
        print("    %3d vs %3d  host %2d  cat %d/%d  type %d/%d  value 0x%016x / 0x%016x"
              % (a, b, host, TAGS[a][0], TAGS[b][0], TAGS[a][1], TAGS[b][1], TAGS[a][2], TAGS[b][2]))
    if comparator_reversed and len(comparator_reversed) < len(comparator):
        print("    the reversed argument order fits better")
    signatures = {}
    for best, forward, backward, name in results:
        signatures.setdefault((best, forward, backward), []).append(name)
    for (best, forward, backward), names in sorted(signatures.items()):
        if len(names) > 1:
            print("STOP: two candidates score identically, so at least one is not running its own code:")
            for name in names:
                print("   %4d (%d forward, %d reversed)  %s" % (best, forward, backward, name))
            raise SystemExit(1)
    print("\n=== every candidate's name changes its score, checked over %d pairs" % len(pairs))
    print("\n=== the top three")
    for best, forward, backward, name in sorted(results)[:3]:
        print("  %4d mismatches  (%d forward, %d reversed)  %s" % (best, forward, backward, name))
    winners = [r for r in results if r[0] == 0]
    best_name = sorted(results)[0][3]
    fields = tuple("category dataType value".split().index(p) for p in best_name.split()[1].split("-"))
    category_signed = "signed" in best_name
    value_bits = best_name.split("value ")[1]
    print("\n=== the type the candidate chose for 1.5 against -0.5")
    for index in (7, 15):
        category, dataType, value = TAGS[index]
        key = order(fields, category_signed, value_bits)((category, dataType, value))
        print("  tag %d: data type %d, value 0x%016x -> key %r (%s)" % (index, dataType, value, key[2], type(key[2]).__name__))
    print("\n=== the pairs the best candidate leaves, with both values as bits")
    for a, b, host in pairs:
        if compare(TAGS[a], TAGS[b], fields, category_signed, value_bits) == host:
            continue
        marks = []
        for index in (a, b):
            category, dataType, value = TAGS[index]
            tag = "cat %d type %d" % (category, dataType)
            if dataType == 3:
                number = struct.unpack(">d", struct.pack(">Q", value))[0]
                if number != number:
                    tag += " NaN"
                elif number == 0.0 and value:
                    tag += " -0.0"
                elif number in (float("inf"), float("-inf")):
                    tag += " %sInf" % ("+" if number > 0 else "-")
                else:
                    tag += " %g" % number
            elif dataType == 2:
                tag += " int %d" % (value - (1 << 64) if value & 0x8000000000000000 else value)
            else:
                tag += " 0x%016x" % value
            marks.append("[%d] %s 0x%016x" % (index, tag, value))
        print("  %3d vs %3d  host %2d  %s" % (a, b, host, "   ".join(marks)))
    if winners:
        print("\nzero-mismatch candidates: %d" % len(winners))
        for _, _, _, name in winners:
            print("  " + name)
    else:
        print("\nNO CANDIDATE EXPLAINS EVERY PAIR. The pairs no candidate with the fewest mismatches covers:")
        best = min(r[0] for r in results)
        for name in [r[3] for r in results if r[0] == best]:
            fields = tuple("category dataType value".split().index(p) for p in name.split()[1].split("-")) \
                     if name.startswith("order") else None
            category_signed = "signed" in name
            print("  %s leaves:" % name)
            for a, b, host in pairs:
                if fields is None:
                    big = "big" in name
                    got = memcmp_fields(TAGS[a], TAGS[b], fields, big) if fields else None
                if fields is not None and compare(TAGS[a], TAGS[b], fields, category_signed, "number") != host:
                    print("    %d vs %d: host %d" % (a, b, host))
    return 0

sys.exit(main())
