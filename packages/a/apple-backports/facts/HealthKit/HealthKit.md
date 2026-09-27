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
`.agent-work/runs/api-kits/cfconst32.py` and its output `.agent-work/runs/api-kits/hk8.0.constvalues`.
Two controls: `HKQuantityTypeIdentifierStepCount` and `HKErrorDomain` are read out as real strings,
and a name no image exports reports that instead of a value.

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

## The device run

None yet. Everything above is a read of a release image, a release cache, the SDK headers and the
host's own HealthKit, plus a compile of every file against `armv7-apple-ios6.1.3` and the SDK 16.4 the
gate resolves. What the host cannot be an oracle for is named rather than glossed: the store, the
authorization and the queries, because a host keeps its data in a healthd behind an entitlement and
this port's is a SQLite database of its own, so a differential over the two would compare two different
programs. The behaviour of the store on a device - a sample saved by one launch and read by the next, a
statistic over a set, a predicate that walks a correlation - is **device-unverified**, and the emulator
call test is what this delivery still owes.
