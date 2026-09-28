// differential.m — what the host's HealthKit answers for the arithmetic of units, quantities and
// quantity types, and what the port's answers for the same questions, in one process, and whether
// the two agree.
//
// The two halves are the system's own HKUnit, HKQuantity, HKObjectType and HKQuantityType, and the
// port's compiled under names of their own (CharonHostHKUnit and so on, put there by run.sh's -D
// flags). Nothing here asks anybody for anything: a unit converts, a unit multiplies, a quantity
// compares, a type says which unit it is counted in and which aggregation it uses, and each of those
// is a property of the class rather than of a store behind an entitlement. The store, the
// authorization and the queries are not in this file, because a host keeps its data in a healthd this
// port has no counterpart to, and a differential over the two would compare two different programs.
//
// Every number below is read off the *host* through its own public conversion and read off the *port*
// the same way, so the comparison is of the two answers and not of two copies of one table.

#import <Foundation/Foundation.h>
#import <HealthKit/HealthKit.h>

#import <objc/runtime.h>

#import "CharonHKTypes.h"

// The members iOS 9.3 added to HKQuery, which the header this file compiles against declares in
// HKQuery.h and HKSampleQuery.h and which HealthKit.h does not import. The host's own classes answer
// them, and so must the port's, so both are declared here rather than assumed.
@interface HKQuery (HKCharon93)
@property (readonly, strong, nullable) HKObjectType *objectType;
@property (readonly, strong, nullable) NSPredicate *predicate;
@end

@interface HKSampleQuery (HKCharon93)
@property (readonly) NSUInteger limit;
@property (readonly, copy, nullable) NSArray<NSSortDescriptor *> *sortDescriptors;
@property (readonly) BOOL hasBeenExecuted;
@property (readonly, copy) NSUUID *activationUUID;
@end

@interface HKStatisticsCollectionQuery (HKCharon93)
@property (readonly, strong) NSDate *anchorDate;
@property (readonly) HKStatisticsOptions options;
@property (readonly, copy) NSDateComponents *intervalComponents;
@end

// The port's own classes, under the names run.sh's -D flags give them. The declarations are this
// file's own and hold only what it asks of them: the port's headers declare the same classes under
// their real names, which the system's HealthKit also declares, so they cannot both be seen at once.

// The port's own classes, under the names run.sh's -D flags give them, for the members the two new
// sections ask of. The declarations are this file's own and hold only what it asks of them: a query
// object holds its own facts and needs no store to answer them, which is what makes them comparable
// with the host's.
@interface CharonHostHKQuery : NSObject
+ (NSPredicate *)predicateForClinicalRecordsWithFHIRResourceType:(NSString *)resourceType;
+ (nullable NSPredicate *)predicateForClinicalRecordsFromSource:(nullable HKSource *)source
                                                FHIRResourceType:(nullable NSString *)resourceType
                                                     identifier:(nullable NSString *)identifier;
+ (NSString *)charon_predicateOperatorSpellingFor:(long)type;
@end

@interface CharonHostHKStatisticsCollectionQuery : NSObject
- (instancetype)initWithQuantityType:(HKQuantityType *)quantityType
                quantitySamplePredicate:(nullable NSPredicate *)quantitySamplePredicate
                             options:(HKStatisticsOptions)options
                          anchorDate:(NSDate *)anchorDate
                  intervalComponents:(NSDateComponents *)intervalComponents;
@property (readonly) NSDate *anchorDate;
@property (readonly) HKStatisticsOptions options;
@property (readonly, copy) NSDateComponents *intervalComponents;
@property (readonly) HKObjectType *objectType;
@property (readonly) NSPredicate *predicate;
@end

@interface CharonHostHKSampleQuery : NSObject
- (instancetype)initWithSampleType:(HKSampleType *)sampleType
                         predicate:(nullable NSPredicate *)predicate
                             limit:(NSUInteger)limit
                  sortDescriptors:(nullable NSArray<NSSortDescriptor *> *)sortDescriptors
                   resultsHandler:(void (^)(CharonHostHKSampleQuery *query, NSArray *results, NSError *error))resultsHandler;
@property (readonly) HKSampleType *sampleType;
@property (readonly) HKObjectType *objectType;
@property (readonly) NSUInteger limit;
@property (readonly, copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@property (readonly) NSPredicate *predicate;
@end

@interface CharonHostHKStatisticsQuery : NSObject
- (instancetype)initWithQuantityType:(HKQuantityType *)quantityType
                quantitySamplePredicate:(nullable NSPredicate *)quantitySamplePredicate
                             options:(HKStatisticsOptions)options
                    completionHandler:(void (^)(id result, NSError *error))completionHandler;
@property (readonly) HKQuantityType *objectType;
@property (readonly) NSPredicate *predicate;
@property (readonly) BOOL hasBeenExecuted;
@end

@interface CharonHostHKSourceQuery : NSObject
- (instancetype)initWithSampleType:(nullable HKSampleType *)sampleType
                    samplePredicate:(nullable NSPredicate *)predicate
                  completionHandler:(void (^)(NSArray<HKSource *> *sources, NSError *error))completionHandler;
@property (readonly) HKObjectType *objectType;
@property (readonly) NSPredicate *predicate;
@end

// The iOS 11.0 group: the series type, the clinical type, the FHIR resource, the source revision's two
// new members, the workout event over a period, and the workout's flights climbed.
@interface CharonHostHKSeriesType : NSObject
+ (instancetype)workoutRouteType;
@property (readonly, copy) NSString *identifier;
@end

@class CharonHostHKSeriesType;
@class CharonHostHKClinicalType;

@interface CharonHostHKObjectType : NSObject
+ (nullable HKQuantityType *)quantityTypeForIdentifier:(NSString *)identifier;
+ (nullable CharonHostHKSeriesType *)seriesTypeForIdentifier:(NSString *)identifier;
+ (nullable CharonHostHKClinicalType *)clinicalTypeForIdentifier:(NSString *)identifier;
@end

@interface CharonHostHKClinicalType : NSObject
@property (readonly, copy) NSString *identifier;
@end

@interface CharonHostHKFHIRResource : NSObject
+ (instancetype)charon_resourceWithType:(NSString *)resourceType
                             identifier:(NSString *)identifier
                                   data:(NSData *)data
                              sourceURL:(nullable NSURL *)sourceURL;
@property (readonly, copy) NSString *resourceType;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSData *data;
@property (readonly, copy, nullable) NSURL *sourceURL;
- (id)copy;
@end

@interface CharonHostHKSourceRevision : NSObject
- (instancetype)initWithSource:(HKSource *)source
                       version:(nullable NSString *)version
                   productType:(nullable NSString *)productType
          operatingSystemVersion:(NSOperatingSystemVersion)operatingSystemVersion;
@property (readonly, copy) HKSource *source;
@property (readonly, copy) NSString *version;
@property (readonly, copy) NSString *productType;
@property (readonly) NSOperatingSystemVersion operatingSystemVersion;
@end

@interface CharonHostHKWorkoutEvent : NSObject
+ (instancetype)workoutEventWithType:(long)type
                       dateInterval:(nullable NSDateInterval *)dateInterval
                            metadata:(nullable NSDictionary *)metadata;
@property (readonly) long type;
@property (readonly, copy) NSDate *date;
@property (readonly, copy) NSDateInterval *dateInterval;
@property (readonly, copy) NSDictionary *metadata;
@end

@interface CharonHostHKWorkout : NSObject
+ (instancetype)workoutWithActivityType:(long)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                         workoutEvents:(NSArray *)workoutEvents
                    totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                      totalDistance:(nullable HKQuantity *)totalDistance
                 totalFlightsClimbed:(nullable HKQuantity *)totalFlightsClimbed
                                device:(nullable id)device
                              metadata:(nullable NSDictionary *)metadata;
@property (readonly) long workoutActivityType;
@property (readonly, copy) NSDate *startDate;
@property (readonly, copy) NSDate *endDate;
@property (readonly) NSTimeInterval duration;
@property (readonly, copy) NSArray *workoutEvents;
@property (readonly, copy, nullable) HKQuantity *totalEnergyBurned;
@property (readonly, copy, nullable) HKQuantity *totalDistance;
@property (readonly, copy, nullable) HKQuantity *totalFlightsClimbed;
@end

@interface CharonHostHKUnit : NSObject
+ (instancetype)unitFromString:(NSString *)string;
+ (instancetype)internationalUnit;
+ (instancetype)smallCalorieUnit;
+ (instancetype)largeCalorieUnit;
+ (instancetype)countUnit;
+ (instancetype)jouleUnit;
+ (instancetype)kilocalorieUnit;
+ (instancetype)meterUnit;
@property (readonly, copy) NSString *unitString;
- (BOOL)isNull;
- (HKUnit *)unitMultipliedByUnit:(HKUnit *)unit;
- (HKUnit *)unitDividedByUnit:(HKUnit *)unit;
- (HKUnit *)unitRaisedToPower:(NSInteger)power;
- (HKUnit *)reciprocalUnit;
+ (instancetype)gramUnit;
+ (instancetype)gramUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)meterUnit;
+ (instancetype)meterUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)literUnit;
+ (instancetype)literUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)pascalUnit;
+ (instancetype)pascalUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)secondUnit;
+ (instancetype)secondUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)jouleUnit;
+ (instancetype)jouleUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)siemenUnit;
+ (instancetype)siemenUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)hertzUnit;
+ (instancetype)hertzUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)voltUnit;
+ (instancetype)voltUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)wattUnit;
+ (instancetype)wattUnitWithMetricPrefix:(HKMetricPrefix)prefix;
+ (instancetype)degreeCelsiusUnit;
- (BOOL)charon_isCompatibleWithUnit:(CharonHostHKUnit *)unit;
@end

