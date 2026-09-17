#import "directionaledges-cases.h"
#import <objc/message.h>

@implementation DirectionalEdgesRecorder

- (instancetype)init
{
    if ((self = [super init]))
        _records = [NSMutableDictionary dictionary];
    return self;
}

- (void)record:(NSString *)value named:(NSString *)name
{
    if (_records[name])
        [NSException raise:NSInternalInconsistencyException format:@"record %@ is recorded twice", name];
    _records[name] = value ?: @"nil";
}

@end

static NSString *directionaledges_prefix;

static SEL sel(SEL selector)
{
    if (!directionaledges_prefix.length)
        return selector;
    return NSSelectorFromString([directionaledges_prefix stringByAppendingString:NSStringFromSelector(selector)]);
}

static NSString *text(NSDirectionalEdgeInsets insets)
{
    return [NSString stringWithFormat:@"%g %g %g %g", insets.top, insets.leading, insets.bottom, insets.trailing];
}

void directionaledges_run(DirectionalEdgesImplementation implementation, DirectionalEdgesRecorder *recorder)
{
    directionaledges_prefix = implementation.prefix;
    [recorder record:text(*implementation.zero) named:@"zero"];

    NSArray *values = @[@[@1.5, @2, @3.25, @4], @[@0, @0, @0, @0], @[@(-1), @0.5, @1000, @0.125]];
    for (NSArray *four in values) {
        NSDirectionalEdgeInsets insets = NSDirectionalEdgeInsetsMake([four[0] doubleValue], [four[1] doubleValue],
                                                                     [four[2] doubleValue], [four[3] doubleValue]);
        NSString *label = [four componentsJoinedByString:@","];
        [recorder record:implementation.string(insets) named:[@"string." stringByAppendingString:label]];

        NSValue *value = ((id (*)(id, SEL, NSDirectionalEdgeInsets))objc_msgSend)([NSValue class],
            sel(@selector(valueWithDirectionalEdgeInsets:)), insets);
        [recorder record:@(value.objCType) named:[@"objCType." stringByAppendingString:label]];
        [recorder record:text(((NSDirectionalEdgeInsets (*)(id, SEL))objc_msgSend)(value, sel(@selector(directionalEdgeInsetsValue))))
                   named:[@"value." stringByAppendingString:label]];
    }

    NSArray *strings = @[@"{1, 2, 3, 4}", @"{1, 2}", @"{1}", @"", @"nonsense", @"{1, 2, 3, 4, 5}", @"{ 1 , 2 , 3 , 4 }",
                         @"1, 2, 3, 4", @"{-1.5, 0, 2e2, .5}"];
    for (NSString *string in strings)
        [recorder record:text(implementation.parse(string)) named:[@"parse." stringByAppendingString:string.length ? string : @"(empty)"]];

    NSDirectionalEdgeInsets insets = NSDirectionalEdgeInsetsMake(1.5, 2, 3.25, 4);
    for (NSNumber *secure in @[@NO, @YES]) {
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        archiver.requiresSecureCoding = secure.boolValue;
        ((void (*)(id, SEL, NSDirectionalEdgeInsets, id))objc_msgSend)(archiver, sel(@selector(encodeDirectionalEdgeInsets:forKey:)), insets, @"insets");
        [archiver finishEncoding];
        [recorder record:[NSString stringWithFormat:@"%lu bytes", (unsigned long)data.length]
                   named:[NSString stringWithFormat:@"archive.secure%@", secure.boolValue ? @"YES" : @"NO"]];

        NSKeyedUnarchiver *reader = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        reader.requiresSecureCoding = secure.boolValue;
        [recorder record:text(((NSDirectionalEdgeInsets (*)(id, SEL, id))objc_msgSend)(reader, sel(@selector(decodeDirectionalEdgeInsetsForKey:)), @"insets"))
                   named:[NSString stringWithFormat:@"decode.secure%@", secure.boolValue ? @"YES" : @"NO"]];
        [recorder record:text(((NSDirectionalEdgeInsets (*)(id, SEL, id))objc_msgSend)(reader, sel(@selector(decodeDirectionalEdgeInsetsForKey:)), @"absent"))
                   named:[NSString stringWithFormat:@"decodeMissing.secure%@", secure.boolValue ? @"YES" : @"NO"]];
    }
    directionaledges_prefix = nil;
}
