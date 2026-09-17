#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int failures;
static int checks;

static void fail(NSString *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    printf("FAIL %s\n", text.UTF8String);
    failures++;
}

static void same_double(double ours, double theirs, NSString *what)
{
    checks++;
    if (ours == theirs || (isnan(ours) && isnan(theirs)))
        return;
    fail(@"%@: ours %.17g, Foundation %.17g", what, ours, theirs);
}

static void same_object(id ours, id theirs, NSString *what)
{
    checks++;
    if (ours == theirs || [ours isEqual:theirs])
        return;
    fail(@"%@: ours %@, Foundation %@", what, ours, theirs);
}

static void same_flag(BOOL ours, BOOL theirs, NSString *what)
{
    checks++;
    if (ours == theirs)
        return;
    fail(@"%@: ours %d, Foundation %d", what, ours, theirs);
}

static Class ours_of(Class theirs)
{
    Class mine = NSClassFromString([@"CharonHost" stringByAppendingString:NSStringFromClass(theirs)]);
    if (!mine)
        fail(@"the backport defines no %@", NSStringFromClass(theirs));
    return mine;
}

static id send(id target, SEL selector)
{
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString *reason_of(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        NSString *reason = [exception.reason stringByReplacingOccurrencesOfString:@"CharonHost" withString:@""];
        reason = [reason stringByReplacingOccurrencesOfString:@"_NSStatic_" withString:@""];
        return [NSString stringWithFormat:@"%@: %@", exception.name, reason];
    }
    return nil;
}

static const double SAMPLES[] = {0, 1, -1, 3.5, 1e6, 1e-6, 273.15, -40};

static void compare_units(NSString *name)
{
    Class theirs = NSClassFromString(name), mine = ours_of(theirs);
    if (!mine)
        return;
    unsigned count = 0;
    objc_property_t *properties = class_copyPropertyList(object_getClass(theirs), &count);
    for (unsigned index = 0; index < count; index++) {
        const char *attributes = property_getAttributes(properties[index]);
        if (!attributes || strncmp(attributes, "T@\"NSUnit", 9) != 0)
            continue;
        SEL selector = sel_registerName(property_getName(properties[index]));
        NSString *what = [NSString stringWithFormat:@"+[%@ %s]", name, sel_getName(selector)];
        if (![mine respondsToSelector:selector]) {
            fail(@"%@ is missing", what);
            continue;
        }
        NSUnit *unit = send(theirs, selector), *unitOurs = send(mine, selector);
        same_object([unitOurs symbol], [unit symbol], [what stringByAppendingString:@" symbol"]);
        checks++;
        if (send(mine, selector) != unitOurs)
            fail(@"%@ is not a singleton", what);
        if (![unit isKindOfClass:[NSDimension class]])
            continue;
        NSUnitConverter *converter = [(NSDimension *)unit converter], *converterOurs = [(NSDimension *)unitOurs converter];
        for (unsigned sample = 0; sample < sizeof(SAMPLES) / sizeof(*SAMPLES); sample++) {
            same_double([converterOurs baseUnitValueFromValue:SAMPLES[sample]], [converter baseUnitValueFromValue:SAMPLES[sample]],
                        [NSString stringWithFormat:@"%@ baseUnitValueFromValue:%g", what, SAMPLES[sample]]);
            same_double([converterOurs valueFromBaseUnitValue:SAMPLES[sample]], [converter valueFromBaseUnitValue:SAMPLES[sample]],
                        [NSString stringWithFormat:@"%@ valueFromBaseUnitValue:%g", what, SAMPLES[sample]]);
        }
    }
    free(properties);
    same_object([send(mine, @selector(baseUnit)) symbol], [send(theirs, @selector(baseUnit)) symbol],
                [NSString stringWithFormat:@"+[%@ baseUnit] symbol", name]);
}