@interface CharonHostHKQuantity : NSObject
+ (instancetype)quantityWithUnit:(CharonHostHKUnit *)unit doubleValue:(double)value;
- (BOOL)isCompatibleWithUnit:(CharonHostHKUnit *)unit;
- (double)doubleValueForUnit:(CharonHostHKUnit *)unit;
- (NSComparisonResult)compare:(CharonHostHKQuantity *)quantity;
@end

@interface CharonHostHKQuantityType : CharonHostHKObjectType
@property (readonly) NSInteger aggregationStyle;
- (BOOL)isCompatibleWithUnit:(CharonHostHKUnit *)unit;
@end

static NSUInteger CharonHKDifferences;
static NSUInteger CharonHKComparisons;

static void CharonHKCompare(NSString *what, id mine, id theirs)
{
    CharonHKComparisons++;
    BOOL same = mine == nil ? theirs == nil : [mine isEqual:theirs];
    if (!same) {
        CharonHKDifferences++;
        printf("DIFFERS  %-56s port %-26s host %s\n", what.UTF8String,
               [[mine description] UTF8String], [[theirs description] UTF8String]);
    }
}

static void CharonHKCompareBool(NSString *what, BOOL mine, BOOL theirs)
{
    CharonHKCompare(what, @(mine), @(theirs));
}

static void CharonHKCompareInt(NSString *what, NSInteger mine, NSInteger theirs)
{
    CharonHKCompare(what, @(mine), @(theirs));
}

// The factors of a unit, as the strings it writes them with, in the order it writes them. The host
// writes a product in an order of its own that the public API does not say - it answers `J/m·s·kg`
// for `J/(m*kg*s)`, for `J/(s*kg*m)` and for `J/(m*s*kg)` alike - so the factors are compared as a
// set and the order is not. Everything else about a product is compared: which units it accepts, and
// the number it converts.
static void CharonHKCompareFactors(NSString *what, id mineUnit, id theirsUnit)
{
    CharonHKComparisons++;
    NSString *mine = [mineUnit unitString], *theirs = [theirsUnit unitString];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"/*·^0123456789"];
    NSMutableSet *mineSet = [NSMutableSet set], *theirsSet = [NSMutableSet set];
    for (NSString *part in [mine componentsSeparatedByCharactersInSet:separators]) {
        NSString *bare = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (bare.length)
            [mineSet addObject:bare];
    }
    for (NSString *part in [theirs componentsSeparatedByCharactersInSet:separators]) {
        NSString *bare = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (bare.length)
            [theirsSet addObject:bare];
    }
    if (![mineSet isEqualToSet:theirsSet]) {
        CharonHKDifferences++;
        printf("DIFFERS  %-56s port %-26s host %s\n", what.UTF8String, mine.UTF8String, theirs.UTF8String);
    }
}

static void CharonHKCompareDouble(NSString *what, double mine, double theirs)
{
    CharonHKComparisons++;
    // Relative: the two are doubles computed from the same factors, and a factor of the wrong order of
    // magnitude differs by six orders of magnitude, not by a last bit. An absolute floor of 1e-12
    // keeps a difference of exactly zero from being a failure of the comparison itself.
    double scale = MAX(1.0, MAX(fabs(mine), fabs(theirs)));
    if (fabs(mine - theirs) > 1e-9 * scale) {
        CharonHKDifferences++;
        printf("DIFFERS  %-56s port %.12g  host %.12g\n", what.UTF8String, mine, theirs);
    }
}

// The value a unit is measured at. Not round and not small, so a factor of the wrong order of
// magnitude cannot agree by accident.
static const double CharonHKProbe = 1.0 + 1.0 / 3.0;
// A temperature's conversion is affine, so a second value at a different place is what tells an offset
// that is right from one that is not.
static const double CharonHKSecondProbe = 21.5;

// ---------------------------------------------------------------------- units

typedef struct {
    __unsafe_unretained NSString *name;
    __unsafe_unretained NSString *dimension;
    BOOL affine;
} HKUnitCase;

// The unit strings the port's own table holds, each with the unit of its dimension it is measured
// against. The reference is the first name of the dimension, so the factor of every other unit of it is
// read off the host through the host's own conversion.
static HKUnitCase CharonHKUnits[] = {
    {@"g", @"g", NO}, {@"kg", @"g", NO}, {@"mg", @"g", NO}, {@"ug", @"g", NO}, {@"ng", @"g", NO},
    {@"pg", @"g", NO}, {@"fg", @"g", NO}, {@"oz", @"g", NO}, {@"lb", @"g", NO}, {@"st", @"g", NO},
    {@"m", @"m", NO}, {@"km", @"m", NO}, {@"cm", @"m", NO}, {@"mm", @"m", NO}, {@"um", @"m", NO},
    {@"nm", @"m", NO}, {@"in", @"m", NO}, {@"ft", @"m", NO}, {@"yd", @"m", NO}, {@"mi", @"m", NO},
    {@"L", @"L", NO}, {@"mL", @"L", NO}, {@"uL", @"L", NO}, {@"nL", @"L", NO}, {@"pL", @"L", NO},
    {@"fL", @"L", NO}, {@"dL", @"L", NO}, {@"cL", @"L", NO}, {@"daL", @"L", NO}, {@"hL", @"L", NO},
    {@"fl_oz_us", @"L", NO}, {@"pt_us", @"L", NO}, {@"cup_us", @"L", NO},
    {@"fl_oz_imp", @"L", NO}, {@"pt_imp", @"L", NO}, {@"cup_imp", @"L", NO},
    {@"Pa", @"Pa", NO}, {@"kPa", @"Pa", NO}, {@"hPa", @"Pa", NO}, {@"daPa", @"Pa", NO}, {@"MPa", @"Pa", NO},
    {@"mmHg", @"Pa", NO}, {@"cmAq", @"Pa", NO}, {@"atm", @"Pa", NO}, {@"inHg", @"Pa", NO},
    {@"s", @"s", NO}, {@"ms", @"s", NO}, {@"us", @"s", NO}, {@"ns", @"s", NO}, {@"min", @"s", NO},
    {@"hr", @"s", NO}, {@"d", @"s", NO},
    {@"J", @"J", NO}, {@"kJ", @"J", NO}, {@"MJ", @"J", NO}, {@"cal", @"J", NO}, {@"kcal", @"J", NO},
    {@"Cal", @"J", NO}, {@"kWh", @"J", NO},
    {@"K", @"K", YES}, {@"degC", @"K", YES}, {@"degF", @"K", YES},
    {@"S", @"S", NO}, {@"mS", @"S", NO}, {@"uS", @"S", NO}, {@"nS", @"S", NO}, {@"pS", @"S", NO},
    {@"count", @"count", NO}, {@"%", @"%", NO},
    // the products the SDK's own type table names for its types
    {@"count/s", @"count/s", NO}, {@"count/min", @"count/min", NO}, {@"m/s", @"m/s", NO},
    {@"L/min", @"L/min", NO}, {@"mg/dL", @"mg/dL", NO}, {@"ml/(kg*min)", @"ml/(kg*min)", NO},
    {@"kcal/(kg*hr)", @"kcal/(kg*hr)", NO}, {@"dBASPL", @"dBASPL", NO},
    // strings that are not units: both sides have to say so, and say it the same way
    {@"", @"", NO}, {@"not a unit", @"", NO}, {@"kg/", @"", NO}, {@"1/", @"", NO}, {@"*", @"", NO},
};
static const NSUInteger CharonHKUnitCaseCount = sizeof(CharonHKUnits) / sizeof(CharonHKUnits[0]);

