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
cases=0
mutants=0
mutants_noticed=0

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
    # `cmd > out 2>&1` FOLLOWED BY `status=$?` ON THE NEXT LINE CANNOT WORK: set -e ends the script on the
    # failing command, so the assignment never runs and the branch below it is unreachable. That is the
    # whole of exit 134 - the attributes mutant segfaulted, and the driver died on it before it could say
    # so. `|| status=$?` is the form that survives, and the verdict block already used it.
    status=0
    ( cd "$work" && "$build/$name" ) > "$build/$name.out" 2>&1 || status=$?
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
    name=$1; compare=$2; casefile=${3:-$name}
    if [ ! -f "$build/mutant-$name.m" ]; then
        echo "RED    $name mutation NOT BUILT - nothing proved the case can fail"
        failures=$((failures + 1))
        return
    fi
    if [ ! -f "$build/mutant-$name.m" ]; then
        echo "RED    $name mutation NOT BUILT - nothing proved the case can fail"
        failures=$((failures + 1)); return
    fi
    if ! xcrun clang $common "$H/$casefile.m" "$build/mutant-$name.m" \
         -framework Foundation -framework Security -framework CoreFoundation \
         -o "$build/mutant-$name" > "$build/mutant-$name.log" 2>&1; then
        echo "BUILD  $name mutation FAILED to build"
        failures=$((failures + 1))
        return
    fi
    status=0
    ( cd "$work" && "$build/mutant-$name" ) > "$build/mutant-$name.out" 2>&1 || status=$?
    if [ "$status" -ge 128 ]; then
        # A MUTATION THAT CRASHES WAS NOTICED - that is the most emphatic form of "this comparison can
        # tell the case from a broken one" - so it is NOT a failure of the run, and the run says that
        # rather than leaving a crash and a non-zero exit to describe the same run.
        echo "CRASH  $name mutation  crashed: signal $((status - 128)) (exit $status) - NOTICED, and not a failure: a crash is a mutation the comparison caught"
        return
    fi
    if python3 "$H/$compare" "$build/mutant-$name.out" > "$build/mutant-$name.red" 2>&1; then
        echo "RED    $name MUTATION WENT UNNOTICED - the comparison cannot tell this case from a broken one"
        failures=$((failures + 1))
    else
        echo "RED    $name mutation  $(grep -m1 DIFFERS "$build/mutant-$name.red" | cut -c9-)"
        mutants=$((mutants + 1))
        mutants_noticed=$((mutants_noticed + 1))
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
O=$S/SecObjectWrappers12_0.m
PM=$S/SecProtocolMetadata13_0.m
PMA="$S/SecProtocolMetadataAccessors13_0.m $S/SecProtocolMetadataAccessors16_0.m"
PO=$S/SecProtocolOptions13_0.m
PC=$S/SecProtocolOptionsCiphersuite13_0.m
PR=$S/SecProtocolOptionsStrings13_0.m
PK=$S/SecProtocolOptionsBlocks13_0.m
PF=$S/SecProtocolOptionsFlags13_0.m
PD=$S/SecProtocolOptionsData13_0.m
PS=$S/SecProtocolOptionsSSLProtocol13_0.m

