#import "foundation11-cases.h"
#import <objc/message.h>
#import <objc/runtime.h>

@implementation Foundation11Recorder

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

static NSString *foundation11_prefix;

static SEL sel(SEL selector)
{
    if (!foundation11_prefix.length)
        return selector;
    return NSSelectorFromString([foundation11_prefix stringByAppendingString:NSStringFromSelector(selector)]);
}

static NSString *described(NSError *error)
{
    if (!error)
        return @"nil";
    NSString *debug = error.userInfo[NSDebugDescriptionErrorKey];
    return [NSString stringWithFormat:@"%@ %ld%@", error.domain, (long)error.code, debug ? [@" " stringByAppendingString:debug] : @""];
}

static NSString *tail(NSURL *url)
{
    return url.lastPathComponent ?: @"?";
}

static void run_property_lists(Foundation11Recorder *recorder)
{
    NSURL *folder = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *arrayURL = [folder URLByAppendingPathComponent:@"charon11-array.plist"];
    NSURL *dictURL = [folder URLByAppendingPathComponent:@"charon11-dict.plist"];
    NSURL *emptyURL = [folder URLByAppendingPathComponent:@"charon11-empty.plist"];
    NSURL *missingURL = [folder URLByAppendingPathComponent:@"charon11-missing.plist"];
    [[NSFileManager defaultManager] removeItemAtURL:missingURL error:NULL];

    NSError *error = nil;
    BOOL wrote = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(@[@"a", @2], sel(@selector(writeToURL:error:)), arrayURL, &error);
    [recorder record:[NSString stringWithFormat:@"%d %@", wrote, described(error)] named:@"write.array"];

    NSData *raw = [NSData dataWithContentsOfURL:arrayURL];
    NSString *head = raw.length >= 19 ? [[NSString alloc] initWithData:[raw subdataWithRange:NSMakeRange(0, 19)] encoding:NSUTF8StringEncoding] : @"(short)";
    [recorder record:head ?: @"(binary)" named:@"write.format"];

    NSError *dictionaryError = nil;
    BOOL wroteDictionary = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(@{@"k": @"v"}, sel(@selector(writeToURL:error:)), dictURL, &dictionaryError);
    [recorder record:[NSString stringWithFormat:@"%d %@", wroteDictionary, described(dictionaryError)] named:@"write.dictionary"];

    NSError *readError = nil;
    id readBack = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSArray class], sel(@selector(arrayWithContentsOfURL:error:)), arrayURL, &readError);
    [recorder record:[NSString stringWithFormat:@"%@ %@", readBack ?: @"nil", described(readError)] named:@"read.array"];

    NSError *dictionaryBackError = nil;
    id dictionaryBack = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSDictionary class], sel(@selector(dictionaryWithContentsOfURL:error:)), dictURL, &dictionaryBackError);
    [recorder record:[NSString stringWithFormat:@"%@ %@", dictionaryBack ?: @"nil", described(dictionaryBackError)] named:@"read.dictionary"];

    NSError *wrongKindError = nil;
    id wrongKind = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSArray class], sel(@selector(arrayWithContentsOfURL:error:)), dictURL, &wrongKindError);
    [recorder record:[NSString stringWithFormat:@"%@ %@ %@", wrongKind ?: @"nil", wrongKindError.domain, @(wrongKindError.code)] named:@"read.wrongKind"];
    [recorder record:[wrongKindError.userInfo[NSDebugDescriptionErrorKey] hasSuffix:@"did not contain a top-level array value"] ? @"says so" : @"says something else"
               named:@"read.wrongKind.text"];

    [[NSData data] writeToURL:emptyURL atomically:YES];
    NSError *emptyError = nil;
    id empty = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSArray class], sel(@selector(arrayWithContentsOfURL:error:)), emptyURL, &emptyError);
    [recorder record:[NSString stringWithFormat:@"%@ %@ %@", empty ?: @"nil", emptyError.domain, @(emptyError.code)] named:@"read.empty"];

    NSError *missingError = nil;
    id missing = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSArray class], sel(@selector(arrayWithContentsOfURL:error:)), missingURL, &missingError);
    [recorder record:[NSString stringWithFormat:@"%@ %@ %@", missing ?: @"nil", missingError.domain, @(missingError.code)] named:@"read.missing"];

    NSError *invalidError = nil;
    BOOL invalid = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(@[[NSObject new]], sel(@selector(writeToURL:error:)), arrayURL, &invalidError);
    [recorder record:[NSString stringWithFormat:@"%d %@ %@", invalid, invalidError.domain, @(invalidError.code)] named:@"write.invalid"];

    NSError *mutableError = nil;
    id mutable = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSMutableArray alloc], sel(@selector(initWithContentsOfURL:error:)), arrayURL, &mutableError);
    [recorder record:[mutable respondsToSelector:@selector(addObject:)] ? @"mutable" : @"immutable" named:@"read.mutable"];
    [recorder record:[NSString stringWithFormat:@"%@", mutable ?: @"nil"] named:@"read.mutable.value"];

    NSError *nilURLError = nil;
    id nilURL = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([NSArray class], sel(@selector(arrayWithContentsOfURL:error:)), (NSURL *)nil, &nilURLError);
    [recorder record:[NSString stringWithFormat:@"%@ %@", nilURL ?: @"nil", described(nilURLError)] named:@"read.nilURL"];
    [recorder record:tail(arrayURL) named:@"paths.stable"];
}

