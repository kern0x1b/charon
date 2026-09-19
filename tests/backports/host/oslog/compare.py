import re, sys
system_text = open(sys.argv[1], errors="surrogateescape").read()
ours = {}
for record in open(sys.argv[2], "rb").read().split(b"\0"):
    if record:
        index, _, text = record.partition(b"\x1f")
        ours[int(index)] = text.decode("utf-8", "surrogateescape")
lines = re.split(r"(?m)^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+[+-]\d{4} \S+\[\d+:\d+\] \[c(\d+)\] ", system_text)
system = {}
for position in range(1, len(lines), 2):
    system[int(lines[position])] = lines[position + 1].rstrip("\n")
failures = 0
for index in sorted(ours):
    a, b = system.get(index), ours[index]
    if a == b:
        print("ok   case %d: %s" % (index, b.replace("\n", "\\n")[:110]))
    else:
        failures += 1
        print("FAIL case %d: the system answers %r, the backport answers %r" % (index, a, b))
print("%d checks, %d failures" % (len(ours), failures))
if len(sys.argv) > 3 and not failures:
    limit = int(sys.argv[4])
    rows = []
    for index in sorted(system):
        if index <= limit:
            escaped = "".join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else "\\%03o" % b for b in system[index].encode("utf-8", "surrogateescape"))
            rows.append('    {%d, "%s"},' % (index, escaped))
    open(sys.argv[3], "w").write("static const struct {\n    int index;\n    const char *text;\n} charon_oslog_expected[] = {\n" + "\n".join(rows) + "\n};\n")
sys.exit(1 if failures else 0)
