#!/usr/bin/env python3
# compare.py HOST PORT [TOLERANCE] : the two probes' answers, line by line, by key.
# A key is everything up to the first number in a line, so "box vertices 9" and "box vertices 12" are
# the same measurement. Numbers are compared to a tolerance, so a value the two round differently is
# not a difference. A key one side has and the other does not is reported on its own line: that is a
# measurement the host cannot be asked, not a disagreement.
import re, sys

host_path, port_path = sys.argv[1], sys.argv[2]
tolerance = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0

KEY = re.compile(r'^(.*?)(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)(\s|$)')

def read(path):
    # A key seen again is the same key a second time, and is matched as such: the two runs walk the
    # same script, so the n-th occurrence of a key here is the n-th occurrence there.
    lines, seen = {}, {}
    for line in open(path):
        line = line.rstrip('\n')
        m = KEY.match(line)
        key = m.group(1) if m else line
        seen[key] = seen.get(key, 0) + 1
        lines[(key, seen[key])] = (m.group(2) if m else None, line)
    return lines

def numbers(text):
    return [float(x) for x in re.findall(r'-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', text)]

host, port = read(host_path), read(port_path)
same = different = only = 0
for key, (value, line) in host.items():
    if key not in port:
        only += 1
        print('only the system answers: %s' % line)
        continue
    other = port[key][1]
    if value is None:
        # A line with no number in it is a name or a set of names: the text is the measurement.
        if line == other:
            same += 1
            continue
    else:
        a, b = numbers(value), numbers(port[key][0] if port[key][0] is not None else '')
        if len(a) == len(b) and all(abs(x - y) <= tolerance for x, y in zip(a, b)):
            same += 1
            continue
    different += 1
    print('different: %s' % line)
    print('        the port: %s' % other)
for key, (value, line) in port.items():
    if key not in host:
        only += 1
        print('only the port answers: %s' % line)
print('modelio: %d measurements, %d the same, %d different, %d one side only (tolerance %g)'
      % (len(host), same, different, only, tolerance))
sys.exit(0 if different == 0 else 1)
