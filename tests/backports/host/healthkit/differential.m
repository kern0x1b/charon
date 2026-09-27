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

#import "CharonHKTypes.h"

// The port's own classes, under the names run.sh's -D flags give them. The declarations are this
// file's own and hold only what it asks of them: the port's headers declare the same classes under
// their real names, which the system's HealthKit also declares, so they cannot both be seen at once.
@interface CharonHostHKUnit : NSObject
+ (instancetype)unitFromString:(NSString *)string;
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

@interface CharonHostHKObjectType : NSObject
+ (nullable HKQuantityType *)quantityTypeForIdentifier:(NSString *)identifier;
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
                        @"secondUnit", @"milliseconds", @"minuteUnit", @"hourUnit", @"dayUnit", @"jouleUnit",
                        @"kilocalorieUnit", @"calorieUnit", @"degreeCelsiusUnit",
                        @"degreeFahrenheitUnit", @"kelvinUnit", @"siemenUnit", @"countUnit",
                        @"percentUnit" ];
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

int main(void)
{
    CharonHKUnitCases();
    CharonHKPrefixedFactories();
    CharonHKUnitArithmetic();
    CharonHKQuantities();
    CharonHKTypeTable();
    printf("healthkit: %lu comparisons, %lu differences\n", (unsigned long)CharonHKComparisons,
           (unsigned long)CharonHKDifferences);
    return CharonHKDifferences == 0 ? 0 : 1;
}
