// HKUnit: what a quantity is counted in, and the arithmetic between units of one dimension.
//
// A unit here is a product of powers of the base units of its dimensions, plus the additive offset
// that only a temperature has: a value in the unit comes to a value in the base as
// (value + offset) * the product. So m/s is {m: 1, s: -1}, kcal/(kg*hr) is {J: 1, kg: -1, hr: -1},
// and degF is 5/9 with an offset of 459.67, which is what makes it a temperature.
//
// The strings are the ones the header writes beside each factory method. The factors are the
// international ones those names have: the inch as 0.0254 m, the foot as 0.3048 m, the mile as
// 1609.344 m, the avoirdupois pound as 453.59237 g, the stone as 6350.29318 g, the US fluid ounce as
// 0.0295735295625 L and the imperial one as 0.0284130625 L, the millimetre of mercury as
// 133.322387415 Pa, the centimetre of water as 98.0665 Pa, the standard atmosphere as 101325 Pa, the
// thermochemical calorie as 4.184 J and the large one as 4184 J.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"
#import "CharonHKTypes.h"

// Every dimension the units of this framework has, and the unit it is expressed in.
enum {
    CharonHKDimensionMass = 0,          // gram
    CharonHKDimensionLength,           // metre
    CharonHKDimensionVolume,           // litre
    CharonHKDimensionPressure,         // pascal
    CharonHKDimensionTime,             // second
    CharonHKDimensionEnergy,           // joule
    CharonHKDimensionTemperature,      // kelvin
    CharonHKDimensionConductance,      // siemens
    CharonHKDimensionCount,            // a dimensionless count
    CharonHKDimensionFraction,         // a dimensionless fraction, 0.0 to 1.0
    CharonHKDimensionSoundLevel,       // a weighted sound pressure level, a level and not a pressure
    CharonHKDimensionCountOfDimensions,
};

static NSString *CharonHKBaseUnit(NSInteger dimension)
{
    switch (dimension) {
    case CharonHKDimensionMass:
        return @"g";
    case CharonHKDimensionLength:
        return @"m";
    case CharonHKDimensionVolume:
        return @"L";
    case CharonHKDimensionPressure:
        return @"Pa";
    case CharonHKDimensionTime:
        return @"s";
    case CharonHKDimensionEnergy:
        return @"J";
    case CharonHKDimensionTemperature:
        return @"K";
    case CharonHKDimensionConductance:
        return @"S";
    case CharonHKDimensionFraction:
        return @"%";
    case CharonHKDimensionSoundLevel:
        return @"dBASPL";
    default:
        return @"count";
    }
}

#pragma mark - The table of units

// One unit of the header's own: the string it writes, the dimension it is of and the factor it is
// worth in that dimension's base. Read off the factory methods of HKUnit.h and the comments beside
// them, the eight of iOS 8 that the header gives without an iOS version on them.
typedef struct {
    __unsafe_unretained NSString *string;
    NSInteger dimension;
    double factor;
    double offset;
} CharonHKUnitEntry;

