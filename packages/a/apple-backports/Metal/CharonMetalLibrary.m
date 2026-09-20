#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation CharonMetalFunction {
    NSString *_name, *_stage, *_source;
    NSDictionary *_reflection;
}

@synthesize label;

- (instancetype)initWithName:(NSString *)name stage:(NSString *)stage source:(NSString *)source reflection:(NSDictionary *)reflection
{
    if ((self = [super init])) {
        _name = [name copy];
        _stage = [stage copy];
        _source = [source copy];
        _reflection = reflection;
    }
    return self;
}

- (NSString *)name
{
    return _name;
}

- (NSString *)stage
{
    return _stage;
}

- (NSString *)source
{
    return _source;
}

- (NSDictionary *)reflection
{
    return _reflection;
}

- (MTLFunctionType)functionType
{
    return [_stage isEqualToString:@"vertex"] ? MTLFunctionTypeVertex : MTLFunctionTypeFragment;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

@end

@implementation CharonMetalLibrary {
    NSMutableDictionary *_functions;
}

@synthesize label;

- (instancetype)initWithFolder:(NSString *)folder error:(NSError **)error
{
    NSData *manifest = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"library.json"]];
    NSDictionary *root = manifest ? [NSJSONSerialization JSONObjectWithData:manifest options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error)
            *error = CharonMetalError(4, [NSString stringWithFormat:@"%@ holds no translated library", folder]);
        return nil;
    }
    if ((self = [super init])) {
        _functions = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in root[@"functions"]) {
            NSString *source = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:entry[@"source"]] encoding:NSUTF8StringEncoding error:NULL];
            NSData *reflectionData = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:entry[@"reflection"]]];
            NSDictionary *reflection = reflectionData ? [NSJSONSerialization JSONObjectWithData:reflectionData options:0 error:NULL] : nil;
            if (!source || !reflection)
                continue;
            _functions[entry[@"name"]] = [[CharonMetalFunction alloc] initWithName:entry[@"name"] stage:entry[@"stage"] source:source reflection:reflection];
        }
    }
    return self;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

- (NSArray *)functionNames
{
    return [_functions allKeys];
}

- (id<MTLFunction>)newFunctionWithName:(NSString *)functionName
{
    return (id<MTLFunction>)_functions[functionName];
}

@end
