// matter/params-init.m - the designated initialiser the SDK declares on MTRSubscribeParams, initWithMinInterval:maxInterval:
// (MTRCluster.h:213: "Must provide a minInterval and maxInterval; there are no default values"), measured on the framework
// and on the port's own committed class, the same calls on both sides.
//
// The system side is the host's MTRSubscribeParams. The port side is the committed CharonMatterMTRSubscribeParams.m,
// compiled by params-init.sh with its class name aliased onto CharonPortMTRSubscribeParams, so both classes are in
// one program. Every line is compared: a difference is a failure, and a side that does not declare the initialiser
// answers "absent" for each of its rows, which is a failure too.
//
// What is measured, and only the framework's answer is the expectation:
//   designated.*  the initialiser after (1, 10): the stored minInterval and maxInterval, and every other property
//                 (the defaults it leaves), read through the properties
//   designated.min>max and designated.nil  the stored values for (10, 1) and for (nil, nil); nothing is refused
//   designated.copy  whether a copy is the same object, the stored minInterval and maxInterval, and whether a copy
//                 of the argument is stored (the framework copies it)
//   init.*        the deprecated -init, for the defaults beside it (already matching; kept so that a change to either
//                 initialiser shows here)
//
// Usage: params-init (no arguments). Exit 0 when every line is the same on both sides, 1 otherwise.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSMutableDictionary *sides[2];

static void record(int side, NSString *key, NSString *value)
{
    sides[side][key] = value;
}

static NSString *describe(id value)
{
    return value ? [NSString stringWithFormat:@"%@ (%@)", value, NSStringFromClass([value class])] : @"nil";
}

// The value of one property of the object, read through its accessor, or what raised when it does not answer.
static NSString *property(id object, NSString *name)
{
    @try {
        return describe([object valueForKey:name]);
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"raised %@", exception.name];
    }
}

static NSArray *propertyNames(void)
{
    NSMutableArray *names = [NSMutableArray array];
    unsigned count = 0;
    objc_property_t *list = class_copyPropertyList([MTRSubscribeParams class], &count);
    for (unsigned index = 0; index < count; index++) {
        [names addObject:@(property_getName(list[index]))];
    }
    free(list);
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

static void measure(int side, Class cls, NSArray *names)
{
    SEL designated = NSSelectorFromString(@"initWithMinInterval:maxInterval:");
    BOOL declared = [cls instancesRespondToSelector:designated];
    record(side, @"designated.declared", declared ? @"yes" : @"no");
    NSString *absent = @"absent";
    if (!declared) {
        for (NSString *name in names) {
            record(side, [NSString stringWithFormat:@"designated.after 1,10 %@", name], absent);
            record(side, [NSString stringWithFormat:@"designated.after 10,1 %@", name], absent);
        }
        record(side, @"designated.copy same object", absent);
        record(side, @"designated.copy minInterval is the same object", absent);
        record(side, @"designated.copy maxInterval is the same object", absent);
        record(side, @"designated.argument stored as given", absent);
        record(side, @"designated.nil,nil", absent);
        return;
    }
    // Both the framework's and the port's initialisers, called the same way.
    id (*initWith)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;

    id after = initWith([cls alloc], designated, @1, @10);
    for (NSString *name in names) {
        record(side, [NSString stringWithFormat:@"designated.after 1,10 %@", name], property(after, name));
    }
    id reversed = initWith([cls alloc], designated, @10, @1);
    for (NSString *name in names) {
        record(side, [NSString stringWithFormat:@"designated.after 10,1 %@", name], property(reversed, name));
    }
    @try {
        id nothing = initWith([cls alloc], designated, nil, nil);
        record(side, @"designated.nil,nil", [NSString stringWithFormat:@"minInterval %@, maxInterval %@",
                                              property(nothing, @"minInterval"), property(nothing, @"maxInterval")]);
    } @catch (NSException *exception) {
        record(side, @"designated.nil,nil", [NSString stringWithFormat:@"raised %@", exception.name]);
    }
    id copied = [after copy];
    record(side, @"designated.copy same object", copied == after ? @"yes" : @"no");
    record(side, @"designated.copy minInterval is the same object",
           [copied minInterval] == [after minInterval] ? @"yes" : @"no");
    record(side, @"designated.copy maxInterval is the same object",
           [copied maxInterval] == [after maxInterval] ? @"yes" : @"no");
    // A mutable string is not an NSNumber, but the initialiser takes the argument as the framework does: the framework
    // stores a COPY of it, so the stored object is not the argument.
    NSMutableString *mutable = [NSMutableString stringWithString:@"1"];
    id fromMutable = initWith([cls alloc], designated, (NSNumber *)mutable, @10);
    record(side, @"designated.argument stored as given", [fromMutable minInterval] == (NSNumber *)mutable ? @"yes" : @"no");
}

static void measureInit(int side, Class cls, NSArray *names)
{
    id plain = [[cls alloc] init];
    for (NSString *name in names) {
        record(side, [NSString stringWithFormat:@"init.%@", name], property(plain, name));
    }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        Class classes[2] = {[MTRSubscribeParams class], NSClassFromString(@"CharonPortMTRSubscribeParams")};
        if (!classes[1]) {
            printf("class\tCharonPortMTRSubscribeParams\tMISSING: params-init.sh did not link the port's object\n");
            return 1;
        }
        NSArray *names = propertyNames();
        sides[0] = [NSMutableDictionary dictionary];
        sides[1] = [NSMutableDictionary dictionary];
        for (int side = 0; side < 2; side++) {
            measure(side, classes[side], names);
            measureInit(side, classes[side], names);
        }
        NSInteger failures = 0;
        NSArray *keys = [[sides[0].allKeys arrayByAddingObjectsFromArray:sides[1].allKeys]
            valueForKeyPath:@"@distinctUnionOfObjects.self"];
        for (NSString *key in [keys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *system = sides[0][key] ?: @"(absent)";
            NSString *port = sides[1][key] ?: @"(absent)";
            BOOL same = [system isEqualToString:port];
            printf("%s\t%s\n    system: %s\n    port:   %s\n", same ? "same     " : "DIFFERENT", key.UTF8String,
                   system.UTF8String, port.UTF8String);
            if (!same) {
                failures++;
            }
        }
        printf("checks: %lu, failed: %ld\n", (unsigned long)keys.count, (long)failures);
        return failures == 0 ? 0 : 1;
    }
}
