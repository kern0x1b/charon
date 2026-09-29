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
`tools/cfconst/api-check.py`: every registered row against the set of names the gate's own
`backports.surface()` reads out of the built dylib. It reads the *built* library, so it sees what this
port carries; the *release's* image cannot answer it, because `objc.binary_inventory` on an image
extracted from a shared cache reads a class's category method lists and not the class's own, so a
public method of a release looks absent. The SDK header and its availability annotations are the
authority for what a release has; the image is the authority for the values a constant holds.

## The one field this port invents: a device's manufacturer

`+[HKDevice localDevice]` answers the host's own name, model and system version out of the release's own
`UIDevice`, and nil for the four the release has no value for on a host device — the hardware and
firmware revisions and the two identifiers, which are a paired accessory's. The **manufacturer is the
exception and it is this port's own string.** Measured: the HealthKit image of the armv7 shared cache of
iOS 9.0 holds exactly one occurrence of the string `Apple` and no exported symbol reaches it — the only
names in that image with `Apple` in them are `HKCategoryTypeIdentifierAppleStandHour`,
`HKSourceOptionsForAppleDevice` and `HKSourceOptionsForNonAppleDevice` — and the image of iOS 8.0 holds
none at all. HealthKit has no manufacturer constant of its own on any image this workspace holds, so
there is nothing to read. The value is a true statement about the hardware every device this port runs
on is made by, and it is said here, in `HKDevice9.m` beside the code, and in the registry effect for
`+[HKDevice localDevice]`, so that a reader of any of the three does not take it for a measured value.

## The 11.0 group's placement, measured on the images rather than taken from either source

The review asks which of the SDK and the cache each class's release is taken from, and the answer is
per class, measured. What I measured, by extracting the HealthKit image out of each rung of the held
ladder with `modules/apple/dyld.lua`'s `extract()` and reading its own symbol table with `nm`:

| class | the first rung of the held ladder whose image carries it | whose date I follow |
| --- | --- | --- |
| `HKSeriesBuilder`, `HKSeriesSample` | **10.0.1** (and 10.3.4, and 11.0) | the cache: 10.0.1, not the 10.0.1 I had guessed and not 10.3.4 |
| `HKSeriesType`, `HKWorkoutRoute`, `HKWorkoutRouteBuilder`, `HKWorkoutRouteQuery` | **11.0** | the SDK: 11.0, and the cache agrees |
| `HKClinicalRecord`, `HKClinicalType`, `HKFHIRResource` | **12.0** | the SDK: 12.0, and the cache agrees |

So two of the review's four statements are the measurement and two are not, and both halves are
recorded here rather than argued. `HKSeriesBuilder` and `HKSeriesSample` are **of 10.0.1 by the cache and
of no SDK version at all** - the SDK's headers declare them with no `API_AVAILABLE` of their own, so
there is no header date to follow for them and the cache is the only source; they were in the 12.0
group's file and are moved to a group of their own at 10.0.1. The route classes **are** in the 11.0
image - measured, not asserted - so their date of 11.0 is the SDK's and the cache's together. The
clinical record classes are of 12.0 and the cache agrees, and they are carried in the 12.0 group.

What `dyld.first_releases` says over the same ladder is "no rung carries it" for all nine, because it
asks where a *client* binds the symbol and a client of this port binds nothing that is not in the SDK.
The release check reads the same two numbers the gate printed: 10.0.1 for the two superclasses and 11.0
for the route classes, which is the placement this file describes.

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

## The iOS 10.0 and 11.0 groups

`ios100.json` carries 48 rows of iOS 10.0 - `HKDocumentType`, `HKDocumentSample`, `HKCDADocumentSample`,
`HKDocumentQuery`, `HKWheelchairUseObject`, `HKWorkoutConfiguration`, the 12 properties and 10 methods
that came with them, and the 20 exported constants of that release. `ios110.json` carries six rows of
11.0: the CDA document and its five members.