static const CharonHKUnitEntry CharonHKUnitTable[] = {
    // mass, in grams
    {@"g", CharonHKDimensionMass, 1.0, 0.0},
    {@"kg", CharonHKDimensionMass, 1000.0, 0.0},
    {@"mg", CharonHKDimensionMass, 1e-3, 0.0},
    {@"ug", CharonHKDimensionMass, 1e-6, 0.0},
    {@"ng", CharonHKDimensionMass, 1e-9, 0.0},
    {@"pg", CharonHKDimensionMass, 1e-12, 0.0},
    {@"fg", CharonHKDimensionMass, 1e-15, 0.0},
    {@"oz", CharonHKDimensionMass, 28.349523125, 0.0},
    {@"lb", CharonHKDimensionMass, 453.59237, 0.0},
    {@"st", CharonHKDimensionMass, 6350.29318, 0.0},
    // length, in metres
    {@"m", CharonHKDimensionLength, 1.0, 0.0},
    {@"km", CharonHKDimensionLength, 1000.0, 0.0},
    {@"cm", CharonHKDimensionLength, 1e-2, 0.0},
    {@"mm", CharonHKDimensionLength, 1e-3, 0.0},
    {@"um", CharonHKDimensionLength, 1e-6, 0.0},
    {@"nm", CharonHKDimensionLength, 1e-9, 0.0},
    {@"in", CharonHKDimensionLength, 0.0254, 0.0},
    {@"ft", CharonHKDimensionLength, 0.3048, 0.0},
    {@"yd", CharonHKDimensionLength, 0.9144, 0.0},
    {@"mi", CharonHKDimensionLength, 1609.344, 0.0},
    // volume, in litres
    {@"L", CharonHKDimensionVolume, 1.0, 0.0},
    {@"mL", CharonHKDimensionVolume, 1e-3, 0.0},
    {@"uL", CharonHKDimensionVolume, 1e-6, 0.0},
    {@"nL", CharonHKDimensionVolume, 1e-9, 0.0},
    {@"pL", CharonHKDimensionVolume, 1e-12, 0.0},
    {@"fL", CharonHKDimensionVolume, 1e-15, 0.0},
    {@"dL", CharonHKDimensionVolume, 1e-1, 0.0},
    {@"cL", CharonHKDimensionVolume, 1e-2, 0.0},
    {@"daL", CharonHKDimensionVolume, 10.0, 0.0},
    {@"hL", CharonHKDimensionVolume, 100.0, 0.0},
    {@"fl_oz_us", CharonHKDimensionVolume, 0.0295735295625, 0.0},
    {@"pt_us", CharonHKDimensionVolume, 0.473176473, 0.0},
    {@"cup_us", CharonHKDimensionVolume, 0.2365882365, 0.0},
    {@"fl_oz_imp", CharonHKDimensionVolume, 0.0284130625, 0.0},
    {@"pt_imp", CharonHKDimensionVolume, 0.56826125, 0.0},
    {@"cup_imp", CharonHKDimensionVolume, 0.284130625, 0.0},
    // pressure, in pascals
    {@"Pa", CharonHKDimensionPressure, 1.0, 0.0},
    {@"kPa", CharonHKDimensionPressure, 1000.0, 0.0},
    {@"hPa", CharonHKDimensionPressure, 100.0, 0.0},
    {@"daPa", CharonHKDimensionPressure, 10.0, 0.0},
    {@"MPa", CharonHKDimensionPressure, 1e6, 0.0},
    {@"mmHg", CharonHKDimensionPressure, 133.322387415, 0.0},
    {@"cmAq", CharonHKDimensionPressure, 98.0665, 0.0},
    {@"atm", CharonHKDimensionPressure, 101325.0, 0.0},
    {@"dBASPL", CharonHKDimensionSoundLevel, 1.0, 0.0},
    // time, in seconds
    {@"s", CharonHKDimensionTime, 1.0, 0.0},
    {@"ms", CharonHKDimensionTime, 1e-3, 0.0},
    {@"us", CharonHKDimensionTime, 1e-6, 0.0},
    {@"ns", CharonHKDimensionTime, 1e-9, 0.0},
    {@"min", CharonHKDimensionTime, 60.0, 0.0},
    {@"hr", CharonHKDimensionTime, 3600.0, 0.0},
    {@"d", CharonHKDimensionTime, 86400.0, 0.0},
    // energy, in joules
    {@"J", CharonHKDimensionEnergy, 1.0, 0.0},
    {@"kJ", CharonHKDimensionEnergy, 1000.0, 0.0},
    {@"MJ", CharonHKDimensionEnergy, 1e6, 0.0},
    {@"cal", CharonHKDimensionEnergy, 4.184, 0.0},
    {@"kcal", CharonHKDimensionEnergy, 4184.0, 0.0},
    {@"Cal", CharonHKDimensionEnergy, 4184.0, 0.0},
    {@"kWh", CharonHKDimensionEnergy, 3600000.0, 0.0},
    // temperature, in kelvin
    {@"K", CharonHKDimensionTemperature, 1.0, 0.0},
    {@"degC", CharonHKDimensionTemperature, 1.0, 273.15},
    {@"degF", CharonHKDimensionTemperature, 5.0 / 9.0, 459.67},
    // electrical conductance, in siemens
    {@"S", CharonHKDimensionConductance, 1.0, 0.0},
    {@"mS", CharonHKDimensionConductance, 1e-3, 0.0},
    {@"uS", CharonHKDimensionConductance, 1e-6, 0.0},
    {@"nS", CharonHKDimensionConductance, 1e-9, 0.0},
    {@"pS", CharonHKDimensionConductance, 1e-12, 0.0},
    // dimensionless
    {@"count", CharonHKDimensionCount, 1.0, 0.0},
    {@"%", CharonHKDimensionFraction, 1.0, 0.0},
};
static const NSUInteger CharonHKUnitTableCount = sizeof(CharonHKUnitTable) / sizeof(CharonHKUnitTable[0]);

