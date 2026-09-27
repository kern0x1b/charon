# HealthKit of iOS 8.0, on a release that has none of it

`libHealthKitBackports.dylib`, built with the `healthkit` config, carries the iOS 8.0 surface of
HealthKit: 30 classes, 183 of their members and 110 of the constants that release exported, in
`registry/HealthKit/ios8.json`. This file is what the work was read out of, what the store is, and
where the two seams are.

## What was measured, and from what

**The framework is absent from the port's releases.** Neither the armv7 shared cache of iOS 6.1.3 nor
the one of iOS 4.3 holds a HealthKit image, and neither exports a name of it. The probe: no string of
either cache is `HealthKit`, with `NSObject` (2169 strings) and `PassKit` (14) as the controls that
say the probe finds what is there, and `HealthKit` appearing 33 times in the armv7 cache of iOS 8.0
as the release that first has it. So nothing here is a release's own and every row is the port's.

**The constants are the release's own values, not assumed.** The HealthKit image of the armv7 shared
cache of iOS 8.0 was extracted with `modules/apple/dyld.lua`'s `extract()` and each exported
constant followed through its entry in that image's symbol table to the `__cfstring` it points at.
110 of the 120 names the image exports are declared by the SDK headers, and those 110 are what
`HKConstants8.m` carries; the other ten are Apple's private entitlement names. The reader is
`tools/cfconst/cache32.py`, in the repository, and the 64-bit reader for a shared cache is
`tools/cfconst.py`.
Two controls: `HKQuantityTypeIdentifierStepCount` and `HKErrorDomain` are read out as real strings,
and a name no image exports reports that instead of a value.

**The unit arithmetic is the host's, measured.** `tests/backports/host/healthkit/` asks the
system's own HealthKit and this library the same questions in one process: every unit string, the
factor of every one of them against the base of its dimension, both directions of every conversion at
eight values, the compatibility of every pair, the four arithmetic operations, every prefixed factory at
every prefix of the header's enum, every plain factory, and every one of the 120 quantity types with
its aggregation. **5554 comparisons, 0 differences**, and three mutants of the port are run through it
and none survives, so a pass is a pass.

It is what corrected the units, and every correction is in `HKUnit.m` with the measurement beside it:

- the **micro prefix is `mc`**, and neither `u` nor U+03BC is one - the host raises "Unable to parse
  factorization string" for `ug` and for `μg` alike, and `+gramUnitWithMetricPrefix:HKMetricPrefixMicro`
  answers `mcg`. A prefix goes in front of the base unit's own name, so a milli-pascal is `mPa` and a
  mega-litre is `ML`. The earlier reading inferred an ASCII `u` from the absence of U+03BC in an iOS 8.0
  image, which was an argument from silence and was wrong: that image never held a micro-prefixed unit
  string at all.
- **`%` is not a dimension of its own**: the host converts a percent into a count, so `count` is the
  base of both. `IU`, `appleEffortScore`, `dBASPL`, `Hz`, `dBHL`, `V` and `W` each are one.
- a **molar unit** is a mole with the molar mass as its factor: `mol<12>` is 12 g a mole, `mmol<12>` is
  0.012 g, and the two are compatible - the host answers six for one `mol<12>` in `mol<2>`.
- the three pressure factors are the host's own to the last bit: the millimetre of mercury as
  133.32236842105263 Pa, the centimetre of water as 98.06649606299213 Pa, the inch of mercury as
  3386.38816 Pa. The exact 1/760 atm and the exact 1/760 inHg, which the first table carried, are not
  what the host uses.
- a **product** is written with U+00B7 between its factors, a power with `^` and a quotient with one
  solidus and no parentheses; a `*` reads as the same separator and two soliduses are refused.
- a **string it cannot parse raises** rather than answering nil, which is what its nonnull return and
  its own message say; the empty string is the null unit rather than a refusal.
- a **temperature is not refused** in the arithmetic: the host makes `degC·m`, `1/degC` and `degC^2`,
  and `(degC·m)/degC` comes back as `m`, so a product carries no offset and two temperatures cancel.
- an **offset is not part of compatibility**: a degree Celsius and a kelvin are one dimension.
- `HKQuantityTypeIdentifierUVExposure` is the only line of the SDK header whose unit field is empty,
  and the host answers `count` and `%` for it, so its row carries `count` and the generator that writes
  the table says why.