**The CDA document is of 11.0, not 10.0**, and the gate's release check found it: `HKDocument10.m`
held `HKDocumentType`, `HKDocumentSample`, `HKCDADocumentSample`, `HKWheelchairUseObject` and
`HKWorkoutConfiguration` from 10.0 and `HKCDADocument` from 11.0, which one object may not do. The
document is its own file now, in its own group, and the corpus's dating of its five members to 10.0 -
they took the version of the class they sit in - is corrected in the generator, which moves a member to
its class's release.

**The 20 constants of 10.0 came out of the arm64 cache of 10.0.1**, not an armv7 one: there is no
10.0 or 10.0.1 armv7 cache in this workspace, and the armv7s slice's data pointers are tagged, so the
32-bit reader cannot read that slice. **Twelve of the twenty hold a string that is not their own name**,
which is the reason the values are read rather than written: `HKMetadataKeyLapLength` is `HKLapLength`,
`HKMetadataKeyWeatherCondition` is `HKWeatherCondition`, `HKMetadataKeyWeatherHumidity` and
`HKMetadataKeyWeatherTemperature` are `HKWeatherHumidity` and `HKWeatherTemperature`,
`HKMetadataKeySwimmingLocationType` and `HKMetadataKeySwimmingStrokeStyle` are
`HKSwimmingLocationType` and `HKSwimmingStrokeStyle`, `HKPredicateKeyPathCDAAuthorName`,
`HKPredicateKeyPathCDACustodianName` and `HKPredicateKeyPathCDAPatientName` are `author_name`,
`custodian_name` and `patient_name`, `HKPredicateKeyPathCDATitle` is `title`, and
`HKPredicateKeyPathWorkoutTotalSwimmingStrokeCount` and `HKWorkoutSortIdentifierTotalSwimmingStrokeCount` are
both `totalSwimmingStrokeCount`. The other **eight hold their own names**, among them
`HKDocumentTypeIdentifierCDA`, which holds `HKDocumentTypeIdentifierCDA` — the 10.0.1 image, the host's own
HealthKit through `dlsym`, and the line in `HKConstants100.m` agree, and an earlier version of this
paragraph and of that file's own comment claimed otherwise.

**One wall in the 10.0 group**: `-startWatchAppWithWorkoutConfiguration:completion:` starts a workout on
a paired watch, and this release has no watch application and no daemon that would start one. It is
refused with the release's own no-data error, and the log says once why. A success there would be a
success that started nothing.

## The workout builder of 12.0, and what the host can be asked

`HKWorkoutBuilder` is of 12.0, and the arm64 shared cache of 12.0 carries the class with all ten of the
selectors the 26.2 header declares of that release: `initWithHealthStore:configuration:device:`,
`beginCollectionWithStartDate:completion:`, `addSamples:completion:`, `addWorkoutEvents:completion:`,
`addMetadata:completion:`, `endCollectionWithEndDate:completion:`, `finishWorkoutWithCompletion:`,
`discardWorkout`, `elapsedTimeAtDate:` and `statisticsForType:`. The five members of 16.0 -
`workoutActivities`, `allStatistics`, `addWorkoutActivity:completion:` and the two
`updateActivityWithUUID:...` - are @dynamic here, so their selectors are not in the library at all.

The host's HealthKit answers two of the ten with an answer of its own on this machine, and both are in
the differential:

- `-addSamples:` with an empty array is refused with `com.apple.healthkit` code 3, "HKWorkout: HKSample
  data cannot be nil or empty." That code and that wording are the port's as well, read off the host.
- `-elapsedTimeAtDate:` on a builder that has begun no period answers 0.

Everything from `-beginCollectionWithStartDate:` onward the host here will not answer at all: it replies
`com.apple.healthkit` code 1, "Health data is unavailable on this device", to anything that touches
health data, and its `-beginCollectionWithStartDate:completion:` never runs at all, its `startDate`
staying nil. So the period, the samples, the events, the metadata, the statistics, the finish and the
discard are **not compared** against the host, and the differential prints that with the measurement
rather than passing them silently. What is compared for those is the port against the inputs the harness
itself passes - the two dates, and the fact that a second begin is refused and does not move the period
- so that a change to the port's own state machine is still a difference the test notices.