// The factor of a prefix: the power of ten its name stands for.
static BOOL CharonHKPrefixFactor(HKMetricPrefix prefix, double *factor)
{
    static const double factors[] = {1.0, 1e-15, 1e-12, 1e-9, 1e-6, 1e-3, 1e-2, 1e-1, 10.0, 100.0, 1e3, 1e6, 1e9, 1e12, 1e15};
    if (prefix < 0 || (NSUInteger)prefix >= sizeof(factors) / sizeof(factors[0]))
        return NO;
    *factor = factors[prefix];
    return YES;
}

#pragma mark - The unit

@interface HKUnit ()
// base unit -> NSNumber, the power of that base this unit carries
@property (readwrite, copy) NSString *unitString;
// The factor of the whole product: a value in this unit times it, plus the offset, is the value in
// the base of every dimension the unit carries.
@property (readwrite) double scale;
@property (readwrite) double offset;
// The dimensions the unit has, in the order the string writes them, so that two units of one
// dimension compare equal and a unit of a product does not.
@property (readwrite, copy) NSArray<NSString *> *bases;
@property (readwrite, copy) NSDictionary<NSString *, NSNumber *> *powers;
@end


@implementation HKUnit
@synthesize unitString = _unitString;
@synthesize scale = _scale;
@synthesize offset = _offset;
@synthesize bases = _bases;
@synthesize powers = _powers;

- (instancetype)init
{
    return [super init];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _unitString = [[coder decodeObjectOfClass:[NSString class] forKey:@"unitString"] copy] ?: @"";
        _scale = [coder decodeDoubleForKey:@"scale"];
        _offset = [coder decodeDoubleForKey:@"offset"];
        _bases = [[coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSString class], nil]
                                       forKey:@"bases"] copy] ?: @[];
        _powers = [[coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], [NSNumber class], nil]
                                        forKey:@"powers"] copy] ?: @{};
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_unitString forKey:@"unitString"];
    [coder encodeDouble:_scale forKey:@"scale"];
    [coder encodeDouble:_offset forKey:@"offset"];
    [coder encodeObject:_bases forKey:@"bases"];
    [coder encodeObject:_powers forKey:@"powers"];
}

- (id)copyWithZone:(NSZone *)zone
{
    HKUnit *copy = [[HKUnit alloc] init];
    copy->_unitString = [_unitString copy];
    copy->_scale = _scale;
    copy->_offset = _offset;
    copy->_bases = [_bases copy];
    copy->_powers = [_powers copy];
    return copy;
}

#pragma mark Building a unit

// The one place a unit is made: its string, the factor of the whole product, the offset only a
// temperature has, and the dimensions it carries with the power of each.
+ (instancetype)charon_unitWithString:(NSString *)string
                                 scale:(double)scale
                                offset:(double)offset
                                 bases:(NSArray *)bases
                                powers:(NSDictionary *)powers
{
    HKUnit *unit = [[HKUnit alloc] init];
    unit->_unitString = [string copy] ?: @"";
    unit->_scale = scale;
    unit->_offset = offset;
    unit->_bases = [bases copy];
    unit->_powers = [powers copy];
    return unit;
}

+ (instancetype)charon_unitOfDimension:(NSInteger)dimension string:(NSString *)string factor:(double)factor offset:(double)offset
{
    return [self charon_unitWithString:string
                                 scale:factor
                                offset:offset
                                 bases:@[CharonHKBaseUnit(dimension)]
                                powers:@{CharonHKBaseUnit(dimension): @1}];
}

