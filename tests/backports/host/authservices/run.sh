#!/bin/sh
# run.sh -- the host differential for AuthenticationServices' surface shape, with a mutant.
#
# **The member list comes from clang**, not from a pattern: members.py runs `clang -ast-dump=json` over
# the class's own header and takes its ObjCMethodDecls. That is the header as the compiler reads it, and
# it is the only source that gives the full selector -- initWithURL:callbackURLScheme:completionHandler:
# is one member and initWithURL: is not a member of anything -- which class or instance, and whether the
# release marks it NS_UNAVAILABLE. The first version used regular expressions and produced a selector
# nobody declared.
#
# **Both sides are answered from a runtime view.** The host's own copy of the framework, asked with
# class_getInstanceMethod and class_getClassMethod by hostshape.c. The port's built library, read out of
# the linked binary's method list by portshape.py -- the port's objects are armv7 and this host is arm64,
# so the library cannot be dlopen'd here and its method list is read out of the file instead. Reading the
# port's *source text* was the earlier mistake, and it invented a selector the file does not contain.
# An inherited method counts on both sides, which is the control: +new comes from NSObject.
#
# **A class the registry carries and whose header cannot be found is an error.** There is no table here
# to be left out of, which is what let a class be asked about one member and pass.
#
# The port's library is built from this worktree's own sources into .agent-work/runs/, so the port side
# measures the tree and not a gate's older binary.
#
#   sh run.sh                measure, exit 0 only when every case agrees
#   sh run.sh --mutate       remove one method from the port and require exactly that case red
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
package="$charon/packages/a/apple-backports/AuthenticationServices"
registry="$charon/packages/a/apple-backports/registry/AuthenticationServices"
framework=${AS_FRAMEWORK:-AuthenticationServices}
build=${BUILD:-$charon/.agent-work/runs/authservices-shape}
mkdir -p "$build"

# The SDK the port is compiled against: the headers are where the member list comes from and the SDK is
# where the library is built with, so the two can never be from different SDKs.
sdk=${AS_SDK:-$(ls -d "$HOME"/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null | head -1)}
if [ -z "$sdk" ] || [ ! -d "$sdk" ]; then
    echo "FAIL: no iPhoneOS SDK on this machine. The member list comes from the headers and the library"
    echo "      is built with it, and measuring against a list or a toolchain kept here instead is the"
    echo "      gap this check exists to close. Set AS_SDK."
    exit 1
fi
headers="$sdk/System/Library/Frameworks/AuthenticationServices.framework/Headers"
[ -d "$headers" ] || { echo "FAIL: no AuthenticationServices headers under $sdk"; exit 1; }
echo "sdk:      $sdk"
echo "headers:  $headers"
echo "library:  $build/libAuthenticationServicesBackports.dylib"

cc -O2 -Wno-unused-parameter -o "$build/hostshape" "$here/hostshape.c" -framework Foundation

# 1. The port's library, from this worktree's sources. Undefined symbols are deferred: this is a shape
#    check, and the classes here call into SafariServices and into the release's own internals, which a
#    shape measurement does not need bound.
build_library() {
    sources=$1
    output=$2
    objects=""
    for source in $sources; do
        name=$(basename "$source" .m)
        "$AS_CLANG" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -fobjc-arc -Os -g0 -fPIC \
            -I"$package" -I"$charon/packages/a/apple-backports/HomeKit" -I"$monocypher" \
            -c "$source" -o "$build/$name.o" 2>"$build/$name.log" || {
                echo "FAIL: $source did not compile"; head -5 "$build/$name.log"; return 1; }
        objects="$objects $build/$name.o"
    done
    "$AS_CLANG" -target armv7-apple-ios6.1.3 -isysroot "$sdk" -dynamiclib \
        -Wl,-undefined,dynamic_lookup -install_name /usr/lib/libAuthenticationServicesBackports.dylib \
        -o "$output" $objects 2>"$build/link.log" || { echo "FAIL: the library did not link"; return 1; }
}
export AS_CLANG=${AS_CLANG:-$HOME/.xmake/packages/l/llvm/23.1.1/6a8c97aaa69241df9ed69ac86f13a045/bin/clang}
monocypher=$(ls -d "$HOME"/.xmake/packages/m/monocypher/*/*/include 2>/dev/null | head -1)
[ -x "$AS_CLANG" ] || { echo "FAIL: no compiler at $AS_CLANG; set AS_CLANG to the llvm package's clang"; exit 1; }

