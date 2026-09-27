#!/bin/bash
# The port's CreateML against the host's own CreateML, in one process.
#
# The port's sources are compiled under the module names `PortCreateMLComponents` and `PortCreateML`
# so that Apple's `CreateML` and this port's `CreateML` are two modules declaring the same type
# names, and the differential can hold both in one process. The only edit made to the sources is the
# module's own name: every `CreateMLComponents` becomes `PortCreateMLComponents`, which is the import
# line and every qualified use of the port's own types. The sources keep the qualified spelling
# because it says where each type comes from, and the rename is done here rather than in the sources
# because the sources are the armv7 build's, where the spelling is the right one.
#
# What has to be true for this to be a differential rather than two programs: the same sources, one
# module renamed. What is compared, and what is deliberately not, is in differential.swift's header.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
charon=$(cd "$here/../../../.." && pwd)
files="$charon/packages/c/createml/files"
out="${TMPDIR:-/tmp}/createml-differential.$$"
mkdir -p "$out/modules"
trap 'rm -rf "$out"' EXIT

cp -R "$files" "$out/files"
python3 - "$out/files" <<'PY'
import os, re, sys
root = sys.argv[1]
for dirpath, _, names in os.walk(root):
    for name in names:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        text = open(path).read()
        # The whole word, not the import line: the port's sources qualify their own types with the
        # module's name, and a half-renamed copy would not compile.
        assert "PortCreateMLComponents" not in text, path
        open(path, "w").write(re.sub(r"\bCreateMLComponents\b", "PortCreateMLComponents", text))
PY

xcrun swiftc -swift-version 5 -wmo -O \
    -module-name PortCreateMLComponents \
    -emit-module -emit-module-path "$out/modules/PortCreateMLComponents.swiftmodule" \
    -c -o "$out/cmc.o" "$out"/files/CreateMLComponents/*.swift

xcrun swiftc -swift-version 5 -wmo -O \
    -module-name PortCreateML \
    -I "$out/modules" \
    -emit-module -emit-module-path "$out/modules/PortCreateML.swiftmodule" \
    -c -o "$out/cml.o" "$out"/files/CreateML/*.swift

# The two port modules are linked as the objects just built, with the modules beside them, so the
# differential sees one binary holding Apple's CreateML and the port's under different names.
xcrun swiftc -swift-version 5 -O -I "$out/modules" \
    "$here/differential.swift" "$out/cmc.o" "$out/cml.o" \
    -framework Accelerate -framework Foundation -framework CoreFoundation -framework CreateML \
    -o "$out/differential"

"$out/differential"