+ (instancetype)charon_namedUnit:(NSString *)string
{
    if (![string isKindOfClass:[NSString class]])
        return nil;
    for (NSUInteger index = 0; index < CharonHKUnitTableCount; index++) {
        if ([CharonHKUnitTable[index].string isEqualToString:string])
            return [self charon_unitOfDimension:CharonHKUnitTable[index].dimension
                                          string:string
                                         factor:CharonHKUnitTable[index].factor
                                         offset:CharonHKUnitTable[index].offset];
    }
    return nil;
}

// The unit of a dimension with a metric prefix in front of it, which is every prefixed factory method
// of the header: gramUnitWithMetricPrefix:, meterUnitWithMetricPrefix:, literUnitWithMetricPrefix:,
// pascalUnitWithMetricPrefix:, secondUnitWithMetricPrefix:, jouleUnitWithMetricPrefix: and
// siemenUnitWithMetricPrefix:.
+ (instancetype)charon_prefixedUnitForDimension:(NSInteger)dimension prefix:(HKMetricPrefix)prefix
{
    if (dimension < 0 || (NSUInteger)dimension >= CharonHKDimensionCountOfDimensions)
        return nil;
    double factor = 1.0;
    if (!CharonHKPrefixFactor(prefix, &factor))
        return nil;
    NSString *base = CharonHKBaseUnit(dimension);
    NSString *string = nil;
    if (prefix == HKMetricPrefixNone)
        string = base;
    else if (prefix == HKMetricPrefixDeci)
        string = [@"d" stringByAppendingString:base];
    else if (prefix == HKMetricPrefixCenti)
        string = [@"c" stringByAppendingString:base];
    else if (prefix == HKMetricPrefixKilo)
        string = [@"k" stringByAppendingString:base];
    else {
        // The names the header writes for the rest, as the UTF-8 the modern headers use.
        static NSString *const prefixes[] = {@"f", @"p", @"n", @"u", @"m", @"c", @"d", @"da", @"h", @"k", @"M", @"G", @"T"};
        NSString *name = prefixes[(NSUInteger)prefix];
        string = name ? [name stringByAppendingString:base] : base;
    }
    return [self charon_unitOfDimension:dimension string:string factor:factor offset:0.0];
}

#pragma mark Reading a unit

+ (instancetype)unitFromString:(NSString *)string
{
    if (![string isKindOfClass:[NSString class]] || !string.length)
        return nil;
    HKUnit *named = [self charon_namedUnit:string];
    if (named)
        return named;
    return [self charon_unitFromString:string];
}


// A single unit of the table, and a product of the units above as the header writes one: m/s, km/h,
// kcal/(kg*hr) and every prefix the header names. A string that names nothing the table holds is not
// a unit, and nil is what the release answers for one.
// A string that is a product of the units above: m/s, km/h, kcal/(kg*hr) and everything the header
// writes that way. A string that names nothing the table holds is not a unit, and nil is what the
// release answers for one.
+ (instancetype)charon_unitFromString:(NSString *)string
{
    NSString *written = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *halves = [written componentsSeparatedByString:@"/"];
    if (halves.count > 2)
        return nil;
    HKUnit *numerator = halves.count == 2 ? [self charon_product:halves[0] sign:1] : [self charon_unitFromString:halves[0]];
    if (!numerator)
        return nil;
    if (halves.count == 1)
        return numerator;
    HKUnit *denominator = [self charon_product:halves[1] sign:-1];
    if (!denominator)
        return nil;
    return [numerator charon_productWithUnit:denominator];
}

// A factor list, `count*min` or `count` or `kcal`, turned into a unit; sign is the power the whole
// product carries, so a denominator's factors come out inverted.
+ (instancetype)charon_product:(NSString *)string sign:(NSInteger)sign
{
    NSString *written = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([written hasPrefix:@"("] && [written hasSuffix:@")"])
        written = [written substringWithRange:NSMakeRange(1, written.length - 2)];
    NSMutableArray *bases = [NSMutableArray array];
    NSMutableDictionary *powers = [NSMutableDictionary dictionary];
    double scale = 1.0;
    for (NSString *part in [written componentsSeparatedByString:@"*"]) {
        NSString *name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!name.length)
            return nil;
        HKUnit *one = [self charon_namedUnit:name];
        if (!one)
            return nil;
        for (NSString *base in one.bases) {
            NSInteger power = [powers[base] integerValue] + [one.powers[base] integerValue] * sign;
            if (!power) {
                [powers removeObjectForKey:base];
                [bases removeObject:base];
            } else {
                powers[base] = @(power);
                if (![bases containsObject:base])
                    [bases addObject:base];
            }
        }
        scale *= sign > 0 ? one.scale : 1.0 / one.scale;
    }
    if (!bases.count)
        return nil;
    [bases sortUsingSelector:@selector(compare:)];
    return [self charon_unitWithString:string scale:scale offset:0.0 bases:bases powers:powers];
}