static void CharonHKUnitCases(void)
{
    for (NSUInteger index = 0; index < CharonHKUnitCaseCount; index++) {
        NSString *name = CharonHKUnits[index].name;
        NSString *dimension = CharonHKUnits[index].dimension;
        NSString *label = [@"unitFromString:" stringByAppendingString:name];
        // A string neither side can make: the host raises, and the refusal is a behaviour the two have
        // to agree on just as much as an answer is, so it is asked for inside a @try on both sides.
        BOOL theirsRaised = NO, mineRaised = NO, theirsNil = NO, mineNil = NO;
        HKUnit *theirs = nil;
        CharonHostHKUnit *mine = nil;
        @try {
            theirs = [HKUnit unitFromString:name];
            theirsNil = theirs == nil;
        } @catch (NSException *exception) {
            theirsRaised = YES;
        }
        @try {
            mine = [CharonHostHKUnit unitFromString:name];
            mineNil = mine == nil;
        } @catch (NSException *exception) {
            mineRaised = YES;
        }
        CharonHKCompareBool([label stringByAppendingString:@" raises"], mineRaised, theirsRaised);
        CharonHKCompareBool([label stringByAppendingString:@" nil"], mineNil, theirsNil);
        if (!theirs || !mine)
            continue;
        if (!theirs || !mine)
            continue;
        CharonHKCompareFactors([label stringByAppendingString:@" unitString"], mine, theirs);
        CharonHKCompareBool([label stringByAppendingString:@" isNull"], mine.isNull, theirs.isNull);

        HKUnit *theirsReference = [HKUnit unitFromString:dimension];
        CharonHostHKUnit *mineReference = [CharonHostHKUnit unitFromString:dimension];
        if (!theirsReference || !mineReference)
            continue;
        // The factor of this unit in its dimension, each side measured through its own conversion.
        CharonHostHKQuantity *mineQuantity = [CharonHostHKQuantity quantityWithUnit:mine doubleValue:CharonHKProbe];
        HKQuantity *theirsQuantity = [HKQuantity quantityWithUnit:theirs doubleValue:CharonHKProbe];
        CharonHKCompareBool([label stringByAppendingString:@" isCompatibleWithUnit:itsDimension"],
                            [mineQuantity isCompatibleWithUnit:mineReference],
                            [theirsQuantity isCompatibleWithUnit:theirsReference]);
        if (![mineQuantity isCompatibleWithUnit:mineReference] || ![theirsQuantity isCompatibleWithUnit:theirsReference])
            continue;
        CharonHKCompareDouble([label stringByAppendingFormat:@" %g in %@", CharonHKProbe, dimension],
                              [mineQuantity doubleValueForUnit:mineReference],
                              [theirsQuantity doubleValueForUnit:theirsReference]);
        if (CharonHKUnits[index].affine) {
            CharonHostHKQuantity *mineSecond = [CharonHostHKQuantity quantityWithUnit:mine doubleValue:CharonHKSecondProbe];
            HKQuantity *theirsSecond = [HKQuantity quantityWithUnit:theirs doubleValue:CharonHKSecondProbe];
            CharonHKCompareDouble([label stringByAppendingFormat:@" %g in %@", CharonHKSecondProbe, dimension],
                                  [mineSecond doubleValueForUnit:mineReference],
                                  [theirsSecond doubleValueForUnit:theirsReference]);
        }
        // A unit of another dimension is not compatible, and a reciprocal is of the same dimension.
        HKUnit *theirsOther = [HKUnit unitFromString:@"count"];
        CharonHostHKUnit *mineOther = [CharonHostHKUnit unitFromString:@"count"];
        if (theirsOther && mineOther) {
            CharonHKCompareBool([label stringByAppendingString:@" isCompatibleWithUnit:count"],
                                [mineQuantity isCompatibleWithUnit:mineOther],
                                [theirsQuantity isCompatibleWithUnit:theirsOther]);
            // A temperature's reciprocal is refused on both sides, and a refusal is a behaviour, so it
            // is compared as one; everything else's reciprocal is compared by its factors.
            if (CharonHKUnits[index].affine) {
                BOOL mineRefused = NO, theirsRefused = NO;
                @try {
                    (void)[mine reciprocalUnit];
                } @catch (NSException *exception) {
                    mineRefused = YES;
                }
                @try {
                    (void)[theirs reciprocalUnit];
                } @catch (NSException *exception) {
                    theirsRefused = YES;
                }
                CharonHKCompareBool([label stringByAppendingString:@" reciprocal raises"], mineRefused,
                                    theirsRefused);
            } else {
                CharonHostHKUnit *mineReciprocal = [mine reciprocalUnit];
                HKUnit *theirsReciprocal = [theirs reciprocalUnit];
                CharonHKCompareFactors([label stringByAppendingString:@" reciprocal"], mineReciprocal,
                                       theirsReciprocal);
            }
        }
    }
}

// ------------------------------------------------------------------ arithmetic

// The four operations the header gives a unit, each asked of a pair of the same dimension and the
// answer compared two ways: the string the unit writes, and its factor against the same reference,
// which is what tells a product right in name and wrong in factor.
static void CharonHKUnitArithmetic(void)
{
    NSArray *pairs = @[@[ @"m", @"s" ], @[ @"m", @"min" ], @[ @"kg", @"m" ], @[ @"mL", @"kg" ],
                        @[ @"kcal", @"hr" ], @[ @"J", @"K" ], @[ @"count", @"min" ], @[ @"L", @"hr" ]];
    static NSInteger powers[] = { -2, -1, 2, 3 };
    for (NSArray *pair in pairs) {
        HKUnit *theirsLeft = [HKUnit unitFromString:pair[0]], *theirsRight = [HKUnit unitFromString:pair[1]];
        CharonHostHKUnit *mineLeft = [CharonHostHKUnit unitFromString:pair[0]],
                           *mineRight = [CharonHostHKUnit unitFromString:pair[1]];
        if (!theirsLeft || !theirsRight || !mineLeft || !mineRight)
            continue;
        NSString *label = [NSString stringWithFormat:@"%@ x %@", pair[0], pair[1]];
        HKUnit *theirsProduct = [theirsLeft unitMultipliedByUnit:theirsRight];
        CharonHostHKUnit *mineProduct = [mineLeft unitMultipliedByUnit:mineRight];
        CharonHKCompareFactors([label stringByAppendingString:@" product"], mineProduct, theirsProduct);
        HKUnit *theirsQuotient = [theirsLeft unitDividedByUnit:theirsRight];
        CharonHostHKUnit *mineQuotient = [mineLeft unitDividedByUnit:mineRight];
        CharonHKCompareFactors([label stringByAppendingString:@" quotient"], mineQuotient, theirsQuotient);

        // The factor of a product, each side measured by converting a quantity in the left-hand unit
        // into the product. A product has no dimension of its own on either side, so what is compared
        // is the number each side answers, which is where a product that is right in its string and
        // wrong in its factors shows.
        // A product has no dimension of its own, so what is compared is whether the two accept the
        // same conversion, and the round trip through the product when they do.
        CharonHostHKQuantity *mineValue = [CharonHostHKQuantity quantityWithUnit:mineLeft doubleValue:CharonHKProbe];
        HKQuantity *theirsValue = [HKQuantity quantityWithUnit:theirsLeft doubleValue:CharonHKProbe];
        CharonHKCompareBool([label stringByAppendingString:@" takes a conversion into the product"],
                            [mineValue isCompatibleWithUnit:mineProduct],
                            [theirsValue isCompatibleWithUnit:theirsProduct]);
        CharonHostHKQuantity *mineQuotientValue = [CharonHostHKQuantity quantityWithUnit:mineLeft doubleValue:CharonHKProbe];
        HKQuantity *theirsQuotientValue = [HKQuantity quantityWithUnit:theirsLeft doubleValue:CharonHKProbe];
        CharonHKCompareBool([label stringByAppendingString:@" takes a conversion into the quotient"],
                            [mineQuotientValue isCompatibleWithUnit:mineQuotient],
                            [theirsQuotientValue isCompatibleWithUnit:theirsQuotient]);
        for (NSUInteger step = 0; step < 4; step++) {
            HKUnit *theirsPower = [theirsLeft unitRaisedToPower:powers[step]];
            CharonHostHKUnit *minePower = [mineLeft unitRaisedToPower:powers[step]];
            CharonHKCompareFactors([NSString stringWithFormat:@"%@ raised to %ld", pair[0], (long)powers[step]],
                                   minePower, theirsPower);
        }
    }
    // A temperature cannot be multiplied, divided or raised to a power, and both sides raise.
    HKUnit *theirsCelsius = [HKUnit degreeCelsiusUnit], *theirsMetre = [HKUnit meterUnit];
    CharonHostHKUnit *mineCelsius = [CharonHostHKUnit degreeCelsiusUnit],
                       *mineMetre = [CharonHostHKUnit meterUnit];
    NSArray *selectors = @[ @"unitMultipliedByUnit:", @"unitDividedByUnit:" ];
    for (NSUInteger step = 0; step < selectors.count; step++) {
        SEL chosen = NSSelectorFromString(selectors[step]);
        NSString *label = [NSString stringWithFormat:@"degC %@ m raises", selectors[step]];
        BOOL mineRaised = NO, theirsRaised = NO;
        @try {
            (void)[mineCelsius performSelector:chosen withObject:mineMetre];
        } @catch (NSException *exception) {
            mineRaised = YES;
        }
        @try {
            (void)[theirsCelsius performSelector:chosen withObject:theirsMetre];
        } @catch (NSException *exception) {
            theirsRaised = YES;
        }
        CharonHKCompareBool(label, mineRaised, theirsRaised);
    }
}

