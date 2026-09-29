#!/bin/sh
# EVERY Security host case, from the tree, in one command: build it with the port sources it needs, run
# it, compare it, and then run a MUTATION of it and require the comparison to notice.
#
# This file exists because nothing ran the compare-*.py scripts. A check nobody invokes is a check that
# cannot fail, so the comparisons are driven HERE and a run in which one of them is skipped is a failure
# rather than a quiet pass.
#
# A case is built WITH the port source that defines the symbols it calls, and that is the shim: the
# system half on its own has no _CharonSecurityCarries, _CharonSecurityPaddingFor,
# _CharonCertificateNameTLV or _CharonSecurityAttributesFromItemResult, and the reviewer's build line
# linked without them. The host's own accessors are reached by dlsym off the SYSTEM framework handle, in
# the cases themselves - see the header of each.
#
# Exit non-zero on: a build that fails, a comparison that differs, a mutation that goes UNNOTICED, and a
# case that is not listed below. GREEN/RED lines are printed for each, so a log shows what was checked.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=$(cd "$here/../../../.." && pwd)
build=${BUILD:-$work/.agent-work/runs/run-cases}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
S="$work/packages/a/apple-backports/Security"
H="$here"
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks"
common="$common -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc"
frameworks="-framework Foundation -framework Security -framework CoreFoundation"
failures=0

# run NAME PORT-SOURCES... -- COMPARE-SCRIPT ; a mutation is applied by mutate_NAME below
run_case() {
    name=$1; shift
    compare=$1; shift
    if ! xcrun clang $common "$@" -framework Foundation -framework Security -framework CoreFoundation \
         -o "$build/$name" > "$build/$name.log" 2>&1; then
        echo "BUILD  $name FAILED - $build/$name.log"
        sed -n '1,5p' "$build/$name.log" | sed 's/^/       /'
        failures=$((failures + 1))
        return
    fi
    ( cd "$work" && "$build/$name" ) > "$build/$name.out" 2>&1
    status=$?
    # A SIGNAL IS NOT A DIFFERENCE. exit 128+N is death by signal N, and the output is whatever was
    # printed before the process died - so running the comparison on it would say "the port's class was
    # not found" about a process that never got that far. Three mutations in this series were caught
    # this way (134 for the C strings, 139 for the dispatch_data values) and each was reported as a
    # harness failure rather than as the crash it was.
    if [ "$status" -ge 128 ]; then
        echo "CRASH  $name  crashed: signal $((status - 128)) (exit $status), not a difference"
        sed 's/^/       /' "$build/$name.out" | tail -3
        failures=$((failures + 1))
        return
    fi
    if python3 "$H/$compare" "$build/$name.out" > "$build/$name.green" 2>&1; then
        echo "GREEN  $name  $(tail -1 "$build/$name.green")"
    else
        echo "RED    $name  $(tail -1 "$build/$name.green")"
        sed 's/^/       /' "$build/$name.green"
        failures=$((failures + 1))
    fi
}

# A mutation must make its comparison FAIL. A mutation that still passes is a useless mutation, and a run
# that accepted one would be reporting coverage it does not have - so that is an error, not a pass.
run_mutation() {
    name=$1; compare=$2
    if [ ! -f "$build/mutant-$name.m" ]; then
        echo "RED    $name mutation NOT BUILT - nothing proved the case can fail"
        failures=$((failures + 1))
        return
    fi
    if ! xcrun clang $common "$H/$name.m" "$build/mutant-$name.m" \
         -framework Foundation -framework Security -framework CoreFoundation \
         -o "$build/mutant-$name" > "$build/mutant-$name.log" 2>&1; then
        echo "BUILD  $name mutation FAILED to build"
        failures=$((failures + 1))
        return
    fi
    ( cd "$work" && "$build/mutant-$name" ) > "$build/mutant-$name.out" 2>&1
    status=$?
    if [ "$status" -ge 128 ]; then
        echo "CRASH  $name mutation  crashed: signal $((status - 128)) (exit $status), not a difference"
        failures=$((failures + 1))
        return
    fi
    if python3 "$H/$compare" "$build/mutant-$name.out" > "$build/mutant-$name.red" 2>&1; then
        echo "RED    $name MUTATION WENT UNNOTICED - the comparison cannot tell this case from a broken one"
        failures=$((failures + 1))
    else
        echo "RED    $name mutation  $(grep -m1 DIFFERS "$build/mutant-$name.red" | cut -c9-)"
    fi
}

# --- the mutants, written by patching the port source in the tree and keeping the copy ---
mutate() {
    python3 - "$@" <<'PY'
import sys
src, out, old, new, why = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit("the mutation anchor for %s matched %d times, not once" % (out, s.count(old)))
open(out, 'w').write(s.replace(old, new))
print("  mutant %s: %s" % (out.rsplit('/', 1)[-1], why))
PY
}

F=$S/SecurityFunctions10_0_1.m
D=$S/SecCertificateNameDER10_3.m
N=$S/SecTrustNetworkFetch7_0.m
G=$S/SecTrustGetTrustResult7_0.m

