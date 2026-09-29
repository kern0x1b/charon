#!/usr/bin/env python3
"""One mutation of the port's constants object: a value the host did not print.

A mutation that does not apply is an error, not a pass - the run goes red rather than skipping.
"""
import sys

path, api, value = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
needle = 'const CFStringRef %s = CFSTR("' % api
count = text.count(needle)
if count != 1:
    print("expected exactly one %s, found %d" % (api, count))
    sys.exit(1)
start = text.index(needle) + len(needle)
end = text.index('");', start)
open(path, "w").write(text[:start] + value + text[end:])
print("mutated %s to [%s]" % (api, value))