static void compare_measurements(void)
{
    Class theirs = [NSMeasurement class], mine = ours_of(theirs);
    Class theirLength = [NSUnitLength class], ourLength = ours_of(theirLength);
    Class theirTemperature = [NSUnitTemperature class], ourTemperature = ours_of(theirTemperature);
    if (!mine || !ourLength || !ourTemperature)
        return;
    NSUnit *kilometres = send(theirLength, @selector(kilometers)), *metres = send(theirLength, @selector(meters));
    NSUnit *kilometresOurs = send(ourLength, @selector(kilometers)), *metresOurs = send(ourLength, @selector(meters));

    NSMeasurement *(^build)(Class, double, NSUnit *) = ^(Class cls, double value, NSUnit *unit) {
        return (NSMeasurement *)[[cls alloc] initWithDoubleValue:value unit:unit];
    };
    NSMeasurement *a = build(theirs, 2, kilometres), *b = build(theirs, 500, metres);
    NSMeasurement *aOurs = build(mine, 2, kilometresOurs), *bOurs = build(mine, 500, metresOurs);

    same_double([aOurs measurementByConvertingToUnit:metresOurs].doubleValue,
                [a measurementByConvertingToUnit:metres].doubleValue, @"2 km in metres");
    same_double([aOurs measurementByAddingMeasurement:bOurs].doubleValue,
                [a measurementByAddingMeasurement:b].doubleValue, @"2 km + 500 m value");
    same_object([aOurs measurementByAddingMeasurement:bOurs].unit.symbol,
                [a measurementByAddingMeasurement:b].unit.symbol, @"2 km + 500 m unit");
    same_double([aOurs measurementBySubtractingMeasurement:bOurs].doubleValue,
                [a measurementBySubtractingMeasurement:b].doubleValue, @"2 km - 500 m value");
    same_double([aOurs measurementByAddingMeasurement:build(mine, 3, kilometresOurs)].doubleValue,
                [a measurementByAddingMeasurement:build(theirs, 3, kilometres)].doubleValue, @"2 km + 3 km value");
    same_object([aOurs measurementByAddingMeasurement:build(mine, 3, kilometresOurs)].unit.symbol,
                [a measurementByAddingMeasurement:build(theirs, 3, kilometres)].unit.symbol, @"2 km + 3 km unit");
    same_flag([aOurs canBeConvertedToUnit:metresOurs], [a canBeConvertedToUnit:metres], @"km convertible to m");
    same_flag([aOurs canBeConvertedToUnit:send(ourTemperature, @selector(celsius))],
              [a canBeConvertedToUnit:send(theirTemperature, @selector(celsius))], @"km convertible to celsius");
    same_flag([aOurs isEqual:build(mine, 2, kilometresOurs)], [a isEqual:build(theirs, 2, kilometres)], @"equal measurements");
    same_flag([aOurs isEqual:build(mine, 2000, metresOurs)], [a isEqual:build(theirs, 2000, metres)], @"km equals 2000 m");

    NSUnit *custom = [[NSUnit alloc] initWithSymbol:@"zz"], *other = [[NSUnit alloc] initWithSymbol:@"qq"];
    NSUnit *customOurs = [[ours_of([NSUnit class]) alloc] initWithSymbol:@"zz"], *otherOurs = [[ours_of([NSUnit class]) alloc] initWithSymbol:@"qq"];
    same_object(reason_of(^{ [build(mine, 1, customOurs) measurementByAddingMeasurement:build(mine, 1, otherOurs)]; }),
                reason_of(^{ [build(theirs, 1, custom) measurementByAddingMeasurement:build(theirs, 1, other)]; }),
                @"adding differing custom units");
    same_object(reason_of(^{ [build(mine, 1, customOurs) measurementByAddingMeasurement:build(mine, 1, metresOurs)]; }),
                reason_of(^{ [build(theirs, 1, custom) measurementByAddingMeasurement:build(theirs, 1, metres)]; }),
                @"adding a custom unit to metres");
    same_object(reason_of(^{ (void)[(NSMeasurement *)[mine alloc] initWithDoubleValue:1 unit:(NSUnit *)@"no"]; }),
                reason_of(^{ (void)[[NSMeasurement alloc] initWithDoubleValue:1 unit:(NSUnit *)@"no"]; }),
                @"a measurement of something that is not a unit");

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:aOurs];
    NSMeasurement *back = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    same_double(back.doubleValue, 2, @"archived measurement value");
    same_object(back.unit.symbol, @"km", @"archived measurement symbol");
    checks++;
    if (![back isEqual:aOurs])
        fail(@"a measurement does not survive an archive");
}