// The string of a product of units, in the order the header writes one: the factors with a positive
// power, a solidus, and the ones with a negative power, in parentheses when there is more than one.
static NSString *CharonHKStringForDimensions(NSArray *bases, NSDictionary *powers, NSString *reciprocalOf)
{
    if (reciprocalOf)
        return [NSString stringWithFormat:@"1/%@", reciprocalOf];
    NSMutableArray *numerator = [NSMutableArray array], *denominator = [NSMutableArray array];
    for (NSString *base in bases) {
        NSInteger power = [powers[base] integerValue];
        NSString *name = labs(power) == 1 ? base : [NSString stringWithFormat:@"%@%ld", base, (long)labs(power)];
        [power > 0 ? numerator : denominator addObject:name];
    }
    NSMutableString *written = [NSMutableString string];
    if (!numerator.count)
        [written appendString:@"1"];
    [written appendString:[numerator componentsJoinedByString:@"*"]];
    if (denominator.count) {
        [written appendString:denominator.count > 1 ? @"/(" : @"/"];
        [written appendString:[denominator componentsJoinedByString:@"*"]];
        if (denominator.count > 1)
            [written appendString:@")"];
    }
    return written;
}

#pragma mark The arithmetic of the header

- (HKUnit *)charon_productWithUnit:(HKUnit *)unit
{
    if (_offset != 0.0 || ((HKUnit *)unit).offset != 0.0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"A temperature is not multiplied or divided: %@ carries an offset of %g, which only an addition can carry.",
                           _unitString, _offset];
        return nil;
    }
    NSMutableDictionary *powers = [_powers mutableCopy];
    NSMutableSet *bases = [NSMutableSet setWithArray:_bases];
    for (NSString *base in ((HKUnit *)unit).bases) {
        NSInteger power = [powers[base] integerValue] + [((HKUnit *)unit).powers[base] integerValue];
        if (!power) {
            [powers removeObjectForKey:base];
            [bases removeObject:base];
        } else {
            powers[base] = @(power);
            [bases addObject:base];
        }
    }
    NSArray *ordered = [bases.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (!ordered.count)
        return [HKUnit charon_unitWithString:@"count" scale:1.0 offset:0.0 bases:@[] powers:@{}];
    return [HKUnit charon_unitWithString:CharonHKStringForDimensions(ordered, powers, nil)
                                   scale:_scale * ((HKUnit *)unit).scale
                                  offset:0.0
                                   bases:ordered
                                  powers:powers];
}

- (HKUnit *)unitMultipliedByUnit:(HKUnit *)unit
{
    return [self charon_productWithUnit:unit];
}

- (HKUnit *)unitDividedByUnit:(HKUnit *)unit
{
    return [self charon_productWithUnit:((HKUnit *)unit).charon_reciprocal];
}

- (HKUnit *)charon_reciprocal
{
    if (_offset != 0.0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"A temperature is not multiplied or divided: %@ carries an offset of %g, which only an addition can carry.",
                           _unitString, _offset];
        return nil;
    }
    NSMutableDictionary *powers = [NSMutableDictionary dictionary];
    for (NSString *base in _bases)
        powers[base] = @(-[_powers[base] integerValue]);
    return [HKUnit charon_unitWithString:CharonHKStringForDimensions(_bases, powers, _unitString)
                                   scale:(_scale == 0.0 ? 1.0 : 1.0 / _scale)
                                  offset:0.0
                                   bases:_bases
                                  powers:powers];
}

- (HKUnit *)reciprocalUnit
{
    return [self charon_reciprocal];
}