echo "== the Security host cases, from $(git -C "$work" rev-parse --short HEAD 2>/dev/null || echo '?') =="
# The two verdicts a driver must keep apart, checked first so a driver that has conflated them says so
# before it goes on to report anything else.
if xcrun clang -Wall -o "$build/crash-case" "$H/crash-case.c" > "$build/crash-case.log" 2>&1; then
    # set -e EXITS ON A FAILING SIMPLE COMMAND, so "cmd; status=$?" never reaches the assignment: the
    # script died on the segfault before it could record the exit code it was trying to record, which is
    # the same class of bug as the one this commit fixes. `cmd || status=$?` is the form that survives.
    clean=0; missing=0; crashed=0
    "$build/crash-case" clean   >/dev/null 2>&1 || clean=$?
    "$build/crash-case" missing >/dev/null 2>&1 || missing=$?
    "$build/crash-case" crash   >/dev/null 2>&1 2>/dev/null || crashed=$?
    if [ "$clean" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$crashed" -ge 128 ]; then
        echo "GREEN  verdicts     the three shapes behave: clean 0, missing $missing, crash $crashed"
    else
        echo "RED    verdicts     clean $clean, missing $missing, crash $crashed - one shape is wrong"
        failures=$((failures + 1))
    fi
else
    echo "BUILD  crash-case FAILED to build"
    failures=$((failures + 1))
fi
run_case supported          compare-supported.py          $H/supported.m $F
run_case padding           compare-padding.py           $H/padding.m $F
run_case verify-pairs      compare-verify-pairs.py      $H/verify-pairs.m $F
run_case attributes        compare-attributes.py        $H/attributes.m $F
run_case certificate-name  compare-certificate-name.py  $H/certificate-name.m $D
run_case certificate-fields compare-certificate-fields.py $H/certificate-fields.m $D
run_case network-fetch     compare-network-fetch.py     $H/network-fetch.m $N
run_case trust-result      compare-trust-result.py      $H/trust-result.m $G

# The SHA-256 test is made UNSATISFIABLE rather than deleted: a `;` there ends the return and orphans the
# next `||`, so the first version of this mutation did not compile and the run reported a BUILD failure
# where a RED was required. An expression that is still valid but never true drops the algorithm just as
# well and keeps the mutant comparable.
mutate "$F" "$build/mutant-supported.m" \
'                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256)' \
'                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1)   // MUTANT: SHA-256 can never match' \
'the SHA-256 test can never match, so the table loses that algorithm'
mutate "$F" "$build/mutant-padding.m" \
'    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        return kSecPaddingPKCS1SHA256;' \
'    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        return kSecPaddingPKCS1SHA384;   // MUTANT: SHA-384s padding for a SHA-256 algorithm' \
'a SHA-256 algorithm gets the SHA-384 padding'
mutate "$F" "$build/mutant-verify-pairs.m" \
'        return false;      // EC signing arrives after 6.1.3: the release has no EC primitive to sign with' \
'        return ec;         // MUTANT: an EC key is held to sign and verify as well' \
'an EC key is held to carry verification'
mutate "$F" "$build/mutant-attributes.m" \
'    if (CFGetTypeID(result) != CFDictionaryGetTypeID())' \
'    if (0)   // MUTANT: anything at all is passed off as an attributes dictionary' \
'anything is passed off as an attributes dictionary'
mutate "$D" "$build/mutant-certificate-name.m" \
'        at = next;                                // the version'"'"'s own TLV ended here' \
'        at = content;   // MUTANT: resume inside the versions integer' \
'the walk resumes inside the version integer'
mutate "$D" "$build/mutant-certificate-fields.m" \
'static const uint8_t CharonOIDCommonName[] = {0x55, 0x04, 0x03};' \
'static const uint8_t CharonOIDCommonName[] = {0x55, 0x04, 0x04};   // MUTANT: the SURNAME attribute' \
'the common name OID becomes the surname one'
mutate "$N" "$build/mutant-network-fetch.m" \
'        answer = CFSetContainsValue(CharonSecurityNetworkFetchAllowed, trust) ? true : false;' \
'        answer = false;   // MUTANT: the set is consulted and the flag dropped' \
'the network-fetch flag is dropped after being looked up'
mutate "$G" "$build/mutant-trust-result.m" \
'    return SecTrustEvaluate(trust, result);   // the release'"'"'s own, iOS 2.0' \
'    *result = kSecTrustResultProceed;   // MUTANT: a verdict invented here
    return errSecSuccess;' \
'a verdict is invented instead of the releases own'

run_mutation supported          compare-supported.py
run_mutation padding           compare-padding.py
run_mutation verify-pairs      compare-verify-pairs.py
run_mutation attributes        compare-attributes.py
run_mutation certificate-name  compare-certificate-name.py
run_mutation certificate-fields compare-certificate-fields.py
run_mutation network-fetch     compare-network-fetch.py
run_mutation trust-result      compare-trust-result.py

# --- the fuzz: no comparison, it must simply not crash, and it is built with the sanitizers on ---
if xcrun clang $common -fsanitize=address,undefined -fno-omit-frame-pointer -g \
     "$H/der-fuzz.m" "$D" -framework Foundation -framework Security -framework CoreFoundation \
     -o "$build/der-fuzz" > "$build/der-fuzz.log" 2>&1; then
    if ( cd "$work" && ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 "$build/der-fuzz" ) \
         > "$build/der-fuzz.out" 2>&1; then
        echo "GREEN  der-fuzz  $(tail -2 "$build/der-fuzz.out" | head -1)"
    else
        echo "RED    der-fuzz CRASHED OR TRIPPED A SANITIZER"
        tail -12 "$build/der-fuzz.out" | sed 's/^/       /'
        failures=$((failures + 1))
    fi
else
    echo "BUILD  der-fuzz FAILED - $build/der-fuzz.log"
    failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "run-cases: OK - every case compared, and every mutation noticed"
else
    echo "run-cases: $failures failure(s)"
fi
exit "$failures"