static void run_query_items(Foundation11Recorder *recorder)
{
    NSArray *queries = @[@"", @"?", @"?a=1", @"?a", @"?a=", @"?=v", @"?a=1&&b=2", @"?a=b=c",
                         @"?a=%E2%82%AC&b=two%20words", @"?a=1&a=2", @"?a+b=c+d"];
    for (NSString *query in queries) {
        NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://e.com/p" stringByAppendingString:query]];
        NSArray *items = ((id (*)(id, SEL))objc_msgSend)(components, sel(@selector(percentEncodedQueryItems)));
        NSMutableArray *pieces = [NSMutableArray array];
        for (NSURLQueryItem *item in items)
            [pieces addObject:[NSString stringWithFormat:@"%@=%@", item.name, item.value ?: @"(nil)"]];
        [recorder record:items ? [pieces componentsJoinedByString:@"|"] : @"(nil array)"
                   named:[NSString stringWithFormat:@"queryItems.read.%@", query.length ? query : @"(none)"]];
    }

    NSArray *sets = @[@[], @[[NSURLQueryItem queryItemWithName:@"x" value:@"%41"]],
                      @[[NSURLQueryItem queryItemWithName:@"x" value:nil]],
                      @[[NSURLQueryItem queryItemWithName:@"x" value:@""]],
                      @[[NSURLQueryItem queryItemWithName:@"" value:@"v"]],
                      @[[NSURLQueryItem queryItemWithName:@"a" value:@"1"], [NSURLQueryItem queryItemWithName:@"b" value:@"2"]]];
    NSUInteger index = 0;
    for (NSArray *items in sets) {
        NSURLComponents *components = [NSURLComponents componentsWithString:@"https://e.com/p?keep=1"];
        ((void (*)(id, SEL, id))objc_msgSend)(components, sel(@selector(setPercentEncodedQueryItems:)), items);
        [recorder record:[NSString stringWithFormat:@"%@ / %@", components.percentEncodedQuery ?: @"(nil)", components.query ?: @"(nil)"]
                   named:[NSString stringWithFormat:@"queryItems.write.%lu", (unsigned long)index++]];
    }
    NSURLComponents *cleared = [NSURLComponents componentsWithString:@"https://e.com/p?keep=1"];
    ((void (*)(id, SEL, id))objc_msgSend)(cleared, sel(@selector(setPercentEncodedQueryItems:)), (NSArray *)nil);
    [recorder record:cleared.percentEncodedQuery ?: @"(nil)" named:@"queryItems.write.nil"];
}