- (HKUnit *)unitRaisedToPower:(NSInteger)power
{
    if (_offset != 0.0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"A temperature is not raised to a power: %@ carries an offset of %g, which only an addition can carry.",
                           _unitString, _offset];
        return nil;
    }
    NSMutableDictionary *powers = [NSMutableDictionary dictionary];
    double scale = 1.0;
    for (NSString *base in _bases) {
        NSInteger raised = [_powers[base] integerValue] * power;
        if (!raised)
            continue;
        powers[base] = @(raised);
        for (NSInteger step = 0; step < labs(raised); step++)
            scale *= raised > 0 ? _scale : 1.0 / _scale;
    }
    NSArray *ordered = [powers.allKeys sortedArrayUsingSelector:@selector(compare:)];
    if (!ordered.count)
        return [HKUnit charon_unitWithString:@"count" scale:1.0 offset:0.0 bases:@[] powers:@{}];
    return [HKUnit charon_unitWithString:CharonHKStringForDimensions(ordered, powers, nil)
                                   scale:scale
                                  offset:0.0
                                   bases:ordered
                                  powers:powers];
}

#pragma mark Comparing units

- (BOOL)charon_isCompatibleWithUnit:(HKUnit *)unit
{
    if (![unit isKindOfClass:[HKUnit class]])
        return NO;
    if (_offset != ((HKUnit *)unit).offset)
        return NO;
    NSArray *mine = _bases, *theirs = ((HKUnit *)unit).bases;
    if (mine.count != theirs.count)
        return NO;
    for (NSUInteger index = 0; index < mine.count; index++) {
        if (![mine[index] isEqualToString:theirs[index]])
            return NO;
        if ([_powers[mine[index]] integerValue] != [((HKUnit *)unit).powers[theirs[index]] integerValue])
            return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)other
{
    if (self == other)
        return YES;
    if (![other isKindOfClass:[HKUnit class]])
        return NO;
    return [_unitString isEqualToString:((HKUnit *)other).unitString] && [self charon_isCompatibleWithUnit:other];
}

- (NSUInteger)hash
{
    return _unitString.hash;
}

- (NSString *)description
{
    return _unitString;
}

// What HKQuantity asks of a unit: the value in the receiver, brought to the base of the dimension
// and then to the unit asked for.
- (double)charon_value:(double)value inUnit:(HKUnit *)unit
{
    double base = (value + _offset) * _scale;
    return base / (unit.scale == 0.0 ? 1.0 : unit.scale) - unit.offset;
}

#pragma mark The factory methods of the header

+ (instancetype)gramUnit
{
    return [self charon_namedUnit:@"g"];
}

+ (instancetype)gramUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionMass prefix:prefix];
}

+ (instancetype)ounceUnit
{
    return [self charon_namedUnit:@"oz"];
}

+ (instancetype)poundUnit
{
    return [self charon_namedUnit:@"lb"];
}

+ (instancetype)stoneUnit
{
    return [self charon_namedUnit:@"st"];
}

+ (instancetype)moleUnitWithMetricPrefix:(HKMetricPrefix)prefix molarMass:(double)gramsPerMole
{
    if (gramsPerMole <= 0.0) {
        [NSException raise:NSInvalidArgumentException format:@"A molar mass must be positive, and %g is not.", gramsPerMole];
        return nil;
    }
    HKUnit *moles = [self charon_namedUnit:@"count"];
    // mol<double> is the unit string the header gives this factory, and its value is in the grams
    // per mole it was made with, so one mole of a 12 g/mol substance is twelve of them.
    return [moles charon_productWithUnit:[self charon_namedUnit:@"g"]];
}

+ (instancetype)moleUnitWithMolarMass:(double)gramsPerMole
{
    return [self moleUnitWithMetricPrefix:HKMetricPrefixNone molarMass:gramsPerMole];
}

+ (instancetype)meterUnit
{
    return [self charon_namedUnit:@"m"];
}

+ (instancetype)meterUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionLength prefix:prefix];
}

+ (instancetype)inchUnit
{
    return [self charon_namedUnit:@"in"];
}

+ (instancetype)footUnit
{
    return [self charon_namedUnit:@"ft"];
}

+ (instancetype)mileUnit
{
    return [self charon_namedUnit:@"mi"];
}