static void compare_intervals(void)
{
    Class theirs = [NSDateInterval class], mine = ours_of(theirs);
    if (!mine)
        return;
    NSDate *epoch = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    NSDateInterval *(^build)(Class, double, double) = ^(Class cls, double start, double duration) {
        return (NSDateInterval *)[[cls alloc] initWithStartDate:[epoch dateByAddingTimeInterval:start] duration:duration];
    };
    const double STARTS[] = {0, 5, 10, -5}, DURATIONS[] = {0, 10, 20};
    for (unsigned i = 0; i < 4; i++)
        for (unsigned j = 0; j < 3; j++)
            for (unsigned k = 0; k < 4; k++)
                for (unsigned l = 0; l < 3; l++) {
                    NSDateInterval *a = build(theirs, STARTS[i], DURATIONS[j]), *b = build(theirs, STARTS[k], DURATIONS[l]);
                    NSDateInterval *aOurs = build(mine, STARTS[i], DURATIONS[j]), *bOurs = build(mine, STARTS[k], DURATIONS[l]);
                    NSString *what = [NSString stringWithFormat:@"[%g+%g] and [%g+%g]", STARTS[i], DURATIONS[j], STARTS[k], DURATIONS[l]];
                    same_double([aOurs compare:bOurs], [a compare:b], [what stringByAppendingString:@" compare:"]);
                    same_flag([aOurs intersectsDateInterval:bOurs], [a intersectsDateInterval:b], [what stringByAppendingString:@" intersects"]);
                    same_flag([aOurs isEqualToDateInterval:bOurs], [a isEqualToDateInterval:b], [what stringByAppendingString:@" isEqualTo"]);
                    NSDateInterval *cut = [a intersectionWithDateInterval:b], *cutOurs = [aOurs intersectionWithDateInterval:bOurs];
                    checks++;
                    if ((cut == nil) != (cutOurs == nil))
                        fail(@"%@ intersection: ours %@, Foundation %@", what, cutOurs ? @"an interval" : @"nil", cut ? @"an interval" : @"nil");
                    else if (cut) {
                        same_object(cutOurs.startDate, cut.startDate, [what stringByAppendingString:@" intersection start"]);
                        same_double(cutOurs.duration, cut.duration, [what stringByAppendingString:@" intersection duration"]);
                    }
                    for (double when = -10; when <= 35; when += 5)
                        same_flag([aOurs containsDate:[epoch dateByAddingTimeInterval:when]],
                                  [a containsDate:[epoch dateByAddingTimeInterval:when]],
                                  [NSString stringWithFormat:@"%@ contains %g", what, when]);
                }
    NSDateInterval *one = build(mine, 5, 10);
    NSDateInterval *back = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:one]];
    checks++;
    if (![back isEqual:one])
        fail(@"an interval does not survive an archive");
    same_double(build(mine, 5, 10).endDate.timeIntervalSinceReferenceDate,
                build(theirs, 5, 10).endDate.timeIntervalSinceReferenceDate, @"end date");
}

int main(void)
{
    @autoreleasepool {
        for (NSString *name in @[@"NSUnitAcceleration", @"NSUnitAngle", @"NSUnitArea", @"NSUnitConcentrationMass",
                                 @"NSUnitDispersion", @"NSUnitDuration", @"NSUnitElectricCharge", @"NSUnitElectricCurrent",
                                 @"NSUnitElectricPotentialDifference", @"NSUnitElectricResistance", @"NSUnitEnergy",
                                 @"NSUnitFrequency", @"NSUnitFuelEfficiency", @"NSUnitIlluminance", @"NSUnitLength",
                                 @"NSUnitMass", @"NSUnitPower", @"NSUnitPressure", @"NSUnitSpeed", @"NSUnitTemperature",
                                 @"NSUnitVolume"])
            compare_units(name);

        Class concentration = ours_of([NSUnitConcentrationMass class]);
        for (double mass = 1; mass < 200; mass *= 7.3) {
            NSDimension *theirs = ((id (*)(id, SEL, double))objc_msgSend)([NSUnitConcentrationMass class],
                                                                         @selector(millimolesPerLiterWithGramsPerMole:), mass);
            NSDimension *ours = ((id (*)(id, SEL, double))objc_msgSend)(concentration,
                                                                       @selector(millimolesPerLiterWithGramsPerMole:), mass);
            same_object(ours.symbol, theirs.symbol, @"millimoles per litre symbol");
            same_double([ours.converter baseUnitValueFromValue:1], [theirs.converter baseUnitValueFromValue:1],
                        [NSString stringWithFormat:@"millimoles per litre of %g g/mol", mass]);
        }

        compare_measurements();
        compare_intervals();
        printf("%d checks, %d failures\n", checks, failures);
    }
    return failures;
}