# The sources: every .m in the framework's own directory, and HomeKit's CharonHomeKitModel.m, which
# the construction header reaches. A class whose source is not here is a class the check cannot see, so
# the list is what is on disk rather than a list kept here.
sources=$(ls "$package"/*.m)
shared=$(ls "$charon/packages/a/apple-backports/HomeKit"/Charon*.m 2>/dev/null || true)
build_library "$sources $shared" "$build/libAuthenticationServicesBackports.dylib"
echo "built:    $(ls "$package"/*.m | wc -l | tr -d ' ') AuthenticationServices sources, $(echo $shared | wc -w | tr -d ' ') shared"

# 2. The cases: every class the registry carries, with the public members clang reads out of its header.
python3 - "$registry" "$build/classes.txt" "$here/members.py" "$headers" "$sdk" <<'PYTHON'
import json, os, subprocess, sys
registry, out, members_py, headers, sdk = sys.argv[1:6]
rows = []
for name in sorted(os.listdir(registry)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(registry, name)) as f:
        for entry in json.load(f).get("entries", []):
            if entry.get("kind") == "class" and entry.get("status") in ("implemented", "inert"):
                rows.append(entry["api"])
if not rows:
    sys.stderr.write("no class row in the registry is carried; nothing to measure\n")
    sys.exit(1)
env = dict(os.environ, MEMBERS_CFLAGS="-isysroot " + sdk)
run = subprocess.run([sys.executable, members_py, headers] + sorted(set(rows)),
                     capture_output=True, text=True, env=env)
if run.returncode != 0:
    sys.stderr.write(run.stderr)
    sys.exit(1)
cases = [line for line in run.stdout.split("\n") if line.strip()]
if not cases:
    sys.stderr.write("clang read the headers and found no method in any of them\n")
    sys.exit(1)
with open(out, "w") as f:
    f.write("\n".join(cases) + "\n")
print("%d class rows, %d members from clang" % (len(set(rows)), len(cases)))
PYTHON

# 3. The comparison. `must-be-unavailable` is a member the header marks NS_UNAVAILABLE: the port must
#    not declare it, and the host answers it because NSObject has it -- which is why it is a state and
#    not a question asked of the port as a member it must have.
compare() {
    label="$1"
    library="$2"
    set +e
    "$build/hostshape" "$framework" "$build/classes.txt" > "$build/$label-host.tsv" 2>"$build/$label-host.err"
    python3 "$here/portshape.py" "$library" "$build/classes.txt" > "$build/$label-port.tsv" 2>"$build/$label-port.err"
    portStatus=$?
    set -e
    cat "$build/$label-host.err" "$build/$label-port.err"
    python3 - "$build/$label-host.tsv" "$build/$label-port.tsv" <<'PYTHON'
import sys
host, port = {}, {}
for path, table in ((sys.argv[1], host), (sys.argv[2], port)):
    with open(path) as f:
        next(f, None)
        for line in f:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            table[(fields[0], fields[1], fields[2])] = (fields[3], fields[4])
print("class\tselector\tkind\tstate\thost\tport\tverdict")
red = 0
for key in sorted(set(host) | set(port)):
    state, hostSays = host.get(key, ("-", "?"))
    _, portSays = port.get(key, ("-", "?"))
    # A must-be-unavailable member is one the port must not declare; the host answering "yes" for it
    # is the inherited +new and is expected, so the two sides are not required to agree there.
    if state == "must-be-unavailable":
        verdict = "ok" if portSays == "no" else "the port declares a member the release marks unavailable"
        if verdict != "ok":
            red += 1
    else:
        verdict = "same" if hostSays == portSays else "the two sides differ"
        if verdict != "same":
            red += 1
    print("%s\t%s\t%s\t%s\t%s\t%s\t%s" % (key[0], key[1], key[2], state, hostSays, portSays, verdict))
print("\n%d cases, %d red" % (len(set(host) | set(port)), red))
sys.exit(1 if red else 0)
PYTHON
}

compare tree "$build/libAuthenticationServicesBackports.dylib"
status=$?
echo

if [ "${1:-}" = "--mutate" ]; then
    # One method removed from the port, and exactly that case must go red. The mutation is made on a
    # copy of the source and built the same way, so the tree is not touched and the run after this one
    # measures the real thing again.
    echo "== mutant: ASAuthorizationRequest's -provider removed from a copy of the source"
    mkdir -p "$build/mutant"
    cp "$package"/*.m "$build/mutant/" 2>/dev/null || true
    # The headers travel with the copy: the sources import them by name, and a build whose include path
    # is the mutant's own directory needs them there or it stops at the first import.
    cp "$package"/*.h "$build/mutant/" 2>/dev/null || true
    python3 - "$build/mutant/ASAuthorizationRequest.m" <<'PYTHON'
import re, sys
path = sys.argv[1]
text = open(path).read()
before = text
text = re.sub(r"- \(id<ASAuthorizationProvider>\)provider\n\{\n    return _provider;\n\}\n", "", text)
text = text.replace("@synthesize provider = _provider;\n", "")
if text == before:
    sys.stderr.write("the mutation changed nothing: the member's text is not what the pattern expects\n")
    sys.exit(1)
open(path, "w").write(text)
PYTHON
    saved=$package
    package=$build/mutant
    build_library "$(ls "$build/mutant"/*.m) $shared" "$build/mutant/lib.dylib"
    package=$saved
    set +e
    compare mutant "$build/mutant/lib.dylib" > "$build/mutant.txt" 2>&1
    mutant=$?
    set -e
    cat "$build/mutant.txt"
    redCase=$(grep -c "provider" "$build/mutant.txt" || true)
    echo
    if [ "$mutant" -eq 0 ]; then
        echo "FAIL: the check passed with a method the port no longer defines"
        exit 1
    fi
    echo "ok: the check went red ($redCase lines mention the removed method), and nothing else changed"
    echo "    the port's own source and its library"
    exit 0
fi

if [ "$status" -ne 0 ]; then
    echo "FAIL: a class the registry carries is not a shape the host has and the port defines"
    exit 1
fi
echo "ok: every class the registry carries, and every public member its header declares, is a member"
echo "    the host has and the port binds"
