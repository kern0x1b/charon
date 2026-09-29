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
mkdir -p "$build"; rm -f "$build/cases-entered" "$build"/verdict-*
sdk=$(xcrun --show-sdk-path --sdk macosx)
S="$work/packages/a/apple-backports/Security"
H="$here"
# -Werror=implicit-function-declaration, so a call to a name no header declares is a BUILD
# FAILURE and not a silently int-returning call that reads garbage.
common="-target arm64-apple-ios15.0-macabi -Werror=implicit-function-declaration -isysroot $sdk -F $sdk/System/Library/Frameworks"
common="$common -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc"
frameworks="-framework Foundation -framework Security -framework CoreFoundation"
failures=0
green=0
MUTANT_SRC=""
# THE CONTROL IS MARKED, NOT THE CHECK WEAKENED. A mutant named here is EXPECTED to survive its
# comparison; every other one that survives is a failure. The list is not a hole in the check - it is one
# entry, and adding to it would turn the run green in a way nobody can read back.
EXPECTED_UNNOTICED="identity"
cases=0
missing=0
mutants=0
mutants_noticed=0

# run NAME PORT-SOURCES... -- COMPARE-SCRIPT ; a mutation is applied by mutate_NAME below
run_case() {
    # A CASE IS COUNTED ONLY AFTER IT HAS BEEN RUN AND COMPARED. The counter used to sit at the TOP of this
    # function, on the reasoning that a caller incrementing after the call undercounts early returns - and
    # that was true, but it fixed the wrong thing: it counted BUILDS. The driver built 19 binaries, checked
    # that the port's symbols were linked into each, and printed "every case compared" without ever asking
    # what any of them DID. The reviewer's control is what showed it: pointing the driver at a source with
    # its half-pair refusal removed changed nothing it printed, while the same binary compared by hand said
    # DIFFERS. So the increment belongs here, after the verdict, and not anywhere above it.
    name=$1; shift
    compare=$1; shift
    echo "$name" >> "$build/cases-entered"
    : > "$build/verdict-$name"

    if ! xcrun clang $common "$@" $frameworks -o "$build/$name" > "$build/$name.log" 2>&1; then
        echo "NOTRUN $name  the build failed, so the case never ran" > "$build/verdict-$name"; echo "BUILD  $name FAILED to build"
        sed -n '1,5p' "$build/$name.log" | sed 's/^/       /'
        failures=$((failures + 1))
        return
    fi

    # THE GUARD, AND EXACTLY WHAT IT DOES NOT COVER. It matches \bsec_[a-z0-9_]+\( in the CASE and in
    # the port sources, so it covers a case that reaches the port through a sec_* name AND that source
    # being linked. IT DOES NOT COVER: supported, attributes, certificate-name and trust-result, which
    # reach the port through Charon* helpers or through dlsym(RTLD_DEFAULT, ...); and a case that calls no
    # sec_* name at all. A case outside that set is not guarded - it is neither checked nor claimed to be.
    # the sec_*/Charon* symbols this case CALLS BY NAME must be DEFINED in
    # the binary it linked, and the reference set is built from the very "$@" the guard is given, so a
    # source dropped from the link line also leaves the reference set. A case that resolves the port by
    # dlsym(RTLD_DEFAULT, ...) is not caught at all. Both are recorded as OWED in the README beside this
    # script, with the three defects, rather than left for a reader to assume away.
    # A source
    # dropped from the command line cannot hide, because the case still calls it - the name resolves to the
    # host framework, and the case measures the host while looking exactly like a port measurement.
    casefile=""
    for a in "$@"; do
        case "$a" in *.m) casefile="$a"; break;; esac
    done
    if [ -n "$casefile" ]; then
        strip() { sed -e 's://.*::' -e 's:/*[^*]* */::g' "$1"; }
        called=$(strip "$casefile" | grep -oE '\bsec_[a-z0-9_]+[[:space:]]*\(' | sed -E 's/[[:space:]]*\($//' | sort -u)
        for src in "$@"; do
            [ -f "$src" ] || continue
            strip "$src" | grep -E '\bsec_[a-z0-9_]+\(' | sed -nE 's/.*[^A-Za-z0-9_](sec_[a-z0-9_]+)\(.*/\1/p'
        done | sort -u > "$build/port-defines.txt"
        # nm's OWN STATUS, CAPTURED WITHOUT set -e KILLING THE SCRIPT FIRST. `nm ... > file` followed by
        # `nmstatus=$?` on the next line NEVER REACHES THE ASSIGNMENT under set -e: the script ends on the
        # failing command, so the branch below was unreachable and the guard died SILENTLY on an nm failure
        # instead of reporting one. The `|| status=$?` form is the one that survives, and the same slip was
        # made in run_mutation and fixed there - twice - before it was fixed here.
        nmstatus=0
        nm -gU "$build/$name" > "$build/$name.nm" 2>/dev/null || nmstatus=$?
        if [ "$nmstatus" -ne 0 ]; then
            echo "NOTRUN $name  nm -gU failed, so the case was never compared" > "$build/verdict-$name"; echo "BUILD  $name FAILED: nm -gU on the linked binary exited $nmstatus"
            failures=$((failures + 1))
            return
        fi
        for sym in $called; do
            grep -qx "$sym" "$build/port-defines.txt" || continue
            if [ "$(awk -v s="_$sym" '$NF==s' "$build/$name.nm" | wc -l)" -lt 1 ]; then
                echo "NOTRUN $name  a port symbol came from a dylib, so the case was never compared" > "$build/verdict-$name"; echo "MISSING $name $sym would measure the HOST: _$sym is not defined in the binary this case linked"
                failures=$((failures + 1))
                return
            fi
        done
    fi

    # RUN IT, COMPARE IT, SAY WHAT HAPPENED.
    status=0
    ( cd "$work" && "$build/$name" ) > "$build/$name.out" 2>&1 || status=$?
    cases=$((cases + 1))
    if [ "$status" -ge 128 ]; then
        echo "CRASH $name" > "$build/verdict-$name"; echo "CRASH  $name  crashed: signal $((status - 128)) (exit $status), not a comparison"
        sed 's/^/       /' "$build/$name.out" | tail -3
        failures=$((failures + 1))
        return
    fi
    if python3 "$H/$compare" "$build/$name.out" > "$build/$name.verdict" 2>&1; then
        green=$((green + 1))
        echo "GREEN $name" > "$build/verdict-$name"; echo "GREEN  $name  $(tail -1 "$build/$name.verdict")"
    else
        echo "RED $name" > "$build/verdict-$name"; echo "RED    $name  $(tail -1 "$build/$name.verdict")"
        sed 's/^/       /' "$build/$name.verdict" | head -4
        failures=$((failures + 1))
    fi
}