**Two differences the host differential declares**, both in `run.sh` with the reason.

1. `HKQuantityAggregationStyle` has **two** cases in the header this library is compiled against -
   cumulative and discrete arithmetic - and the header whose comment the type table is read from names
   five. The host answers the three later ones with a case of its own, so for ten types its
   `aggregationStyle` is a number a caller of this library has no case for. They are
   `AtrialFibrillationBurden`, `CyclingCadence`, `CyclingPower`, `CyclingSpeed`, `HeartRate`,
   `RestingHeartRate` and `WalkingHeartRateAverage` (the host says 2), and `EnvironmentalAudioExposure`,
   `EnvironmentalSoundReduction` and `HeadphoneAudioExposure` (the host says 3). This library answers
   the one discrete style it has; the type, its unit and its factor are the same, and the
   cumulative-or-discrete property - the one the contract has - is compared for every type.
2. The **order of the factors of a product**. The host writes a product in an order of its own - it
   answers `J/m·s·kg` for `J/(m*kg*s)`, for `J/(s*kg*m)` and for `J/(m*s*kg)` alike - and the public
   API does not say what that order is. This library writes the factors in the order they were given.
   The test compares the factors as a set, and everything else about a product: which units it accepts,
   and the number it converts to and from.


**The unit strings are the release's too.** The image's own string pool holds the units it stored
per type, beside the type names: `count`, `%`, `m`, `kg`, `count/s`, `kcal`, `mg/dL`, `mmHg`, `g`,
`S`, `degC`, `L/min`. `mg/dL` is the direct evidence that a metric prefix is spelled in ASCII
(`m`, `g`) and not with U+03BC: the image holds no U+03BC at all. The table of units in `HKUnit.m` is
built from those names and the international factors behind them - the inch as 0.0254 m, the foot as
0.3048 m, the mile as 1609.344 m, the avoirdupois pound as 453.59237 g, the stone as 6350.29318 g,
the US fluid ounce as 0.0295735295625 L and the imperial one as 0.0284130625 L, the millimetre of
mercury as 133.322387415 Pa, the centimetre of water as 98.0665 Pa, the standard atmosphere as
101325 Pa, the thermochemical calorie as 4.184 J and the large one as 4184 J.

**The unit and the aggregation of a quantity type are Apple's own, in the SDK.** Every
`HKQuantityTypeIdentifier` line of `HKTypeIdentifiers.h` carries a trailing comment naming both, as
`// kg, Discrete (Arithmetic)` and `// kcal, Cumulative`. `HKQuantityTypes.m` is that comment read for
all 120 identifiers of the header of the SDK 26.2 this repository's corpus was built from, and
nothing is in it that the header does not say. A type counted in a string no unit can be made of
(`appleEffortScore` for `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore`, and the empty string
for `HKQuantityTypeIdentifierAppleSleepingWristTemperature`) keeps the string, accepts no unit, and
says so once in the log, rather than answering a unit no source names for it.

**Which methods are API and which are Apple's own internals** came from the corpus, not from the
image. The iOS 8.0 image of HealthKit carries `-[HKQuery setClientQueue:]`, `-clientQueue`,
`-hasBeenExecuted`, `-activationUUID` and `-[HKUnit isCompatibleWithUnit:]`, and none of the five is
in any public header: they are Apple's private methods, and this port does not carry them (rule R4).
What a query's handlers are called on is the port's own business, and it is the main queue.

## The store

`CharonHKStore` is a SQLite database under Application Support, reached through the device's own
`/usr/lib/libsqlite3.dylib`. All twenty-six of the SQLite entry points it calls are exported by the
armv7 shared cache of both 4.3 and 6.1.3 - `sqlite3_open`, `sqlite3_open_v2`, `sqlite3_close`,
`sqlite3_exec`, `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`, `sqlite3_reset`,
`sqlite3_bind_text`, `sqlite3_bind_double`, `sqlite3_bind_int64`, `sqlite3_bind_blob`,
`sqlite3_bind_null`, `sqlite3_column_text`, `sqlite3_column_double`, `sqlite3_column_int64`,
`sqlite3_column_blob`, `sqlite3_column_type`, `sqlite3_column_bytes`, `sqlite3_column_count`,
`sqlite3_errmsg`, `sqlite3_last_insert_rowid`, `sqlite3_changes`, `sqlite3_busy_timeout`,
`sqlite3_extended_result_codes` - and `/usr/lib/libsqlite3.dylib` is an image of both caches, so the
linker's load command resolves there.