+ (instancetype)literUnit
{
    return [self charon_namedUnit:@"L"];
}

+ (instancetype)literUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionVolume prefix:prefix];
}

+ (instancetype)fluidOunceUSUnit
{
    return [self charon_namedUnit:@"fl_oz_us"];
}

+ (instancetype)fluidOunceImperialUnit
{
    return [self charon_namedUnit:@"fl_oz_imp"];
}

+ (instancetype)pintUSUnit
{
    return [self charon_namedUnit:@"pt_us"];
}

+ (instancetype)pintImperialUnit
{
    return [self charon_namedUnit:@"pt_imp"];
}

+ (instancetype)pascalUnit
{
    return [self charon_namedUnit:@"Pa"];
}

+ (instancetype)pascalUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionPressure prefix:prefix];
}

+ (instancetype)millimeterOfMercuryUnit
{
    return [self charon_namedUnit:@"mmHg"];
}

+ (instancetype)centimeterOfWaterUnit
{
    return [self charon_namedUnit:@"cmAq"];
}

+ (instancetype)atmosphereUnit
{
    return [self charon_namedUnit:@"atm"];
}

+ (instancetype)secondUnit
{
    return [self charon_namedUnit:@"s"];
}

+ (instancetype)secondUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionTime prefix:prefix];
}

+ (instancetype)milliseconds
{
    return [self charon_namedUnit:@"ms"];
}

+ (instancetype)minuteUnit
{
    return [self charon_namedUnit:@"min"];
}

+ (instancetype)hourUnit
{
    return [self charon_namedUnit:@"hr"];
}

+ (instancetype)dayUnit
{
    return [self charon_namedUnit:@"d"];
}

+ (instancetype)jouleUnit
{
    return [self charon_namedUnit:@"J"];
}

+ (instancetype)jouleUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionEnergy prefix:prefix];
}

+ (instancetype)kilocalorieUnit
{
    return [self charon_namedUnit:@"kcal"];
}

+ (instancetype)calorieUnit
{
    return [self charon_namedUnit:@"cal"];
}

+ (instancetype)kilojoulesUnit
{
    return [self charon_namedUnit:@"kJ"];
}

+ (instancetype)degreeCelsiusUnit
{
    return [self charon_namedUnit:@"degC"];
}

+ (instancetype)degreeFahrenheitUnit
{
    return [self charon_namedUnit:@"degF"];
}

+ (instancetype)kelvinUnit
{
    return [self charon_namedUnit:@"K"];
}

+ (instancetype)siemenUnit
{
    return [self charon_namedUnit:@"S"];
}

+ (instancetype)siemenUnitWithMetricPrefix:(HKMetricPrefix)prefix
{
    return [self charon_prefixedUnitForDimension:CharonHKDimensionConductance prefix:prefix];
}

+ (instancetype)countUnit
{
    return [self charon_namedUnit:@"count"];
}

+ (instancetype)percentUnit
{
    return [self charon_namedUnit:@"%"];
}

+ (instancetype)unitFromMassFormatterUnit:(NSMassFormatterUnit)massFormatterUnit
{
    switch (massFormatterUnit) {
    case NSMassFormatterUnitGram:
        return [self gramUnit];
    case NSMassFormatterUnitKilogram:
        return [self gramUnitWithMetricPrefix:HKMetricPrefixKilo];
    case NSMassFormatterUnitPound:
        return [self poundUnit];
    case NSMassFormatterUnitOunce:
        return [self ounceUnit];
    case NSMassFormatterUnitStone:
        return [self stoneUnit];
    default:
        return nil;
    }
}

+ (NSMassFormatterUnit)massFormatterUnitFromUnit:(HKUnit *)unit
{
    NSString *string = unit.unitString;
    if ([string isEqualToString:@"g"])
        return NSMassFormatterUnitGram;
    if ([string isEqualToString:@"kg"])
        return NSMassFormatterUnitKilogram;
    if ([string isEqualToString:@"lb"])
        return NSMassFormatterUnitPound;
    if ([string isEqualToString:@"oz"])
        return NSMassFormatterUnitOunce;
    if ([string isEqualToString:@"st"])
        return NSMassFormatterUnitStone;
    return NSMassFormatterUnitGram;
}