static void run_decode_value(Foundation11Recorder *recorder)
{
    NSMutableData *buffer = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:buffer];
    int written = 42;
    [archiver encodeValueOfObjCType:@encode(int) at:&written];
    [archiver finishEncoding];

    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:buffer];
    int read = 0;
    ((void (*)(id, SEL, const char *, void *, NSUInteger))objc_msgSend)(unarchiver, sel(@selector(decodeValueOfObjCType:at:size:)),
                                                                        @encode(int), &read, sizeof read);
    [recorder record:[NSString stringWithFormat:@"%d", read] named:@"decodeValue.roundTrip"];

    NSKeyedUnarchiver *again = [[NSKeyedUnarchiver alloc] initForReadingWithData:buffer];
    NSString *answer = @"accepted";
    @try {
        char small = 0;
        ((void (*)(id, SEL, const char *, void *, NSUInteger))objc_msgSend)(again, sel(@selector(decodeValueOfObjCType:at:size:)),
                                                                            @encode(int), &small, (NSUInteger)1);
    } @catch (NSException *exception) {
        answer = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    }
    [recorder record:answer named:@"decodeValue.wrongSize"];
}

static void run_transformer(Foundation11Implementation implementation, Foundation11Recorder *recorder)
{
    Class transformer = implementation.transformer;
    [recorder record:[NSString stringWithFormat:@"%@", [transformer allowedTopLevelClasses]] named:@"transformer.allowedClasses"];
    [recorder record:[transformer allowsReverseTransformation] ? @"YES" : @"NO" named:@"transformer.allowsReverse"];
    [recorder record:[transformer transformedValueClass] ? NSStringFromClass([transformer transformedValueClass]) : @"nil"
               named:@"transformer.transformedValueClass"];

    id instance = [[transformer alloc] init];
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:@[@"a", @1] requiringSecureCoding:YES error:NULL];
    [recorder record:[[instance transformedValue:archive] description] named:@"transformer.transform"];
    [recorder record:[instance transformedValue:nil] ?: @"nil" named:@"transformer.transformNil"];

    NSData *made = [instance reverseTransformedValue:@[@"b"]];
    [recorder record:made.length > 0 ? @"non-empty" : @"empty" named:@"transformer.reverse"];
    [recorder record:[[instance transformedValue:made] description] named:@"transformer.reverseRoundTrip"];

    NSString *junkAnswer = @"no exception";
    @try {
        id decoded = [instance transformedValue:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]];
        junkAnswer = decoded ? [decoded description] : @"nil";
    } @catch (NSException *exception) {
        junkAnswer = exception.name;
    }
    [recorder record:junkAnswer named:@"transformer.junk"];

    NSString *refusedAnswer = @"no exception";
    @try {
        [instance reverseTransformedValue:[NSValue valueWithRange:NSMakeRange(0, 1)]];
    } @catch (NSException *exception) {
        refusedAnswer = [NSString stringWithFormat:@"%@: %@", exception.name,
                                                   [exception.reason hasPrefix:@"Object of class NSValue is not among allowed top level class list"] ? @"says so" : exception.reason];
    }
    [recorder record:refusedAnswer named:@"transformer.refusesOtherClass"];

    NSString *notData = @"no exception";
    @try {
        id answer = [instance transformedValue:@"not data"];
        notData = answer ? [answer description] : @"nil";
    } @catch (NSException *exception) {
        notData = exception.name;
    }
    [recorder record:notData named:@"transformer.transformNotData"];
}

void foundation11_run(Foundation11Implementation implementation, Foundation11Recorder *recorder)
{
    foundation11_prefix = implementation.prefix;
    run_property_lists(recorder);
    run_query_items(recorder);
    run_decode_value(recorder);
    run_transformer(implementation, recorder);
    foundation11_prefix = nil;
}