A row holds the object itself, archived by its own `NSSecureCoding`, beside the few facts SQLite has
to narrow by: the type, the dates, the source and a sequence number that is the store's own clock.
Nothing an application writes reaches SQLite as SQL - every statement is one fixed string with
positional bindings - and the predicate a query carries is decided by the release's own
`NSPredicate`, over the objects read back, after SQLite has narrowed by type and by date. A sample's
correlation is filled in from the table that records the relationship, so a predicate built with
`HKPredicateKeyPathCorrelation` walks a real object graph instead of being answered beside it.

The store enforces what the authorization request recorded: a save of a type the process may not
share fails with `HKErrorAuthorizationDenied`, and a query that finds a type it may not read answers
that error and returns nothing.

## The two seams

**The authorization sheet.** It is a SpringBoard surface, and this release has no health application
to put one up. `requestAuthorizationToShareTypes:readTypes:completion:` records what it was asked
for and calls its completion with success; `success` says the request was recorded, not that a user
granted anything, because there was no user to ask. Everything behind the sheet is real and is
enforced, as the paragraph above says.

**Background delivery** is woken by the healthd. Nothing here wakes the process, so a registration
is kept in the store and read back by a later call, and the log says once that nothing is delivered.
A query left running, or an observer query, is how to be told of a change on this release.

A third, smaller one: the user enters their own biological sex, blood type and date of birth in the
Health application, and iOS 8.0's public API of `HKHealthStore` has no way to write them either - the
setters are of iOS 9. The three readers therefore answer `nil`, and the date of birth leaves the
error empty, as the release does for a value it has.

## What is not here, and where it is

The 8.2, 9.0, 9.3, 10.0, 11.0, 11.2, 12.0, 12.2, 13.0, 13.6, 14.0, 14.2, 14.3, 14.5, 15.0, 15.4, 16.0,
16.4, 17.0, 18.0, 18.2, 26.0 and 26.2 rows of the corpus are the later groups, one object per
release each, and none of them is decided here. `HKQueryAnchor` is iOS 9.0 and is therefore a file of
its own. The header-only rows - 458 of the 848 constants, 74 enums, 67 typealiases, 38 structs and 5
protocols - are the lift's: an `NS_ENUM` case, a typedef, a struct and a protocol are the whole
declaration, and no symbol is emitted for any of them, so they are not rows this port carries and
carry no registry entry.

## Sixteen rows of the iOS 8.0 corpus this group does not carry

The corpus dates a row from the SDK header's own annotation, and that annotation is wrong in three
ways. Each of these is registered `absent` with the reason, so a reader of the registry is told the
method is not there rather than finding it in the corpus and wondering:

- **eight `-init` methods** — `-[HKCategorySample init]`, `-[HKObject init]`, `-[HKObjectType init]`,
  `-[HKQuantity init]`, `-[HKSource init]`, `-[HKStatistics init]`, `-[HKStatisticsCollection init]` and
  `-[HKWorkoutEvent init]`. The header marks `-init` unavailable for each of those classes, so a caller
  cannot call it and the release declares none of its own. `-[HKUnit init]` and `-[HKQuery init]` are
  *available* in the header and are carried.
- **the four workout-session methods of `HKHealthStore`** — `startWorkoutSession:`, `endWorkoutSession:`,
  `pauseWorkoutSession:` and `resumeWorkoutSession:`. The header marks them unavailable on iOS: they are
  the watchOS surface of the class, and the watch application and app extensions both arrived after this
  release.
- **the four states-of-mind predicates of `HKQuery`** — `predicateForStatesOfMindWithValence:operatorType:`,
  `predicateForStatesOfMindWithKind:`, `predicateForStatesOfMindWithLabel:` and
  `predicateForStatesOfMindWithAssociation:`. The header leaves them unannotated, so the corpus gave them
  the version of the class they sit in (its `via=class-floor`). They are not 8.0 API: the HealthKit image
  of the armv7 shared cache holds no such selector, and neither do the images of 8.2, 9.0 and 9.3, and
  the type of each argument — `HKStateOfMindAssociation` and its two siblings — is of iOS 18. They were
  carried here for a while and are removed; the group of 18.0 answers them.