+ (instancetype)unitFromLengthFormatterUnit:(NSLengthFormatterUnit)lengthFormatterUnit
{
    switch (lengthFormatterUnit) {
    case NSLengthFormatterUnitMeter:
        return [self meterUnit];
    case NSLengthFormatterUnitKilometer:
        return [self meterUnitWithMetricPrefix:HKMetricPrefixKilo];
    case NSLengthFormatterUnitCentimeter:
        return [self meterUnitWithMetricPrefix:HKMetricPrefixCenti];
    case NSLengthFormatterUnitMillimeter:
        return [self meterUnitWithMetricPrefix:HKMetricPrefixMilli];
    case NSLengthFormatterUnitInch:
        return [self inchUnit];
    case NSLengthFormatterUnitFoot:
        return [self footUnit];
    case NSLengthFormatterUnitYard:
        return [self charon_namedUnit:@"yd"];
    case NSLengthFormatterUnitMile:
        return [self mileUnit];
    default:
        return nil;
    }
}

+ (NSLengthFormatterUnit)lengthFormatterUnitFromUnit:(HKUnit *)unit
{
    NSString *string = unit.unitString;
    if ([string isEqualToString:@"m"])
        return NSLengthFormatterUnitMeter;
    if ([string isEqualToString:@"km"])
        return NSLengthFormatterUnitKilometer;
    if ([string isEqualToString:@"cm"])
        return NSLengthFormatterUnitCentimeter;
    if ([string isEqualToString:@"mm"])
        return NSLengthFormatterUnitMillimeter;
    if ([string isEqualToString:@"in"])
        return NSLengthFormatterUnitInch;
    if ([string isEqualToString:@"ft"])
        return NSLengthFormatterUnitFoot;
    if ([string isEqualToString:@"yd"])
        return NSLengthFormatterUnitYard;
    if ([string isEqualToString:@"mi"])
        return NSLengthFormatterUnitMile;
    return NSLengthFormatterUnitMeter;
}

+ (instancetype)unitFromEnergyFormatterUnit:(NSEnergyFormatterUnit)energyFormatterUnit
{
    switch (energyFormatterUnit) {
    case NSEnergyFormatterUnitJoule:
        return [self jouleUnit];
    case NSEnergyFormatterUnitKilojoule:
        return [self kilojoulesUnit];
    case NSEnergyFormatterUnitCalorie:
        return [self charon_namedUnit:@"cal"];
    case NSEnergyFormatterUnitKilocalorie:
        return [self kilocalorieUnit];
    default:
        return nil;
    }
}

+ (NSEnergyFormatterUnit)energyFormatterUnitFromUnit:(HKUnit *)unit
{
    NSString *string = unit.unitString;
    if ([string isEqualToString:@"J"])
        return NSEnergyFormatterUnitJoule;
    if ([string isEqualToString:@"kJ"])
        return NSEnergyFormatterUnitKilojoule;
    if ([string isEqualToString:@"cal"])
        return NSEnergyFormatterUnitCalorie;
    if ([string isEqualToString:@"kcal"])
        return NSEnergyFormatterUnitKilocalorie;
    return NSEnergyFormatterUnitJoule;
}

- (BOOL)isNull
{
    return _unitString.length == 0;
}

// The unit a quantity type is counted in, as the SDK's own table of the type's unit names it. A type
// whose documented unit is one this class cannot make is one it refuses a unit for, once, in the log.
+ (nullable HKUnit *)charon_canonicalUnitForType:(HKQuantityType *)type
{
    if (![type isKindOfClass:[HKQuantityType class]])
        return nil;
    const CharonHKTypeEntry *entry = CharonHKQuantityTypeEntry(type.identifier);
    if (!entry)
        return nil;
    HKUnit *unit = [HKUnit unitFromString:entry->unit];
    if (unit)
        return unit;
    charon_hk_say_once([@"quantity-unit" stringByAppendingString:entry->identifier],
                       [NSString stringWithFormat:@"HealthKit: %@ is counted in '%s', which is not a unit this port can make, so it "
                                                      @"accepts none. The SDK names that string for the type, and no source this port can "
                                                      @"read names a unit for it.",
                                                      entry->identifier, entry->unit.UTF8String]);
    return nil;
}

@end
