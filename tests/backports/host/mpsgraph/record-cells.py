#!/usr/bin/env python3
# record-cells.py RUN - the cells of a run that are neither equal nor within tolerances.txt, as
# recorded-cells.txt spells them. The bytes are read out of the run's own outputs and the tolerance out of
# the file the harness itself reads, so this writes exactly what the harness will ask about: a record made
# any other way is a record of something else.
#
#     sh tests/backports/host/mpsgraph/run.sh          # the run, green or red
#     python3 tests/backports/host/mpsgraph/record-cells.py <build> > <the new record>
#
# and the harness's own verdict on the record is what accepts it: a line here whose bytes are not the two
# the run answered fails the comparison, and so does a line that is not here.
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
run = sys.argv[1]
tol = {}
for line in open(os.path.join(here, 'tolerances.txt')):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    case, typ, n = line.split()
    tol[(case, typ)] = int(n)

def rows(side):
    out = {}
    for line in open('%s/%s.txt' % (run, side)):
        p = line.split()
        if len(p) >= 5:
            out[(p[1], p[2])] = p
    return out

def value_of(pattern):
    return int(bytes.fromhex(pattern)[::-1].hex(), 16)

def monotone(pattern):
    bits = len(pattern) * 4
    value = value_of(pattern)
    sign, magnitude = value >> (bits - 1), value & ((1 << (bits - 1)) - 1)
    return -magnitude if sign else magnitude

def is_nan(pattern):
    value = value_of(pattern)
    if len(pattern) == 4:
        return value & 0x7C00 == 0x7C00 and value & 0x03FF != 0
    return value & 0x7F800000 == 0x7F800000 and value & 0x007FFFFF != 0

def is_zero(pattern):
    return value_of(pattern) & ((1 << (len(pattern) * 4 - 1)) - 1) == 0

system, port = rows('system'), rows('port')
out = []
for key in sorted(system):
    if key not in port:
        continue
    a, b = system[key], port[key]
    width = {"float32": 8, "float16": 4, "int32": 8}.get(key[1], 2)
    allowed = tol.get(key, 0)
    for i in range(int(a[3]) * 2 // width):
        x = a[4][i * width:(i + 1) * width]
        y = b[4][i * width:(i + 1) * width]
        if x == y:
            continue
        if allowed and key[1] in ('float32', 'float16'):
            if is_nan(x) and is_nan(y):
                continue
            if not (is_nan(x) or is_nan(y)):
                if (is_zero(x) and is_zero(y)) or abs(monotone(x) - monotone(y)) <= allowed:
                    continue
        out.append('%s %s %d %s %s' % (key[0], key[1], i, x, y))
print('\n'.join(out))