The check that finds these, and that a later session should run before each delivery, is
`.agent-work/runs/api-kits/api-check.py`: every registered row against the set of names the gate's own
`backports.surface()` reads out of the built dylib. It reads the *built* library, so it sees what this
port carries; the *release's* image cannot answer it, because `objc.binary_inventory` on an image
extracted from a shared cache reads a class's category method lists and not the class's own, so a
public method of a release looks absent. The SDK header and its availability annotations are the
authority for what a release has; the image is the authority for the values a constant holds.

## The header decides whether a method exists; the image supplies only a value

The SDK headers are the authority on what an API is, and a release image is the authority on the value
a constant holds. `tools/cfconst/declarations.py Class.member…` says what the iOS 26.2 headers declare
and with which `API_AVAILABLE`, and it is what settled every one of these:

| member | the header says |
| --- | --- |
| the eight `-init` of `HKObject`, `HKObjectType`, `HKQuantity`, `HKSource`, `HKStatistics`, `HKStatisticsCollection`, `HKCategorySample`, `HKWorkoutEvent` | `- (instancetype)init NS_UNAVAILABLE;` in each of their headers, so a caller cannot call it and the release declares none of its own |
| `-startWorkoutSession:`, `-endWorkoutSession:`, `-pauseWorkoutSession:`, `-resumeWorkoutSession:` | each carries `API_UNAVAILABLE(ios, …)`; they are the watchOS surface of the class |
| `+predicateForStatesOfMindWithAssociation:` and its three siblings | declared in the 26.2 header inside `@interface HKQuery (HKStateOfMind)`, with **no** `API_AVAILABLE` on the method or the category, so the row took the class's version - the corpus's `via=class-floor`. The type of each argument, `HKStateOfMindAssociation` and its two siblings, is of iOS 18, and the HealthKit image of the armv7 shared cache holds no such selector, in 8.0, 8.2, 9.0 or 9.3. So they are 18.0's, and they are `absent` here with the group that has them named |
| `+workoutWithActivityType:startDate:endDate:duration:totalEnergyBurned:totalDistance:metadata:` | declared, as `@method` and as the definition; the six-argument form beside it is one argument short and **no header declares it**, so it is gone |
| `-[HKStatisticsCollectionQuery initWithQuantityType:quantitySamplePredicate:options:anchorDate:intervalComponents:]` | declared with exactly those five arguments; the seven-argument form with `initialResultsHandler:` is in **no** header and in none of the three images, so it is gone and the handler comes through the `initialResultsHandler` property, which is declared |
| `-[HKStatisticsCollection statistics]`, `-sources` | declared in the 16.4 header inside `@interface HKStatisticsCollection`, and the 8.0 image's list of that class does not hold them: the header is the authority on the method, so both are carried, and the image's disagreement is this row's business |
| `-[HKCategorySample categoryType]` | declared as a property, unannotated, so 8.0's; it was neither carried nor registered and now is both |

Four more the corpus does not list at all, which the headers do declare and this library answers:
`+[HKUnit kilojoulesUnit]`, `+[HKUnit milliseconds]`, `-[HKStatisticsCollection anchorDate]` and
`-[HKStatisticsCollection intervalComponents]`. The corpus attaches the last two to
`HKStatisticsCollectionQuery` by `via=container` and misses the collection's own. They are real 8.0 API
that the port answers, and a row the corpus does not carry needs no registry entry; R4 constrains the
other direction, a registered name no header declares, and none of the 407 is such a name.

## The device run

None yet. Everything above is a read of a release image, a release cache, the SDK headers and the
host's own HealthKit, plus a compile of every file against `armv7-apple-ios6.1.3` and the SDK 16.4 the
gate resolves. What the host cannot be an oracle for is named rather than glossed: the store, the
authorization and the queries, because a host keeps its data in a healthd behind an entitlement and
this port's is a SQLite database of its own, so a differential over the two would compare two different
programs. The behaviour of the store on a device - a sample saved by one launch and read by the next, a
statistic over a set, a predicate that walks a correlation - is **device-unverified**, and the emulator
call test is what this delivery still owes.