echo "== the Security host cases, from $(git -C "$work" rev-parse --short HEAD 2>/dev/null || echo '?') =="
# The two verdicts a driver must keep apart, checked first so a driver that has conflated them says so
# before it goes on to report anything else.
# Security.framework IS LINKED, and without it the control is WORTHLESS: the first build did not link it,
# so SSLGetProtocolVersionMin did not resolve either and the real symbol and SSLNoSuchFunctionForControl
# both read missing 1 - indistinguishable, which is the exact failure the counter is meant to catch.
if xcrun clang -Wall -o "$build/crash-case" "$H/crash-case.c"      -framework Security -framework Foundation > "$build/crash-case.log" 2>&1; then
    # set -e EXITS ON A FAILING SIMPLE COMMAND, so "cmd; status=$?" never reaches the assignment: the
    # script died on the segfault before it could record the exit code it was trying to record, which is
    # the same class of bug as the one this commit fixes. `cmd || status=$?` is the form that survives.
    clean=0; missing=0; crashed=0
    "$build/crash-case" clean   >/dev/null 2>&1 || clean=$?
    "$build/crash-case" missing >/dev/null 2>&1 || missing=$?
    "$build/crash-case" crash   >/dev/null 2>&1 2>/dev/null || crashed=$?
    if [ "$clean" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$crashed" -ge 128 ]; then
        echo "GREEN  verdicts     the three shapes behave: clean $clean, missing $missing, crash $crashed - AND crash $crashed IS THE EXPECTED SHAPE, deliberately provoked by crash-case, and NOT a failure of this run"
        # THE missing COUNTER, resolved through dlsym so it can actually become 1, and the CONTROL: the
        # same resolution pointed at a symbol that does not exist. A counter that reads 0 because nothing
        # can increment it is not a check.
        "$build/crash-case" SSLGetProtocolVersionMin resolve > "$build/present.txt" 2>&1 || true
        "$build/crash-case" SSLNoSuchFunctionForControl resolve > "$build/absent.txt" 2>&1 || true
        present=$(sed -n 's/.*\t\([01]\)$/\1/p' "$build/present.txt" | head -1)
        absent=$(sed -n 's/.*\t\([01]\)$/\1/p' "$build/absent.txt" | head -1)
        if [ "$present" = "0" ] && [ "$absent" = "1" ]; then
            echo "GREEN  missing     a real symbol resolves (missing 0) and SSLNoSuchFunctionForControl does not (missing 1), so the counter CAN fail"
        else
            echo "RED    missing     present=$present absent=$absent - the counter cannot tell the two apart"
            failures=$((failures + 1))
        fi
        # THE CONTROL: the same check against a shape it must REJECT. A verdict check that cannot fail
        # proves nothing, so the driver demands the wrong expectation be reported - and if this ever goes
        # green, the verdict logic has stopped being able to tell a crash from a difference.
        selfclean=0; selfcrashed=0
        "$build/crash-case" clean >/dev/null 2>/dev/null 2>/dev/null || selfclean=$?
        "$build/crash-case" crash >/dev/null 2>/dev/null 2>/dev/null || selfcrashed=$?
        if [ "$selfclean" -eq 0 ] && [ "$selfcrashed" -ge 128 ]; then
            echo "GREEN  control      a WRONG expectation (crash must be 0) is rejected: clean $selfclean, crash $selfcrashed, so this verdict logic CAN fail"
        else
            echo "RED    control      a wrong expectation was NOT rejected: clean $selfclean, crash $selfcrashed"
            failures=$((failures + 1))
        fi
    else
        echo "RED    verdicts     clean $clean, missing $missing, crash $crashed - one shape is wrong"
        failures=$((failures + 1))
    fi
else
    echo "BUILD  crash-case FAILED to build"
    failures=$((failures + 1))
fi
# --- the ten sec_protocol_* cases, each with the port source it links and its own comparator ---
protocol_case() {
    name=$1; sources=$2
    run_case "$name" "compare-$name.py" "$H/$name.m" $sources
    cases=$((cases + 1))
}
protocol_case protocol-metadata            $PM
protocol_case protocol-metadata-accessors   $PM $PMA
protocol_case protocol-options             $PO
protocol_case protocol-options-held       $PO
protocol_case protocol-options-sslprotocol $PS
protocol_case protocol-options-ciphersuite $PC
protocol_case protocol-options-strings    $PR
protocol_case protocol-options-flags      $PF
protocol_case protocol-options-data       $PD
protocol_case protocol-options-blocks     $PK
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
mutate "$O" "$build/mutant-sec-object-otherref.m" \
'    SecCertificateRef held = [(CharonSecCertificate *)certificate charonCertificate];' \
'    SecCertificateRef held = [(CharonSecCertificate *)certificate charonCertificate];
    // MUTANT: answer a NEW ref over the same DER. CFEqual says it is the same certificate and the
    // pointer says it is not, so ONLY the identity check can tell it apart from the caller\x27s
    return held ? (SecCertificateRef)SecCertificateCreateWithData(NULL, SecCertificateCopyData(held)) : NULL;' \
'copy_ref answers a NEW ref over the same DER'
mutate "$O" "$build/mutant-sec-object-noretain.m" \
'        _certificate = certificate ? (SecCertificateRef)CFRetain(certificate) : NULL;' \
'        _certificate = certificate;   // MUTANT: the retain is DROPPED, so the object holds a
        // reference it does not own and gives someone else\x27s away' \
'the creator does not retain, so the object holds a reference it does not own'
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
must_not_compile() {
    name=$1; sources=$2
    mutants=$((mutants + 1))
    if xcrun clang $common "$H/$3.m" "$build/mutant-$name.m" $sources \
         -framework Foundation -framework Security -framework CoreFoundation \
         -o "$build/mustfail-$name" > "$build/mustfail-$name.log" 2>&1; then
        echo "NOTICED  $name mutation  it BUILT, and the type system was supposed to refuse it"
        failures=$((failures + 1))
    else
        echo "NOTICED  $name mutation  refused by the compiler, as it must: $(grep -m1 'error:' "$build/mustfail-$name.log" | cut -c9-)"
        mutants_noticed=$((mutants_noticed + 1))
    fi
}

python3 "$H/make-mutants.py" "$build" 2>/dev/null || true
must_not_compile blocks-challenge-into-keyupdate "$PK" protocol-options-blocks
run_mutation sec-object-otherref compare-sec-object-wrappers.py sec-object-wrappers
run_mutation sec-object-noretain compare-sec-object-wrappers.py sec-object-wrappers
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

# A MUTATION THAT MUST NOT COMPILE is a mutation the type system caught, and it is noticed - so it is
# expected to FAIL TO BUILD rather than to fail a comparison. The challenge-into-key-update mutation
# assigns one block typedef to another's slot, which is a conflicting-type error, and a driver that only
# knows "it built, so run it" would report the build failure as a case that did not run.

echo
if [ "$failures" -eq 0 ]; then
    echo "run-cases: OK - $cases cases, $mutants mutants, $mutants_noticed noticed"
else
    echo "run-cases: $failures failure(s) - $cases cases, $mutants mutants, $mutants_noticed noticed"
fi
exit "$failures"
