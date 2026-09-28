#!/bin/sh
# run.sh — holds the port's HealthKit arithmetic against the host's own, in one process.
#
# The port's classes are compiled under names of their own (CharonHostHKUnit and so on) so that the
# system's HealthKit and the port's run side by side and the two can be asked the same question. What
# is compared is the arithmetic a host answers without asking anybody for anything: a unit converts, a
# unit multiplies and divides and is raised to a power, a quantity compares, a quantity type says
# which unit it is counted in and which aggregation it uses. The store, the authorization and the
# queries are not in here — a host keeps its data in a healthd behind an entitlement, and this port's
# is a SQLite database of its own, so neither side is an oracle for the other's.
#
# The port's constants are NOT compiled in: the host's HealthKit exports the same symbols, and the two
# would collide. That is also the better arrangement for this test — the identifiers both sides are
# asked about are the host's own, and the port's table is what is held to them.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
healthkit=${HEALTHKIT:-$here/../../../../packages/a/apple-backports/HealthKit}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-w"
# The whole build directory goes and not only its two object subdirectories. A run that fails to link
# then leaves no differential at all, where before it left the one the previous run built, and the line
# after this one ran that: a stale binary answering for a fixed source. The mutant step below, which
# compiles into the same tree, is cleared the same way for the same reason.
rm -rf "$BUILD"
mkdir -p "$BUILD/plain" "$BUILD/renamed"

# The files that carry the arithmetic, plus the store, which is where two of the port's own functions
# live (the error it answers with and the line it says once in the log) and which is the only file that
# defines them. Nothing in this test opens a database: the store is compiled so that what the unit and
# quantity code calls exists, not so that the store is measured.
sources="HKUnit.m HKQuantity.m HKQuantityType.m HKQuantityTypes.m HKObjectType.m HKObject.m HKSource.m HKSample.m HKWorkout.m HKStatistics.m HKQuery.m HKQueries.m HKQueryAnchor9.m HKSourceRevision9.m HKSamples.m HKWorkoutRoute110.m HKWorkoutRouteQuery110.m HKCDADocument11.m HKClinicalRecord120.m CharonHKStore.m"

for source in $sources; do
    xcrun clang -fobjc-arc $quiet -I"$healthkit" -c "$healthkit/$source" -o "$BUILD/plain/$source.o"
done

# Every class the port's own files carry, renamed; the system's own HealthKit carries the real names.
renames=""
for name in $(xcrun nm -gU "$BUILD"/plain/*.o | awk 'NF == 3 {print $3}' | grep -E '^_OBJC_CLASS_\$_' \
              | sed -e 's/^_OBJC_CLASS_\$_//' | sort -u); do
    renames="$renames -D$name=CharonHost$name"
done
echo "renamed:$renames"

for source in $sources; do
    xcrun clang -fobjc-arc $quiet $renames -I"$healthkit" -c "$healthkit/$source" -o "$BUILD/renamed/$source.o"
done

# Built under a second name and moved into place only once it exists, so the line after this one can
# only ever run the binary this run built.
xcrun clang -fobjc-arc $quiet -I"$healthkit" "$here/differential.m" "$BUILD"/renamed/*.o \
    -framework Foundation -framework HealthKit -lsqlite3 -o "$BUILD/differential.new"
mv "$BUILD/differential.new" "$BUILD/differential"

"$BUILD/differential"

# A difference the two are bound to have, and why. HKQuantityAggregationStyle has two cases in the
# header this library is compiled against - cumulative and discrete arithmetic - and the header whose
# comment the type table is read from names five. The host answers the three later ones with a case of
# its own, so for these ten types the host's aggregationStyle is a number this library's caller has no
# case for, and this library answers the one discrete style it has. The type, its unit and its factor
# are the same on both sides, and the cumulative-or-discrete property - the one the contract has - is
# compared for every type.
#
#   HKQuantityTypeIdentifierAtrialFibrillationBurden          host 2, port 1
#   HKQuantityTypeIdentifierCyclingCadence                   host 2, port 1
#   HKQuantityTypeIdentifierCyclingPower                     host 2, port 1
#   HKQuantityTypeIdentifierCyclingSpeed                     host 2, port 1
#   HKQuantityTypeIdentifierEnvironmentalAudioExposure        host 3, port 1
#   HKQuantityTypeIdentifierEnvironmentalSoundReduction      host 3, port 1
#   HKQuantityTypeIdentifierHeadphoneAudioExposure           host 3, port 1
#   HKQuantityTypeIdentifierHeartRate                        host 2, port 1
#   HKQuantityTypeIdentifierRestingHeartRate                 host 2, port 1
#   HKQuantityTypeIdentifierWalkingHeartRateAverage          host 2, port 1
#
# A second one, and the only other: the order of the factors of a product. The host writes a product in
# an order of its own - it answers J/m·s·kg for J/(m*kg*s), for J/(s*kg*m) and for J/(m*s*kg) alike -
# and the public API does not say what that order is. This library writes the factors in the order they
# were given, which is a different order for some products and the same for the rest. The test compares
# the factors as a set, and everything else about a product: which units it accepts, and the number it
# converts to and from.
#
# A mutant that survives would mean the test cannot see a change it is supposed to see, so three are
# run: a factor wrong in its last place, a unit string wrong by one letter, and the micro prefix spelled
# the way it is commonly spelled and the host refuses.
survived=0
mutant() {
    file=$1; from=$2; to=$3
    # The mutant's tree keeps the library's own layout, so that a source which reaches out of its
    # folder for the shared header still finds it and only the one change is in it.
    rm -rf "$BUILD/mutant"; mkdir -p "$BUILD/mutant/HealthKit"
    # nothing of a previous run's may be here: the binary is only run if this step builds it
    rm -f "$BUILD/mutant/differential"
    cp "$healthkit"/*.m "$healthkit"/*.h "$BUILD/mutant/HealthKit/"
    cp "$here/../../../../packages/a/apple-backports/CharonSayOnce.h" "$BUILD/mutant/"
    python3 "$here/mutate.py" "$BUILD/mutant/HealthKit/$file" "$from" "$to"
    for source in $sources; do
        xcrun clang -fobjc-arc $quiet $renames -I"$BUILD/mutant/HealthKit" -c "$BUILD/mutant/HealthKit/$source" \
            -o "$BUILD/mutant/$source.o" 2>/dev/null || true
    done
    xcrun clang -fobjc-arc $quiet -I"$BUILD/mutant/HealthKit" "$here/differential.m" "$BUILD"/mutant/*.o \
        -framework Foundation -framework HealthKit -lsqlite3 -o "$BUILD/mutant/differential" 2>/dev/null || true
    if [ -x "$BUILD/mutant/differential" ] && "$BUILD/mutant/differential" > /dev/null 2>&1; then
        echo "MUTANT SURVIVED: $file $from -> $to"; survived=$((survived + 1))
    fi
}
mutant HKUnit.m '{@"mmHg", CharonHKDimensionPressure, 133.32236842105263, 0.0},' '{@"mmHg", CharonHKDimensionPressure, 133.322387415, 0.0},'
mutant HKUnit.m 'return @"mc";' 'return @"u";'
mutant HKUnit.m '@"appleEffortScore", CharonHKDimensionEffortScore, 1.0, 0.0},' '@"appleEffortScore2", CharonHKDimensionEffortScore, 1.0, 0.0},'
echo "mutants surviving: $survived"
[ "$survived" -eq 0 ]
