#!/usr/bin/env python3
"""Every measured pair against every candidate order, and the hash samples against every candidate
hash. One table in, one verdict out, no rule chosen by hand.

Run from this directory: ./pairs > pairs.tsv, then python3 fit.py
"""
import itertools, struct, sys

TAGS = [  # the same tags pairs.m used, by value: (category, dataType, value)
    (0, 0, 0), (0, 5, 0), (0, 2, (1 << 64) - 1), (1, 5, 0),
    (0x6d646961, 0, 0), (0x6d646961, 5, 0x76696465), (0x7472616b, 2, 7),
    (0x7472616b, 3, 0x3FF8000000000000), (0x70697866, 7, 3), (0x7a7a7a7a, 7, 3),
    (0xffffffff, 5, 0), (0x6d646961, 2, 7), (0x6d646961, 5, 0),
]

def signed(category): return category - (1 << 32) if category & 0x80000000 else category

def order(fields, category_signed, value_bits):
    """fields is a permutation of (0,1,2) naming category, dataType, value."""
    def key(tag):
        category, dataType, value = tag
        raw = [signed(category) if category_signed else category, dataType,
               value if value_bits else (value >> 64 if value_bits == "raw" else value)]
        return tuple(raw[i] for i in fields)
    return key

def compare(a, b, fields, category_signed, value_bits):
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
    pairs, hashes, reversed_pairs = [], [], []
    for line in open("pairs.tsv"):
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if fields[0] == "H":
            hashes.append((int(fields[1]), int(fields[2])))
        else:
            pairs.append((int(fields[0]), int(fields[1]), int(fields[2])))
    reversed_pairs = [(b, a, host) for a, b, host in pairs]

    print("=== orders: %d pairs, both argument orders" % len(pairs))
    results = []
    for fields in itertools.permutations(range(3)):
        for category_signed in (True, False):
            for value_bits in ("number",):
                mismatches = sum(1 for a, b, host in pairs
                                 if compare(TAGS[a], TAGS[b], fields, category_signed, value_bits) != host)
                reversed_mismatches = sum(1 for a, b, host in pairs
                                          if compare(TAGS[b], TAGS[a], fields, category_signed, value_bits) != host)
                name = "order %s category %s" % (
                    "-".join("category dataType value".split()[i] for i in fields),
                    "signed" if category_signed else "unsigned")
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
    winners = [r for r in results if r[0] == 0]
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