The code of a refusal about the builder's own state is zero, and that is a statement rather than a gap.
No SDK header of 16.4 or 26.2 declares a code for those, and the host could not be asked, so a code
written here would be this library's invention wearing Apple's name. The wording carries the refusal.

`HKWorkoutConfiguration` has no public Objective-C initialiser in the 26.2 header - only a Swift one -
so each side of the differential is built the way its own class can be: the host's through `-init` and
its `assign` property, this port's through the initialiser this library carries.

## The quantity series builder of 12.0, and the host's own four answers

`HKQuantitySeriesSampleBuilder` is of 12.0, and the arm64 shared cache of 12.0 carries the class with
`initWithHealthStore:quantityType:startDate:device:`, `finishSeriesWithMetadata:completion:` and
`discard`, and with the insert spelled `insertQuantity:date:error:`.

**A header and image disagreement, recorded rather than resolved silently.** The 26.2 header gives the
insert as `-insertQuantity:dateInterval:completion:` alongside `-insertQuantity:date:error:`, and
`-insertQuantity:dateInterval:error:` carries `API_AVAILABLE(ios(13.0))` while the `date:error:` form
carries none. The image settles it: the image of 12.0 carries exactly one insert spelling,
`insertQuantity:date:error:`, and by string count it is 1 there while
`insertQuantity:dateInterval:error:` is 0 and `insertQuantity:dateInterval:completion:` is 0. So the
12.0 insert is the `BOOL`-and-`NSError` one, and that is what this library carries. The same disagreement is on the
finish: the header gives `-finishSeriesWithMetadata:completion:` and
`-finishSeriesWithMetadata:endDate:completion:` both at the class's own level, and the image carries only
the first. The form the 12.0 image does not carry is not carried here.

**What the host answers, measured on this machine.** Four of the five selectors, and each answer is the
port's:

| call | the host answers |
|---|---|
| `initWithHealthStore:quantityType:startDate:device:` | a builder; `quantityType` and `startDate` set, `device` nil |
| a quantity of a unit the type does not accept | `NO`, `com.apple.healthkit` 3, "Quantity (5 m) does not have a unit compatible with quantity series builder quantity type HKQuantityTypeIdentifierHeartRate" |
| a date before the builder's start | `NO`, code 3, "Date interval (<_NSConcreteDateInterval: 0x…> (Start Date) … + (Duration) 0.000000 seconds = (End Date) …) is before builder's start date …" |
| an insert after the finish | `NO`, code 3, "Quantity series sample builder already finished" |
| an insert after `-discard` | **raises** `NSGenericException`, "HKQuantitySeriesSampleBuilder already discarded." |

The discarded case is a raise and not a refusal, which is a different kind of answer, and it is why this
port raises there and writes an `NSError` everywhere else. The date refusal embeds the description of
an `NSDateInterval`, which carries a pointer: the whole string cannot be compared twice and so is not
comparable at all. Its stable tail is compared and the host's full text is printed by the differential.

**Not measured: what the finish returns.** The host answers it with samples nil and
`com.apple.healthkit` 1, "Health data is unavailable on this device", so the shape of the series is this
port's own reading of the header - one quantity sample per inserted quantity, from the builder's start
date to the date that quantity was inserted at, in the order it was inserted - and the device test is
what would settle it.

## The cumulative quantity sample of 13.0, and the header/image disagreement about it

`HKCumulativeQuantitySample` is of **13.0**, not of 8.0: the 26.2 header carries
`API_AVAILABLE(ios(13.0), watchos(6.0), macCatalyst(13.0), macos(13.0))` above
`@interface HKCumulativeQuantitySample : HKQuantitySample`, and the header's whole surface is one readonly
`sumQuantity` over the 8.0 base's own type and dates. The host agrees the class is of a later release than
this band has been carrying: it answers NO for `-initWithType:quantity:startDate:endDate:` on the class, so
a cumulative sample is made through the superclass's path with the sum given to this library's own
initialiser.