run_mutation() {
    # Same rule: counted where it runs, BEFORE the early return a crashing mutant takes. It was counted
    # after, so a mutation that segfaulted - the most emphatic "noticed" there is - was not counted at all.
    mutants=$((mutants + 1))
    name=$1; compare=$2; casefile=${3:-$name}
    if [ ! -f "$build/mutant-$name.m" ]; then
        echo "RED    $name mutation NOT BUILT - nothing proved the case can fail"
        failures=$((failures + 1))
        MUTANT_SRC=""
# comparison; every other one that survives is a failure. The list is not a hole in the check - it is one
# entry, and adding to it would turn the run green in a way nobody can read back.
        return
    fi
    if [ ! -f "$build/mutant-$name.m" ]; then
        echo "RED    $name mutation NOT BUILT - nothing proved the case can fail"
        failures=$((failures + 1)); return
    fi
    if ! xcrun clang $common "$H/$casefile.m" "$build/mutant-$name.m" ${MUTANT_SRC:+"$MUTANT_SRC"} \
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
        mutants_noticed=$((mutants_noticed + 1))
        MUTANT_SRC=""
# comparison; every other one that survives is a failure. The list is not a hole in the check - it is one
# entry, and adding to it would turn the run green in a way nobody can read back.
        return
    fi
    if python3 "$H/$compare" "$build/mutant-$name.out" > "$build/mutant-$name.red" 2>&1; then
        if [ "$name" = "$EXPECTED_UNNOTICED" ]; then
            echo "EXPECTED  $name mutation  NOT noticed, and that is REQUIRED: it is a byte-identical copy, so
        the comparison passing is the whole point - and it is what proves the noticed count can go LOWER"
        else
            echo "RED    $name MUTATION WENT UNNOTICED - the comparison cannot tell this case from a broken one"
            failures=$((failures + 1))
        fi
        MUTANT_SRC=""
# comparison; every other one that survives is a failure. The list is not a hole in the check - it is one
# entry, and adding to it would turn the run green in a way nobody can read back.
    else
        echo "RED    $name mutation  $(grep -m1 DIFFERS "$build/mutant-$name.red" | cut -c9-)"
        mutants_noticed=$((mutants_noticed + 1))
        MUTANT_SRC=""
# comparison; every other one that survives is a failure. The list is not a hole in the check - it is one
# entry, and adding to it would turn the run green in a way nobody can read back.
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
    # THE SOURCES ARE "$*" AND NOT "$2". A case that needs SEVERAL port objects passed them as
    # separate arguments, and a function that read only $2 DROPPED THE REST ON THE FLOOR: the build
    # succeeded, the missing names resolved to the HOST, and the case measured the host while looking
    # exactly like a port measurement. It failed on four rows and the driver could not say why.
    name=$1; shift
    run_case "$name" "compare-$name.py" "$H/$name.m" "$@"
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
    # IT IS A MUTATION AND IT COUNTS AS ONE. It incremented `noticed` without incrementing `mutants`,
    # so the run reported 11 noticed against 10 mutations: a compiler-refused mutation was being counted
    # as evidence without being counted as an attempt, which is the one thing a coverage summary must not
    # do. The increment belongs at the top, like the other two runners.
    mutants=$((mutants + 1))
    name=$1; sources=$2
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

# make-mutants.py IS NOT OPTIONAL AND ITS FAILURE IS NOT SWALLOWED. It ran under
# `2>/dev/null || true`, so a wrong anchor, a missing file or a write error was invisible here and the
# driver went on to report a mutant as "refused by the compiler" - which reads as a PASS. A script that
# writes the evidence a later verdict depends on must fail the run, and its output is kept.
if ! python3 "$H/make-mutants.py" "$build" > "$build/make-mutants.log" 2>&1; then
    echo "BUILD  make-mutants.py FAILED (exit non-zero) - the mutants this run will judge were not written"
    sed 's/^/       /' "$build/make-mutants.log" | tail -3
    failures=$((failures + 1))
    mutants=0
    mutants_noticed=0
else
    for want in mutant-blocks-challenge-into-keyupdate.m mutant-data-halfpair.m mutant-held-nocopy.m \
                mutant-identity.m; do
        if [ ! -f "$build/$want" ]; then
            echo "BUILD  make-mutants.py reported success but $want is ABSENT - the evidence is not there"
            failures=$((failures + 1))
        fi
    done
fi
run_case sec-object-wrappers compare-sec-object-wrappers.py $H/sec-object-wrappers.m $O
run_mutation sec-object-otherref compare-sec-object-wrappers.py sec-object-wrappers
run_mutation sec-object-noretain compare-sec-object-wrappers.py sec-object-wrappers
# THE BLOCKS MUTATION MUST NOT COMPILE, and its call was LOST in the F3 revert - only the function
# definition survived, so a run quietly stopped proving that. It is restored here beside the other two.
must_not_compile blocks-challenge-into-keyupdate "$PK" protocol-options-blocks
# data-halfpair IS SecProtocolOptionsData13_0.m, so it REPLACES the case's source and is not added beside
# it - passing it again as an extra source is a duplicate symbol, which is what it did first.
run_mutation data-halfpair compare-protocol-options-data.py protocol-options-data
# held-nocopy mutates the IVAR in SecProtocolOptions13_0.m, which IS the case's own source, so it
# REPLACES it and is not added beside it - adding it is a duplicate symbol, which is what it did first.
run_mutation held-nocopy   compare-protocol-options-held.py  protocol-options-held
run_mutation identity       compare-protocol-options-held.py  protocol-options-held
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

# THE SUMMARY MUST AGREE WITH ITS OWN LINES. A run whose GREEN count differs from the case count has
# described a set it did not measure, which is the defect class this whole hunt is for: the tail looked
# fine while run_case built binaries and never compared them.
# EVERY CASE GETS EXACTLY ONE VERDICT LINE. Any case that entered and has no verdict is named NOT-RUN,
# so a missing line is impossible rather than something a reader has to infer from a count.
for c in $(cat "$build/cases-entered" 2>/dev/null); do
    if [ ! -s "$build/verdict-$c" ]; then
        echo "NOTRUN  $c  entered the driver and printed no verdict at all"
        failures=$((failures + 1))
    fi
done
echo
if [ "$green" -ne "$cases" ]; then
    echo "run-cases: $green GREEN verdict lines for $cases cases - the summary does not match the lines it printed"
    exit 1
fi
if [ "$failures" -eq 0 ]; then
    echo "run-cases: OK - $cases cases, $mutants mutants, $mutants_noticed noticed"
else
    echo "run-cases: $failures failure(s) - $cases cases, $mutants mutants, $mutants_noticed noticed"
fi
exit "$failures"
