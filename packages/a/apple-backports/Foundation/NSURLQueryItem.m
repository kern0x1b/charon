#import <Foundation/Foundation.h>

@implementation NSURLQueryItem

+ (instancetype)queryItemWithName:(NSString *)name value:(NSString *)value
{
    return [[self alloc] initWithName:name value:value];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    return [self initWithName:@"" value:nil];
}

- (instancetype)initWithName:(NSString *)name value:(NSString *)value
{
    if ((self = [super init])) {
        _name = [name copy];
        _value = [value copy];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"NS.name"];
    NSString *value = [coder decodeObjectOfClass:[NSString class] forKey:@"NS.value"];
    return [self initWithName:name value:value];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"NS.name"];
    [coder encodeObject:_value forKey:@"NS.value"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (NSString *)name
{
    return _name;
}

- (NSString *)value
{
    return _value;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSURLQueryItem class]])
        return NO;
    NSURLQueryItem *other = object;
    return (_name == other.name || [_name isEqualToString:other.name]) && (_value == other.value || [_value isEqualToString:other.value]);
}

- (NSUInteger)hash
{
    return _name.hash ^ _value.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p> {name = %@, value = %@}", [self class], self, _name, _value];
}

@end
