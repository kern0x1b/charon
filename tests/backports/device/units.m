#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "check.h"

static NSString *image_of(Class cls)
{
    Dl_info info;
    return dladdr((__bridge const void *)cls, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static BOOL close_enough(double actual, double expected)
{
    return fabs(actual - expected) <= fabs(expected) * 1e-12;
}

int main(void)
{
    @autoreleasepool {
        for (NSString *name in @[@"NSUnit", @"NSDimension", @"NSUnitConverterLinear", @"NSUnitLength",
                                 @"NSMeasurement", @"NSDateInterval"])
            CHECK_EQUAL(image_of(NSClassFromString(name)), @"libFoundationBackports.dylib",
                        [name stringByAppendingString:@" comes from the backports library"].UTF8String);

        CHECK_EQUAL([NSUnitLength baseUnit].symbol, @"m", "the base unit of length is the metre");
        CHECK_EQUAL([NSUnitMass baseUnit].symbol, @"kg", "the base unit of mass is the kilogramme");
        CHECK_EQUAL([NSUnitTemperature baseUnit].symbol, @"K", "the base unit of temperature is the kelvin");
        CHECK([NSUnitLength meters] == [NSUnitLength meters], "a unit is a singleton");
        CHECK_EQUAL([NSUnitLength micrometers].symbol, @"µm", "a symbol outside ASCII survives");
        CHECK_EQUAL([NSUnitElectricResistance ohms].symbol, @"Ω", "the ohm keeps its sign");
        CHECK_EQUAL([NSUnitArea squareKilometers].symbol, @"km²", "a squared symbol keeps its exponent");

        CHECK(close_enough([[NSUnitLength miles].converter baseUnitValueFromValue:1], 1609.344),
              "a mile is 1609.344 metres");
        CHECK(close_enough([[NSUnitMass stones].converter baseUnitValueFromValue:1], 6.35029),
              "a stone is 6.35029 kilogrammes, not the reciprocal iOS 10 used");
        CHECK(close_enough([[NSUnitTemperature celsius].converter baseUnitValueFromValue:0], 273.15),
              "zero celsius is 273.15 kelvin");
        CHECK(close_enough([[NSUnitTemperature fahrenheit].converter valueFromBaseUnitValue:273.15], 32),
              "zero celsius is 32 fahrenheit");
        CHECK(close_enough([[NSUnitFuelEfficiency milesPerGallon].converter baseUnitValueFromValue:30], 7.8405),
              "thirty miles per gallon is 7.8405 litres per 100 km");

        NSMeasurement *twoKilometres = [[NSMeasurement alloc] initWithDoubleValue:2 unit:[NSUnitLength kilometers]];
        NSMeasurement *fiveHundredMetres = [[NSMeasurement alloc] initWithDoubleValue:500 unit:[NSUnitLength meters]];
        CHECK([twoKilometres measurementByConvertingToUnit:[NSUnitLength meters]].doubleValue == 2000,
              "two kilometres are two thousand metres");
        NSMeasurement *sum = [twoKilometres measurementByAddingMeasurement:fiveHundredMetres];
        CHECK(sum.doubleValue == 2500 && [sum.unit isEqual:[NSUnitLength meters]],
              "differing units are added in the base unit");
        NSMeasurement *plain = [twoKilometres measurementByAddingMeasurement:
                                   [[NSMeasurement alloc] initWithDoubleValue:3 unit:[NSUnitLength kilometers]]];
        CHECK(plain.doubleValue == 5 && [plain.unit isEqual:[NSUnitLength kilometers]],
              "equal units are added in that unit");
        CHECK(![twoKilometres isEqual:[[NSMeasurement alloc] initWithDoubleValue:2000 unit:[NSUnitLength meters]]],
              "a measurement is not equal to the same length in another unit");
        CHECK(![twoKilometres canBeConvertedToUnit:[NSUnitTemperature celsius]],
              "a length cannot be converted to a temperature");

        @try {
            [twoKilometres measurementByAddingMeasurement:
                [[NSMeasurement alloc] initWithDoubleValue:1 unit:[NSUnitTemperature celsius]]];
            CHECK(NO, "adding differing unit types raises");
        } @catch (NSException *exception) {
            CHECK([exception.name isEqual:NSInvalidArgumentException]
                  && [exception.reason hasPrefix:@"Cannot add measurements of differing unit types!"],
                  "adding differing unit types raises");
        }

        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:twoKilometres];
        NSMeasurement *back = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
        CHECK_EQUAL(back, twoKilometres, "a measurement survives an archive");
        CHECK_EQUAL(back.unit.symbol, @"km", "the unit survives an archive");

        NSDate *epoch = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
        NSDateInterval *ten = [[NSDateInterval alloc] initWithStartDate:epoch duration:10];
        NSDateInterval *overlapping = [[NSDateInterval alloc] initWithStartDate:[epoch dateByAddingTimeInterval:5]
                                                                      duration:10];
        CHECK(ten.endDate.timeIntervalSinceReferenceDate == 10, "the end date is the start plus the duration");
        CHECK([ten containsDate:epoch] && [ten containsDate:[epoch dateByAddingTimeInterval:10]],
              "the interval is closed at both ends");
        CHECK(![ten containsDate:[epoch dateByAddingTimeInterval:10.5]], "a date past the end is not contained");
        CHECK([ten intersectsDateInterval:overlapping], "overlapping intervals intersect");
        NSDateInterval *cut = [ten intersectionWithDateInterval:overlapping];
        CHECK(cut.startDate.timeIntervalSinceReferenceDate == 5 && cut.duration == 5,
              "the intersection is the later start to the earlier end");
        CHECK([ten intersectionWithDateInterval:
                  [[NSDateInterval alloc] initWithStartDate:[epoch dateByAddingTimeInterval:20] duration:1]] == nil,
              "intervals that do not meet intersect in nil");
        CHECK([ten compare:overlapping] == NSOrderedAscending, "an earlier interval orders first");
        NSDateInterval *backAgain = [NSKeyedUnarchiver unarchiveObjectWithData:
                                        [NSKeyedArchiver archivedDataWithRootObject:ten]];
        CHECK_EQUAL(backAgain, ten, "an interval survives an archive");

        printf("%d checks, %d failures\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
