import json, sys

data = json.load(open(sys.argv[1]))
text = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
with open(sys.argv[2], "w") as output:
    output.write("static const char url_expectations[] =\n")
    for start in range(0, len(text), 160):
        chunk = text[start:start + 160].replace("\\", "\\\\").replace('"', '\\"').replace("?", "\\?")
        output.write('    "%s"\n' % chunk)
    output.write(";\n")