**The disagreement, measured and recorded rather than resolved silently.** By exact string count, with
`startDate` and `endDate` at 2 in the same image as the control:

| image | `HKCumulativeQuantitySample` | `HKCumulativeQuantitySeriesSample` |
|---|---|---|
| 8.0 armv7 | 0 | - |
| 12.0 arm64 | 0 | 2, and as a real class (`_OBJC_CLASS_$_`, `_OBJC_METACLASS_$_`) |

So at 12.0 the subclass of this class exists and this class's own name is nowhere in the image: it was
either private at 12.0 or unnamed there, and Apple documented it at 13.0. The header decides which group a
member is in, so this class is of 13.0 - in `registry/HealthKit/ios130.json` - and the 12.0 subclass that
needs it is of 12.0.

The store's kind table gained a case for it: kind 5, because it is a quantity sample and not one, and the
table has to read one back as this class rather than as its superclass.

## The cumulative sample of a series, of 12.0, over a superclass of 13.0

`HKCumulativeQuantitySeriesSample` is of 12.0 and its superclass is of 13.0. The 26.2 header declares it
`@interface HKCumulativeQuantitySeriesSample : HKCumulativeQuantitySample` with one readonly
`HKQuantity *sum`, and carries **no availability line of its own** on the class, so the property inherits
the class's.

By substring count with a boundary after the name, in the arm64 image of 12.0 and the armv7 image of 8.0:

| name | 12.0 arm64 | 8.0 armv7 |
|---|---|---|
| `HKCumulativeQuantitySeriesSample` | 7, and as a real class (`_OBJC_CLASS_$_`, `_OBJC_METACLASS_$_`) | 0 |
| `HKCumulativeQuantitySample` (its superclass) | 0 | 0 |
| `sumQuantity` (the control) | 4 | 4 |
| `startDate` (the control) | - | 17 |

So the class is at 12.0 and its superclass's own name is not in that image, which is the same disagreement
recorded for the 13.0 class: at 12.0 the superclass was private or unnamed, and Apple documented it at 13.0.

**What could not be measured, and is not claimed: the `sum` selector.** A packed cache gives 171
whole-token matches for `sum` - it is a prefix of many identifiers and a word in many strings - and no way
to attribute any of them to this class's accessor. The property is carried because the header declares it
and the class is at 12.0; no count backs that one statement, and this is where it is recorded.

The kind table gained case 6, beside case 5 for the superclass: it names a class per kind, and this is not
its superclass.

## What the kind table decides, and what it does not

Since the archive's root is decoded by the unarchiver (`16b1a771b`), the class of an object read out of the
store comes from the archive's own class name, not from the kind the table resolves. The kind still picks
**whose** `+charon_objectFromArchive:type:store:` runs - so a row whose kind names no class cannot be read
at all - but it no longer decides **which** class the object comes back as. A mutant that changes a
stored kind therefore tests nothing here: the cumulative sample's kind was mutated from 5 to 1 and the
round trip did not notice. The mutants for the cumulative classes are on the fact each class adds - the
running total, and the series' own sum - which is what the read has to preserve.

## The device run

None yet. Everything above is a read of a release image, a release cache, the SDK headers and the
host's own HealthKit, plus a compile of every file against `armv7-apple-ios6.1.3` and the SDK 16.4 the
gate resolves. What the host cannot be an oracle for is named rather than glossed: the store, the
authorization and the queries, because a host keeps its data in a healthd behind an entitlement and
this port's is a SQLite database of its own, so a differential over the two would compare two different
programs. The behaviour of the store on a device - a sample saved by one launch and read by the next, a
statistic over a set, a predicate that walks a correlation - is **device-unverified**, and the emulator
call test is what this delivery still owes.
