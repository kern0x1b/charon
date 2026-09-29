#!/bin/sh
# The kSecKeyAlgorithm constants: every value the port carries must be the host's own, and a value
# written from a rule rather than from a measurement must go red.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(cd "$here/../../../.." && pwd)
obj="$work/packages/a/apple-backports/Security/SecurityConstants11_0.m"
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w"
libs="-framework Foundation -framework Security"

# 0. the case is what the names list says, so a constant cannot go unasked
python3 "$here/gen-security-cases.py" --check

# 1. the host's own Security.framework
xcrun clang $common "$here/main.m" "$here/cases.m" $libs -o "$build/system"
"$build/system" > "$build/system.tsv"
python3 -c "
import json, sys
rows = [l.rstrip(chr(10)).split(chr(9)) for l in open(sys.argv[1]) if chr(9) in l]
json.dump(dict(rows), open(sys.argv[2], 'w'))
" "$build/system.tsv" "$build/system.json"
echo "the host answered: $(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$build/system.json")"

# 2. the port's own object
xcrun clang $common -I"$work/packages/a/apple-backports" "$here/main.m" "$here/cases.m" "$obj" $libs -o "$build/port"
"$build/port" > "$build/port.tsv"
python3 -c "
import json, sys
rows = [l.rstrip(chr(10)).split(chr(9)) for l in open(sys.argv[1]) if chr(9) in l]
json.dump(dict(rows), open(sys.argv[2], 'w'))
" "$build/port.tsv" "$build/port.json"

# 3. the comparison, and a mutation that must go red
python3 "$here/compare.py" "$build/system.json" "$build/port.json"
api=$(head -1 "$here/algorithms.txt")
cp "$obj" "$build/mutant.m"
python3 "$here/mutate.py" "$build/mutant.m" "$api" "NotTheHostsValue" > /dev/null
xcrun clang $common -I"$work/packages/a/apple-backports" "$here/main.m" "$here/cases.m" "$build/mutant.m" $libs -o "$build/mutant"
"$build/mutant" > "$build/mutant.tsv"
python3 -c "
import json, sys
rows = [l.rstrip(chr(10)).split(chr(9)) for l in open(sys.argv[1]) if chr(9) in l]
json.dump(dict(rows), open(sys.argv[2], 'w'))
" "$build/mutant.tsv" "$build/mutant.json"
if python3 "$here/compare.py" "$build/system.json" "$build/mutant.json" | grep -q "DIFFERS $api"; then
    echo "  caught: $api"
else
    echo "MUTANT SURVIVED: $api"; exit 1
fi
echo "mutations: all caught"