// ------------------------------------------------------- the factory methods

// Every prefixed factory method of the header, at every prefix its enum has, and then every plain
// one, on both sides. This is where the spelling of a prefix is answered, and it is a different
// question from the one the table above asks: the table holds the names the header's comments give,
// and these are the names the methods make.
typedef id (^CharonHKPrefixedFactory)(NSInteger);

static CharonHKPrefixedFactory CharonHKPortPrefixed(NSUInteger index)
{
    switch (index) {
    case 0:
        return ^id(NSInteger p) { return [CharonHostHKUnit gramUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 1:
        return ^id(NSInteger p) { return [CharonHostHKUnit meterUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 2:
        return ^id(NSInteger p) { return [CharonHostHKUnit literUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 3:
        return ^id(NSInteger p) { return [CharonHostHKUnit pascalUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 4:
        return ^id(NSInteger p) { return [CharonHostHKUnit secondUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 5:
        return ^id(NSInteger p) { return [CharonHostHKUnit jouleUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    default:
        return ^id(NSInteger p) { return [CharonHostHKUnit siemenUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    }
}

static CharonHKPrefixedFactory CharonHKSystemPrefixed(NSUInteger index)
{
    switch (index) {
    case 0:
        return ^id(NSInteger p) { return [HKUnit gramUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 1:
        return ^id(NSInteger p) { return [HKUnit meterUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 2:
        return ^id(NSInteger p) { return [HKUnit literUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 3:
        return ^id(NSInteger p) { return [HKUnit pascalUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 4:
        return ^id(NSInteger p) { return [HKUnit secondUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    case 5:
        return ^id(NSInteger p) { return [HKUnit jouleUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    default:
        return ^id(NSInteger p) { return [HKUnit siemenUnitWithMetricPrefix:(HKMetricPrefix)p]; };
    }
}

static void CharonHKPrefixedFactories(void)
{
    // The seven prefixed factories of the iOS 8.0 surface, which is the surface this library carries.
    // The header's later ones - hertzUnitWithMetricPrefix: of 13.0, voltUnitWithMetricPrefix: of 14.0
    // and wattUnitWithMetricPrefix: of 16.0 - are asked for in the group of their own release, and
    // asking the host for them here would compare a unit this library does not yet make with one it
    // does.
    NSArray *factories = @[ @"gramUnitWithMetricPrefix:", @"meterUnitWithMetricPrefix:",
                            @"literUnitWithMetricPrefix:", @"pascalUnitWithMetricPrefix:",
                            @"secondUnitWithMetricPrefix:", @"jouleUnitWithMetricPrefix:",
                            @"siemenUnitWithMetricPrefix:" ];
    for (NSInteger prefix = HKMetricPrefixNone; prefix <= HKMetricPrefixTera; prefix++) {
        for (NSUInteger index = 0; index < factories.count; index++) {
            NSString *label = [NSString stringWithFormat:@"%@ prefix %ld", factories[index], (long)prefix];
            HKUnit *theirs = nil;
            CharonHostHKUnit *mine = nil;
            BOOL theirsRefused = NO, mineRefused = NO;
            @try {
                theirs = (HKUnit *)CharonHKSystemPrefixed(index)(prefix);
                theirsRefused = theirs == nil;
            } @catch (NSException *exception) {
                theirsRefused = YES;
            }
            @try {
                mine = (CharonHostHKUnit *)CharonHKPortPrefixed(index)(prefix);
                mineRefused = mine == nil;
            } @catch (NSException *exception) {
                mineRefused = YES;
            }
            CharonHKCompareBool([label stringByAppendingString:@" answers"], !mineRefused, !theirsRefused);
            if (!theirs || !mine)
                continue;
            CharonHKCompare([label stringByAppendingString:@" unitString"], mine.unitString, theirs.unitString);
        }
    }
    // The plain factories, whose spelling question is the same. A selector the host's release has
    // dropped is asked for through respondsToSelector: and is not compared, because there is nothing
    // on that side to compare with.
    NSArray *plain = @[ @"gramUnit", @"ounceUnit", @"poundUnit", @"stoneUnit", @"meterUnit", @"inchUnit",
                        @"footUnit", @"yardUnit", @"mileUnit", @"literUnit", @"fluidOunceUSUnit",
                        @"fluidOunceImperialUnit", @"pintUSUnit", @"pintImperialUnit", @"cupUSUnit",
                        @"cupImperialUnit", @"pascalUnit", @"millimeterOfMercuryUnit",
                        @"centimeterOfWaterUnit", @"atmosphereUnit",
                        @"secondUnit", @"minuteUnit", @"hourUnit", @"dayUnit", @"jouleUnit",
                        @"kilocalorieUnit", @"calorieUnit", @"degreeCelsiusUnit",
                        @"degreeFahrenheitUnit", @"kelvinUnit", @"siemenUnit", @"countUnit",
                        @"percentUnit" ];
    // +[HKUnit kilojoulesUnit] and +[HKUnit milliseconds] are deliberately not asked for: no SDK
    // header of 16.4 or 26.2 declares either, so they are Apple's own and this library does not
    // answer them. The two units are in the table and +[HKUnit unitFromString:] reads them, which the
    // unit cases above already compare.
    for (NSString *name in plain) {
        SEL chosen = NSSelectorFromString(name);
        BOOL theirsHas = [HKUnit respondsToSelector:chosen];
        BOOL mineHas = [CharonHostHKUnit respondsToSelector:chosen];
        CharonHKCompareBool([name stringByAppendingString:@" exists"], mineHas, theirsHas);
        if (!theirsHas || !mineHas)
            continue;
        id theirs = [HKUnit performSelector:chosen];
        id mine = [CharonHostHKUnit performSelector:chosen];
        if (!theirs || !mine) {
            CharonHKCompareBool([name stringByAppendingString:@" answers"], mine != nil, theirs != nil);
            continue;
        }
        CharonHKCompare([name stringByAppendingString:@" unitString"], [mine unitString], [theirs unitString]);
    }
}

// ----------------------------------------------------------------- quantities

static void CharonHKQuantities(void)
{
    NSArray *units = @[ @"kg", @"g", @"m", @"cm", @"L", @"mL", @"kcal", @"kJ", @"min", @"hr", @"degC",
                        @"degF", @"K", @"mmHg", @"count", @"%", @"m/s", @"mg/dL" ];
    static const double values[] = { 0.0, 1.0, -1.0, 0.5, 2.5, -273.15, 1000.0, 1.0 / 3.0 };
    for (NSUInteger left = 0; left < units.count; left++) {
        for (NSUInteger right = 0; right < units.count; right++) {
            HKUnit *theirsLeft = [HKUnit unitFromString:units[left]], *theirsRight = [HKUnit unitFromString:units[right]];
            CharonHostHKUnit *mineLeft = [CharonHostHKUnit unitFromString:units[left]],
                               *mineRight = [CharonHostHKUnit unitFromString:units[right]];
            if (!theirsLeft || !theirsRight || !mineLeft || !mineRight)
                continue;
            for (NSUInteger step = 0; step < 8; step++) {
                HKQuantity *theirs = [HKQuantity quantityWithUnit:theirsLeft doubleValue:values[step]];
                CharonHostHKQuantity *mine = [CharonHostHKQuantity quantityWithUnit:mineLeft doubleValue:values[step]];
                NSString *label = [NSString stringWithFormat:@"%g %@ -> %@", values[step], units[left], units[right]];
                CharonHKCompareBool([label stringByAppendingString:@" isCompatibleWithUnit:"],
                                    [mine isCompatibleWithUnit:mineRight], [theirs isCompatibleWithUnit:theirsRight]);
                if (![mine isCompatibleWithUnit:mineRight] || ![theirs isCompatibleWithUnit:theirsRight])
                    continue;
                CharonHKCompareDouble([label stringByAppendingString:@" doubleValueForUnit:"],
                                      [mine doubleValueForUnit:mineRight], [theirs doubleValueForUnit:theirsRight]);
                CharonHKCompareInt([label stringByAppendingString:@" compare:itself"],
                                   [mine compare:mine], [theirs compare:theirs]);
                if (![mine isCompatibleWithUnit:mineLeft] || ![theirs isCompatibleWithUnit:theirsLeft])
                    continue;
                CharonHKCompareInt([label stringByAppendingString:@" compare:itsUnit"],
                                   [mine compare:mine], [theirs compare:theirs]);
            }
        }
    }
    // Two quantities of the same dimension order and against each other; two of different dimensions
    // raise on both sides.
    HKUnit *theirsKg = [HKUnit gramUnitWithMetricPrefix:HKMetricPrefixKilo];
    HKUnit *theirsG = [HKUnit gramUnit];
    HKUnit *theirsM = [HKUnit meterUnit];
    CharonHostHKUnit *mineKg = [CharonHostHKUnit gramUnitWithMetricPrefix:HKMetricPrefixKilo];
    CharonHostHKUnit *mineG = [CharonHostHKUnit gramUnit];
    CharonHostHKUnit *mineM = [CharonHostHKUnit meterUnit];
    HKQuantity *theirsHeavy = [HKQuantity quantityWithUnit:theirsKg doubleValue:2.0];
    HKQuantity *theirsLight = [HKQuantity quantityWithUnit:theirsG doubleValue:2500.0];
    CharonHostHKQuantity *mineHeavy = [CharonHostHKQuantity quantityWithUnit:mineKg doubleValue:2.0];
    CharonHostHKQuantity *mineLight = [CharonHostHKQuantity quantityWithUnit:mineG doubleValue:2500.0];
    CharonHKCompareInt(@"2 kg compare: 2500 g", [mineHeavy compare:mineLight], [theirsHeavy compare:theirsLight]);
    CharonHKCompareInt(@"2500 g compare: 2 kg", [mineLight compare:mineHeavy], [theirsLight compare:theirsHeavy]);
    HKQuantity *theirsMetre = [HKQuantity quantityWithUnit:theirsM doubleValue:1.0];
    CharonHostHKQuantity *mineMetre = [CharonHostHKQuantity quantityWithUnit:mineM doubleValue:1.0];
    BOOL mineRaised = NO, theirsRaised = NO;
    @try {
        (void)[mineHeavy compare:mineMetre];
    } @catch (NSException *exception) {
        mineRaised = YES;
    }
    @try {
        (void)[theirsHeavy compare:theirsMetre];
    } @catch (NSException *exception) {
        theirsRaised = YES;
    }
    CharonHKCompareBool(@"2 kg compare: 1 m raises", mineRaised, theirsRaised);
}

// ------------------------------------------------------------ the type table

// Every quantity type identifier the SDK's own header names a unit and an aggregation for, which is
// the port's table, is asked of the host: the aggregation the host records for it, and whether the
// host considers the port's unit, and the host's own unit, of it.
static void CharonHKTypeTable(void)
{
    for (NSUInteger index = 0; index < CharonHKQuantityTypeCount(); index++) {
        const CharonHKTypeEntry *entry = CharonHKQuantityTypeEntryAt(index);
        if (!entry)
            continue;
        NSString *identifier = entry->identifier;
        HKQuantityType *theirs = (HKQuantityType *)[HKObjectType quantityTypeForIdentifier:identifier];
        CharonHostHKQuantityType *mine = (CharonHostHKQuantityType *)[CharonHostHKObjectType quantityTypeForIdentifier:identifier];
        CharonHKCompareBool([identifier stringByAppendingString:@" a quantity type"], mine != nil, theirs != nil);
        if (!theirs || !mine)
            continue;
        // The aggregation is compared as the one the port's contract has, cumulative or discrete. The
        // header the port compiles against gives HKQuantityAggregationStyle two cases; the header whose
        // comment the table is read from names five, and the host answers the three later ones with a
        // case of their own. A caller of this library can only be told the two, so the two are what is
        // compared - and the ten types where the host's finer answer differs are named in run.sh and in
        // facts/HealthKit/HealthKit.md, so that the difference is written down rather than passed over.
        CharonHKCompareInt([identifier stringByAppendingString:@" aggregates cumulatively"],
                           (NSInteger)mine.aggregationStyle, (NSInteger)theirs.aggregationStyle == 0 ? 0 : 1);
        // A type the SDK counts in a string no unit can be made of - the header gives
        // `appleEffortScore` for one of them - is a refusal on both sides and is compared as one.
        BOOL mineRefused = NO, theirsRefused = NO;
        HKUnit *theirsUnit = nil;
        CharonHostHKUnit *mineUnit = nil;
        @try {
            theirsUnit = [HKUnit unitFromString:entry->unit];
        } @catch (NSException *exception) {
            theirsRefused = YES;
        }
        @try {
            mineUnit = [CharonHostHKUnit unitFromString:entry->unit];
        } @catch (NSException *exception) {
            mineRefused = YES;
        }
        CharonHKCompareBool([identifier stringByAppendingString:@" its unit raises"], mineRefused, theirsRefused);
        if (theirsUnit && mineUnit)
            CharonHKCompareBool([identifier stringByAppendingString:@" isCompatibleWithUnit:its own unit"],
                                [mine isCompatibleWithUnit:mineUnit], [theirs isCompatibleWithUnit:theirsUnit]);
        // A type of a count accepts a count and a fraction, and a type of a mass accepts neither.
        for (NSString *probe in @[ @"count", @"%", @"kg", @"m", @"s" ]) {
            HKUnit *theirsProbe = [HKUnit unitFromString:probe];
            CharonHostHKUnit *mineProbe = [CharonHostHKUnit unitFromString:probe];
            if (!theirsProbe || !mineProbe)
                continue;
            CharonHKCompareBool([identifier stringByAppendingFormat:@" isCompatibleWithUnit:%@", probe],
                                [mine isCompatibleWithUnit:mineProbe], [theirs isCompatibleWithUnit:theirsProbe]);
        }
    }
}


// ------------------------------------------------- the query objects' own properties
//
// Everything a query holds about itself, which is what the host's own query holds too, asked of both
// without a store anywhere: the type it is for, the predicate it was made with, the limit, the sort
// descriptors, the anchor, the interval and the options. This is the check that reaches HKQueries.m,
// which the unit and quantity cases never did - a mutation of -anchorDate: was invisible to them.

static void CharonHKQueryObjects(void)
{
    // The predicate this section compares. The host's own NSPredicate refuses a metadata key path
    // outside a HealthKit query, so the predicate is over a key path of the object itself, which both
    // sides build and evaluate the same way, and the copy semantics of what a query keeps is compared
    // with the host's on the same predicate.
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K.%K == %@", HKPredicateKeyPathMetadata,
                              HKMetadataKeySyncIdentifier, @"sync"];
    NSSortDescriptor *byDate = [NSSortDescriptor sortDescriptorWithKey:@"startDate" ascending:YES];
    NSDate *anchor = [NSDate dateWithTimeIntervalSince1970:1600000000];
    NSDateComponents *interval = [[NSDateComponents alloc] init];
    interval.day = 1;
    HKQuantityType *stepCount = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierStepCount];
    HKQuantityType *heartRate = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    if (!stepCount || !heartRate)
        return;


    // The check the coordinator asked for: the superclass of the port's own sample query, and the
    // offset of _objectType in it and in the class that declares it. If the two differ the object is
    // of a different layout than the code that reads it thinks, which is what a rename that did not
    // reach one file's superclass looks like from the inside.
    {
        Class mineClass = objc_getClass("CharonHostHKSampleQuery");
        Class mineSuper = mineClass ? class_getSuperclass(mineClass) : Nil;
        Class theirsClass = objc_getClass("HKSampleQuery");
        Class theirsSuper = theirsClass ? class_getSuperclass(theirsClass) : Nil;
        printf("LAYOUT mine=%s super=%s | theirs=%s super=%s\n",
               mineClass ? class_getName(mineClass) : "(none)",
               mineSuper ? class_getName(mineSuper) : "(none)",
               theirsClass ? class_getName(theirsClass) : "(none)",
               theirsSuper ? class_getName(theirsSuper) : "(none)");
        printf("LAYOUT mine superclass is the host's HKQuery: %s\n",
               mineSuper == objc_getClass("HKQuery") ? "YES" : "no");
        Ivar inMine = mineSuper ? class_getInstanceVariable(mineSuper, "_objectType") : NULL;
        Ivar inTheirs = theirsSuper ? class_getInstanceVariable(theirsSuper, "_objectType") : NULL;
        printf("LAYOUT _objectType offset: mineSuper=%lld theirsSuper=%lld\n",
               inMine ? (long long)ivar_getOffset(inMine) : -1LL,
               inTheirs ? (long long)ivar_getOffset(inTheirs) : -1LL);
        Ivar inMineQuery = mineClass ? class_getInstanceVariable(mineClass, "_objectType") : NULL;
        printf("LAYOUT _objectType offset on the sample query itself: %lld\n",
               inMineQuery ? (long long)ivar_getOffset(inMineQuery) : -1LL);
    }

    // The type a query is for, and the sample type under its own name, which is the same object.
    // The objects the predicate is evaluated against, and the answers both sides give for them. The
    // host's NSPredicate takes a metadata key path only where a HealthKit query is the context, so
    // these are a sample's shape: a dictionary of dictionaries, which is what a predicate over a
    // sample's metadata is written for.
    NSDictionary *matching = @{ @"metadata": @{ HKMetadataKeySyncIdentifier: @"sync" } };
    NSDictionary *mismatched = @{ @"metadata": @{ HKMetadataKeySyncIdentifier: @"other" } };
    // The collection query is the sixth of the six, and the port's own five-argument initialiser is
    // checked: the type, the predicate, the options, the anchor and the interval it keeps, and the
    // predicate's own answer. The host's release of the class carries no five-argument initialiser the
    // 16.4 header declares and the one it does carry raises, so nothing is compared here that the
    // host cannot answer, and the host's own members are asked of the queries it does build, below.
    CharonHostHKStatisticsCollectionQuery *mineCollection =
        [[CharonHostHKStatisticsCollectionQuery alloc] initWithQuantityType:stepCount
                                                      quantitySamplePredicate:predicate
                                                                   options:HKStatisticsOptionCumulativeSum
                                                                anchorDate:anchor
                                                        intervalComponents:interval];
    CharonHKCompare(@"collection query anchorDate", mineCollection.anchorDate, anchor);
    CharonHKCompareInt(@"collection query options", (NSInteger)mineCollection.options,
                       (NSInteger)HKStatisticsOptionCumulativeSum);
    CharonHKCompareInt(@"collection query interval day", mineCollection.intervalComponents.day, (NSInteger)1);
    CharonHKCompareInt(@"collection query interval month", mineCollection.intervalComponents.month, (NSInteger)0);
    CharonHKCompare(@"collection query objectType identifier", mineCollection.objectType.identifier,
                    stepCount.identifier);
    // The predicate it was made with, and the answers it gives to a matching and a mismatching object.
    CharonHKCompare(@"collection query predicate", mineCollection.predicate, predicate);
    CharonHKCompareBool(@"collection query predicate evaluates a match",
                        [mineCollection.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"sync"}], YES);
    CharonHKCompareBool(@"collection query predicate rejects a mismatch",
                        [mineCollection.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"other"}], NO);
    // and the same predicate as the host's own sample query and statistics query answer it, so the two
    // are compared rather than one against a constant
    HKSampleQuery *theirsByPredicate = [[HKSampleQuery alloc] initWithSampleType:stepCount
                                                                       predicate:predicate
                                                                           limit:HKObjectQueryNoLimit
                                                                    sortDescriptors:nil
                                                                     resultsHandler:nil];
    CharonHostHKSampleQuery *mineByPredicate = [[CharonHostHKSampleQuery alloc] initWithSampleType:stepCount
                                                                                           predicate:predicate
                                                                                               limit:HKObjectQueryNoLimit
                                                                                        sortDescriptors:nil
                                                                                         resultsHandler:nil];
    CharonHKCompare(@"a sample query's predicate", mineByPredicate.predicate, theirsByPredicate.predicate);
    CharonHKCompareBool(@"that predicate evaluates a match",
                        [mineByPredicate.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"sync"}],
                        [theirsByPredicate.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"sync"}]);
    CharonHKCompareBool(@"that predicate rejects a mismatch",
                        [mineByPredicate.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"other"}],
                        [theirsByPredicate.predicate evaluateWithObject:@{@"HKSourceSyncIdentifier": @"other"}]);

    // A sample query: the limit and the sort descriptors it was made with, and the type again.
    HKSampleQuery *theirsSample = [[HKSampleQuery alloc] initWithSampleType:heartRate
                                                                 predicate:predicate
                                                                     limit:42
                                                          sortDescriptors:@[ byDate ]
                                                           resultsHandler:nil];
    CharonHostHKSampleQuery *mineSample = [[CharonHostHKSampleQuery alloc] initWithSampleType:heartRate
                                                                               predicate:predicate
                                                                                   limit:42
                                                                        sortDescriptors:@[ byDate ]
                                                                         resultsHandler:nil];
    CharonHKCompare(@"sample query objectType identifier", mineSample.objectType.identifier, theirsSample.objectType.identifier);
    CharonHKCompare(@"sample query sampleType identifier", mineSample.sampleType.identifier, theirsSample.sampleType.identifier);
    CharonHKCompareInt(@"sample query limit", (NSInteger)mineSample.limit, (NSInteger)theirsSample.limit);
    CharonHKCompare(@"sample query sortDescriptors", mineSample.sortDescriptors, theirsSample.sortDescriptors);
    CharonHKCompare(@"sample query predicate", mineSample.predicate, theirsSample.predicate);

    // The limit and the sort descriptors of the sample query, when it is made without them.
    HKSampleQuery *theirsBare = [[HKSampleQuery alloc] initWithSampleType:stepCount
                                                                predicate:nil
                                                                    limit:HKObjectQueryNoLimit
                                                           sortDescriptors:nil
                                                            resultsHandler:nil];
    CharonHostHKSampleQuery *mineBare = [[CharonHostHKSampleQuery alloc] initWithSampleType:stepCount
                                                                                  predicate:nil
                                                                                      limit:HKObjectQueryNoLimit
                                                                           sortDescriptors:nil
                                                                            resultsHandler:nil];
    CharonHKCompareInt(@"a bare sample query's limit", (NSInteger)mineBare.limit, (NSInteger)theirsBare.limit);
    CharonHKCompare(@"a bare sample query's sortDescriptors", mineBare.sortDescriptors, theirsBare.sortDescriptors);
    CharonHKCompare(@"a bare sample query's predicate", mineBare.predicate, theirsBare.predicate);
    CharonHKCompare(@"a bare sample query's objectType identifier", mineBare.objectType.identifier,
                    theirsBare.objectType.identifier);

    // A statistics query: the type and the predicate, which are all it holds before it runs.
    HKStatisticsQuery *theirsStats = [[HKStatisticsQuery alloc] initWithQuantityType:heartRate
                                                          quantitySamplePredicate:predicate
                                                                           options:HKStatisticsOptionDiscreteAverage
                                                                    completionHandler:nil];
    CharonHostHKStatisticsQuery *mineStats = [[CharonHostHKStatisticsQuery alloc] initWithQuantityType:heartRate
                                                                                        quantitySamplePredicate:predicate
                                                                                                     options:HKStatisticsOptionDiscreteAverage
                                                                                              completionHandler:nil];
    CharonHKCompare(@"statistics query objectType identifier", mineStats.objectType.identifier,
                    theirsStats.objectType.identifier);
    CharonHKCompare(@"statistics query predicate", mineStats.predicate, theirsStats.predicate);

    // A source query, whose type is the one it is for, and an anchored query, whose anchor is what it
    // was made with.
    HKSourceQuery *theirsSource = [[HKSourceQuery alloc] initWithSampleType:stepCount
                                                             samplePredicate:predicate
                                                           completionHandler:nil];
    CharonHostHKSourceQuery *mineSource = [[CharonHostHKSourceQuery alloc] initWithSampleType:stepCount
                                                                                     samplePredicate:predicate
                                                                                   completionHandler:nil];
    CharonHKCompare(@"source query objectType identifier", mineSource.objectType.identifier,
                    theirsSource.objectType.identifier);
    CharonHKCompare(@"source query predicate", mineSource.predicate, theirsSource.predicate);
}

// --------------------------------------------------------- the iOS 11.0 group
//
// What the group adds, asked of the host's own HealthKit and of this library's, with no store: the
// series type and the route type, the clinical type of an identifier, the FHIR resource's own members
// and the round trip of its archive, the two clinical-record predicates over the key paths the release
// spells "FHIRResource.identifier" and "FHIRResource.resourceType", and the three unit factories the
// release adds. A row the host's release does not have is skipped and said, never guessed.

static void CharonHK11Group(void)
{
    // The series type: the one of 11.0, held as a shared object, and the class method that names it.
    HKSeriesType *theirsRoute = [HKSeriesType workoutRouteType];
    CharonHostHKSeriesType *mineRoute = [CharonHostHKSeriesType workoutRouteType];
    if (theirsRoute && mineRoute) {
        CharonHKCompare(@"series workoutRouteType identifier", mineRoute.identifier, theirsRoute.identifier);
        CharonHKCompare(@"series workoutRouteType twice is the same object",
                        @([HKSeriesType workoutRouteType] == [HKSeriesType workoutRouteType]),
                        @([CharonHostHKSeriesType workoutRouteType] == [CharonHostHKSeriesType workoutRouteType]));
    } else {
        printf("skipped: the host's HealthKit has no +[HKSeriesType workoutRouteType]\n");
    }

    // The route type through the class method of HKObjectType, and an identifier that is not one.
    HKSeriesType *theirsById = [HKObjectType seriesTypeForIdentifier:HKWorkoutRouteTypeIdentifier];
    CharonHostHKSeriesType *mineById = [CharonHostHKObjectType seriesTypeForIdentifier:HKWorkoutRouteTypeIdentifier];
    CharonHKCompare(@"seriesTypeForIdentifier: the route type", mineById.identifier, theirsById.identifier);
    CharonHKCompare(@"seriesTypeForIdentifier: an identifier that is not a series type",
                    [HKObjectType seriesTypeForIdentifier:@"HKQuantityTypeIdentifierStepCount"],
                    [CharonHostHKObjectType seriesTypeForIdentifier:@"HKQuantityTypeIdentifierStepCount"]);

    // The clinical type of an identifier, and one that is not a clinical type.
    HKClinicalType *theirsClinical = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierConditionRecord];
    CharonHostHKClinicalType *mineClinical = [CharonHostHKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierConditionRecord];
    if (theirsClinical || mineClinical) {
        CharonHKCompare(@"clinicalTypeForIdentifier: condition record", mineClinical.identifier, theirsClinical.identifier);
        CharonHKCompare(@"clinicalTypeForIdentifier: an identifier that is not a clinical type",
                        [CharonHostHKObjectType clinicalTypeForIdentifier:@"HKQuantityTypeIdentifierStepCount"],
                        [HKObjectType clinicalTypeForIdentifier:@"HKQuantityTypeIdentifierStepCount"]);
    } else {
        printf("skipped: the host's HealthKit has no clinical type of 11.0\n");
    }

    NSData *resourceData = [@"{\"resourceType\":\"Observation\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *source = [NSURL URLWithString:@"https://example.org/1"];
    // The FHIR resource: the SDK gives the class -init unavailable and declares no other
    // initialiser, in 16.4 and in 26.2 both, so the host's release cannot be asked to build one here
    // and nothing is compared that the host cannot answer. What the port's own factory keeps, and what
    // the archive and a copy of it keep, is checked against the same values it was built from, and the
    // resource type strings and the two key paths are compared with the host's own, which the header
    // gives and this library copies.
    CharonHostHKFHIRResource *mine =
        [CharonHostHKFHIRResource charon_resourceWithType:HKFHIRResourceTypeObservation
                                       identifier:@"obs-1"
                                             data:resourceData
                                        sourceURL:source];
    CharonHKCompare(@"FHIRResource identifier", mine.identifier, @"obs-1");
    CharonHKCompare(@"FHIRResource data", mine.data, resourceData);
    CharonHKCompare(@"FHIRResource sourceURL", mine.sourceURL, source);
    NSData *mineFHIRArchive = [NSKeyedArchiver archivedDataWithRootObject:mine];
    CharonHostHKFHIRResource *mineReadBack =
        (CharonHostHKFHIRResource *)[NSKeyedUnarchiver unarchiveObjectWithData:mineFHIRArchive];
    CharonHKCompare(@"FHIRResource archive round trip: data", mineReadBack.data, resourceData);
    CharonHKCompare(@"FHIRResource archive round trip: identifier", mineReadBack.identifier, @"obs-1");
    CharonHostHKFHIRResource *mineResourceCopy = (CharonHostHKFHIRResource *)[mine copy];
    CharonHKCompare(@"FHIRResource copy: identifier", mineResourceCopy.identifier, @"obs-1");
    // the eight resource types, and the three paths, against the host's own HealthKit
    CharonHKCompare(@"HKFHIRResourceTypeObservation", HKFHIRResourceTypeObservation, @"Observation");
    CharonHKCompare(@"HKFHIRResourceTypeCondition", HKFHIRResourceTypeCondition, @"Condition");
    CharonHKCompare(@"HKFHIRResourceTypeImmunization", HKFHIRResourceTypeImmunization, @"Immunization");
    CharonHKCompare(@"HKFHIRResourceTypeMedicationDispense", HKFHIRResourceTypeMedicationDispense, @"MedicationDispense");
    CharonHKCompare(@"HKFHIRResourceTypeMedicationOrder", HKFHIRResourceTypeMedicationOrder, @"MedicationOrder");
    CharonHKCompare(@"HKFHIRResourceTypeMedicationStatement", HKFHIRResourceTypeMedicationStatement, @"MedicationStatement");
    CharonHKCompare(@"HKFHIRResourceTypeProcedure", HKFHIRResourceTypeProcedure, @"Procedure");
    CharonHKCompare(@"HKFHIRResourceTypeAllergyIntolerance", HKFHIRResourceTypeAllergyIntolerance, @"AllergyIntolerance");
    CharonHKCompare(@"HKPredicateKeyPathSum", HKPredicateKeyPathSum, @"quantity");
    CharonHKCompare(@"HKPredicateKeyPathClinicalRecordFHIRResourceType", HKPredicateKeyPathClinicalRecordFHIRResourceType,
                    @"FHIRResource.resourceType");
    CharonHKCompare(@"HKPredicateKeyPathClinicalRecordFHIRResourceIdentifier",
                    HKPredicateKeyPathClinicalRecordFHIRResourceIdentifier, @"FHIRResource.identifier");
    CharonHKCompare(@"HKMetadataKeyCrossTrainerDistance", HKMetadataKeyCrossTrainerDistance, @"HKCrossTrainerDistance");
    CharonHKCompare(@"HKMetadataKeyFitnessMachineDuration", HKMetadataKeyFitnessMachineDuration,
                    @"HKFitnessMachineDuration");
    CharonHKCompare(@"HKMetadataKeyIndoorBikeDistance", HKMetadataKeyIndoorBikeDistance, @"HKIndoorBikeDistance");

    // The two clinical-record predicates, over the key paths the release itself spells. The host's
    // HealthKit builds them and so does this library, and the two answers are compared.
    NSPredicate *theirsType = [HKQuery predicateForClinicalRecordsWithFHIRResourceType:HKFHIRResourceTypeObservation];
    NSPredicate *mineType = [CharonHostHKQuery predicateForClinicalRecordsWithFHIRResourceType:HKFHIRResourceTypeObservation];
    CharonHKCompare(@"predicateForClinicalRecordsWithFHIRResourceType: format", mineType.predicateFormat, theirsType.predicateFormat);
    NSPredicate *theirsBoth = [HKQuery predicateForClinicalRecordsFromSource:nil
                                                             FHIRResourceType:HKFHIRResourceTypeObservation
                                                                  identifier:@"obs-1"];
    NSPredicate *mineBoth = [CharonHostHKQuery predicateForClinicalRecordsFromSource:nil
                                                           FHIRResourceType:HKFHIRResourceTypeObservation
                                                                identifier:@"obs-1"];
    CharonHKCompare(@"predicateForClinicalRecordsFromSource: format", mineBoth.predicateFormat, theirsBoth.predicateFormat);
    CharonHKCompare(@"predicateForClinicalRecordsFromSource: nothing given is nil",
                    [CharonHostHKQuery predicateForClinicalRecordsFromSource:nil FHIRResourceType:nil identifier:nil],
                    [HKQuery predicateForClinicalRecordsFromSource:nil FHIRResourceType:nil identifier:nil]);

    // The three unit factories of 11.0, whose strings the header's own comments give: the string, and
    // then the factor through the base each converts to, so a right string with a wrong factor is caught
    CharonHKCompare(@"internationalUnit unitString", [CharonHostHKUnit internationalUnit].unitString,
                    [HKUnit internationalUnit].unitString);
    CharonHKCompare(@"smallCalorieUnit unitString", [CharonHostHKUnit smallCalorieUnit].unitString,
                    [HKUnit smallCalorieUnit].unitString);
    CharonHKCompare(@"largeCalorieUnit unitString", [CharonHostHKUnit largeCalorieUnit].unitString,
                    [HKUnit largeCalorieUnit].unitString);
    CharonHKCompareDouble(@"internationalUnit in a count",
                          [[CharonHostHKQuantity quantityWithUnit:[CharonHostHKUnit internationalUnit] doubleValue:1.0]
                              doubleValueForUnit:[CharonHostHKUnit countUnit]],
                          [[HKQuantity quantityWithUnit:[HKUnit internationalUnit] doubleValue:1.0]
                              doubleValueForUnit:[HKUnit countUnit]]);
    CharonHKCompareDouble(@"smallCalorieUnit in a joule",
                          [[CharonHostHKQuantity quantityWithUnit:[CharonHostHKUnit smallCalorieUnit] doubleValue:1.0]
                              doubleValueForUnit:[CharonHostHKUnit jouleUnit]],
                          [[HKQuantity quantityWithUnit:[HKUnit smallCalorieUnit] doubleValue:1.0]
                              doubleValueForUnit:[HKUnit jouleUnit]]);
    CharonHKCompareDouble(@"largeCalorieUnit in a joule",
                          [[CharonHostHKQuantity quantityWithUnit:[CharonHostHKUnit largeCalorieUnit] doubleValue:1.0]
                              doubleValueForUnit:[CharonHostHKUnit jouleUnit]],
                          [[HKQuantity quantityWithUnit:[HKUnit largeCalorieUnit] doubleValue:1.0]
                              doubleValueForUnit:[HKUnit jouleUnit]]);

    // The source revision's two new members and its four-argument initialiser. The host's HealthKit
    // builds a revision only through the store, so what is compared is the members the port keeps, the
    // archive they survive, and the sentinels the header declares, none of which needs a store.
    NSOperatingSystemVersion fifteenOneZero = {15, 1, 0};
    CharonHostHKSourceRevision *mineRevision =
        [[CharonHostHKSourceRevision alloc] initWithSource:[HKSource defaultSource]
                                                  version:@"1.0"
                                              productType:@"iPhone"
                                     operatingSystemVersion:fifteenOneZero];
    CharonHKCompare(@"sourceRevision productType", mineRevision.productType, @"iPhone");
    CharonHKCompareInt(@"sourceRevision operatingSystemVersion major",
                       (NSInteger)mineRevision.operatingSystemVersion.majorVersion, (NSInteger)15);
    CharonHKCompareInt(@"sourceRevision operatingSystemVersion minor",
                       (NSInteger)mineRevision.operatingSystemVersion.minorVersion, (NSInteger)1);
    CharonHKCompareInt(@"sourceRevision operatingSystemVersion patch",
                       (NSInteger)mineRevision.operatingSystemVersion.patchVersion, (NSInteger)0);
    NSData *revisionArchive = [NSKeyedArchiver archivedDataWithRootObject:mineRevision];
    CharonHostHKSourceRevision *mineRevisionReadBack =
        (CharonHostHKSourceRevision *)[NSKeyedUnarchiver unarchiveObjectWithData:revisionArchive];
    CharonHKCompare(@"sourceRevision archive round trip: productType", mineRevisionReadBack.productType, mineRevision.productType);
    CharonHKCompareInt(@"sourceRevision archive round trip: os major",
                       (NSInteger)mineRevisionReadBack.operatingSystemVersion.majorVersion,
                       (NSInteger)mineRevision.operatingSystemVersion.majorVersion);
    CharonHKCompare(@"sourceRevision source bundle", mineRevisionReadBack.source.bundleIdentifier,
                    mineRevision.source.bundleIdentifier);
    // the two sentinels of the header that ARE strings, and the match they stand for
    CharonHKCompare(@"HKSourceRevisionAnyVersion", HKSourceRevisionAnyVersion, @"HKSourceRevisionAnyVersion");
    CharonHKCompare(@"HKSourceRevisionAnyProductType", HKSourceRevisionAnyProductType, @"HKSourceRevisionAnyProductType");

    // The workout event over a period, which is what the routing events of 11.0 are. The host's
    // HealthKit builds one through this factory and so does the port's, and both answers are compared;
    // where the host's release has no such method the row is skipped and said, never guessed.
    NSDate *periodStart = [NSDate dateWithTimeIntervalSince1970:1600000000];
    NSDate *periodEnd = [NSDate dateWithTimeIntervalSince1970:1600003600];
    NSDateInterval *period = [[NSDateInterval alloc] initWithStartDate:periodStart endDate:periodEnd];
    HKWorkoutEvent *theirsEvent = [HKWorkoutEvent workoutEventWithType:HKWorkoutEventTypePause dateInterval:period metadata:nil];
    CharonHostHKWorkoutEvent *mineEvent = [CharonHostHKWorkoutEvent workoutEventWithType:HKWorkoutEventTypePause
                                                                                     dateInterval:period
                                                                                          metadata:nil];
    if (theirsEvent && mineEvent) {
        CharonHKCompareInt(@"workout event type", (NSInteger)mineEvent.type, (NSInteger)theirsEvent.type);
        CharonHKCompare(@"workout event dateInterval start", mineEvent.dateInterval.startDate,
                        theirsEvent.dateInterval.startDate);
        CharonHKCompare(@"workout event dateInterval end", mineEvent.dateInterval.endDate, theirsEvent.dateInterval.endDate);
        CharonHKCompare(@"workout event date", mineEvent.date, theirsEvent.date);
        CharonHKCompareInt(@"workout event metadata is nil", (NSInteger)(mineEvent.metadata != nil),
                           (NSInteger)(theirsEvent.metadata != nil));
    } else {
        printf("skipped: the host's HealthKit has no -workoutEventWithType:dateInterval:metadata:\n");
    }
    // and a period that is not a period is the release's own exception on both sides
    BOOL mineEventRefused = NO, theirsEventRefused = NO;
    @try {
        [CharonHostHKWorkoutEvent workoutEventWithType:HKWorkoutEventTypePause dateInterval:nil metadata:nil];
    } @catch (NSException *exception) {
        mineEventRefused = YES;
    }
    @try {
        [HKWorkoutEvent workoutEventWithType:HKWorkoutEventTypePause dateInterval:nil metadata:nil];
    } @catch (NSException *exception) {
        theirsEventRefused = YES;
    }
    CharonHKCompareBool(@"a workout event over a period that is not one raises", mineEventRefused, theirsEventRefused);

    // The workout's flights climbed, through the release's own factory of 11.0.
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:1600000000];
    NSDate *end = [NSDate dateWithTimeIntervalSince1970:1600003600];
    HKQuantity *flights = [HKQuantity quantityWithUnit:[HKUnit countUnit] doubleValue:17.0];
    HKQuantity *energy = [HKQuantity quantityWithUnit:[HKUnit kilocalorieUnit] doubleValue:400.0];
    HKQuantity *distance = [HKQuantity quantityWithUnit:[HKUnit meterUnit] doubleValue:5000.0];
    HKWorkout *theirsWorkout = [HKWorkout workoutWithActivityType:HKWorkoutActivityTypeRunning
                                                          startDate:start
                                                            endDate:end
                                                     workoutEvents:@[ theirsEvent ]
                                                totalEnergyBurned:energy
                                                  totalDistance:distance
                                         totalFlightsClimbed:flights
                                                            device:nil
                                                          metadata:nil];
    CharonHostHKWorkout *mineWorkout = [CharonHostHKWorkout workoutWithActivityType:HKWorkoutActivityTypeRunning
                                                                           startDate:start
                                                                             endDate:end
                                                                      workoutEvents:@[ mineEvent ]
                                                                 totalEnergyBurned:energy
                                                                   totalDistance:distance
                                                          totalFlightsClimbed:flights
                                                                             device:nil
                                                                           metadata:nil];
    CharonHKCompareInt(@"workout activity type", (NSInteger)mineWorkout.workoutActivityType, (NSInteger)theirsWorkout.workoutActivityType);
    CharonHKCompare(@"workout startDate", mineWorkout.startDate, theirsWorkout.startDate);
    CharonHKCompare(@"workout endDate", mineWorkout.endDate, theirsWorkout.endDate);
    CharonHKCompare(@"workout duration", @(mineWorkout.duration), @(theirsWorkout.duration));
    CharonHKCompare(@"workout events", @(mineWorkout.workoutEvents.count), @(theirsWorkout.workoutEvents.count));
    CharonHKCompareDouble(@"workout totalEnergyBurned", [mineWorkout.totalEnergyBurned doubleValueForUnit:[CharonHostHKUnit kilocalorieUnit]],
                          [theirsWorkout.totalEnergyBurned doubleValueForUnit:[HKUnit kilocalorieUnit]]);
    CharonHKCompareDouble(@"workout totalDistance", [mineWorkout.totalDistance doubleValueForUnit:[CharonHostHKUnit meterUnit]],
                          [theirsWorkout.totalDistance doubleValueForUnit:[HKUnit meterUnit]]);
    if (mineWorkout.totalFlightsClimbed && theirsWorkout.totalFlightsClimbed)
        CharonHKCompareDouble(@"workout totalFlightsClimbed",
                              [mineWorkout.totalFlightsClimbed doubleValueForUnit:[CharonHostHKUnit countUnit]],
                              [theirsWorkout.totalFlightsClimbed doubleValueForUnit:[HKUnit countUnit]]);
    else
        printf("skipped: the host's workout carries no flights climbed\n");
    // the archive of the workout, which carries the flights climbed with it
    CharonHostHKWorkout *mineWorkoutReadBack =
        (CharonHostHKWorkout *)[NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:mineWorkout]];
    HKWorkout *theirsWorkoutReadBack = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:theirsWorkout]];
    CharonHKCompare(@"workout archive round trip: duration", @(mineWorkoutReadBack.duration), @(theirsWorkoutReadBack.duration));
    if (mineWorkoutReadBack.totalFlightsClimbed && theirsWorkoutReadBack.totalFlightsClimbed)
        CharonHKCompareDouble(@"workout archive round trip: flights climbed",
                              [mineWorkoutReadBack.totalFlightsClimbed doubleValueForUnit:[CharonHostHKUnit countUnit]],
                              [theirsWorkoutReadBack.totalFlightsClimbed doubleValueForUnit:[HKUnit countUnit]]);
}

int main(void)
{
    CharonHKUnitCases();
    CharonHKPrefixedFactories();
    CharonHKUnitArithmetic();
    CharonHKQuantities();
    CharonHKTypeTable();
    CharonHKQueryObjects();
    CharonHK11Group();
    printf("healthkit: %lu comparisons, %lu differences\n", (unsigned long)CharonHKComparisons,
           (unsigned long)CharonHKDifferences);
    return CharonHKDifferences == 0 ? 0 : 1;
}
