#import "CharonNEHotspot.h"

/* The configuration object: property storage, `copy` and the keyed archive, which the 26.2 header declares
   on the class (<NSCopying,NSSecureCoding>). The host's own NetworkExtension was measured for exactly these
   answers - the defaults (SSID and SSIDPrefix empty, joinOnce and hidden NO, lifeTimeInDays nil), the
   setters, a -copy that is another object, and an NSKeyedArchiver round trip that decodes the values back
   (facts/NetworkExtension/Hotspot.md) - and tests/backports/host/netext-hotspot/ compares them name by name.

   The passphrase is kept for the join, which is not carried yet, and it is not archived: a password does not
   go into a file the object writes. */
@implementation NEHotspotConfiguration {
    NSString *_SSID;
    NSString *_SSIDPrefix;
    NSString *_passphrase;
    BOOL _isWEP;
    BOOL _joinOnce;
    NSNumber *_lifeTimeInDays;
    BOOL _hidden;
}

- (instancetype)initWithSSID:(NSString *)SSID
{
    self = [super init];
    if (self) {
        _SSID = [SSID copy];
        _SSIDPrefix = @"";
    }
    return self;
}

- (instancetype)initWithSSID:(NSString *)SSID passphrase:(NSString *)passphrase isWEP:(BOOL)isWEP
{
    self = [self initWithSSID:SSID];
    if (self) {
        _passphrase = [passphrase copy];
        _isWEP = isWEP;
    }
    return self;
}

- (instancetype)initWithSSIDPrefix:(NSString *)SSIDPrefix
{
    self = [super init];
    if (self) {
        _SSID = @"";
        _SSIDPrefix = [SSIDPrefix copy];
    }
    return self;
}

- (instancetype)initWithSSIDPrefix:(NSString *)SSIDPrefix passphrase:(NSString *)passphrase isWEP:(BOOL)isWEP
{
    self = [self initWithSSIDPrefix:SSIDPrefix];
    if (self) {
        _passphrase = [passphrase copy];
        _isWEP = isWEP;
    }
    return self;
}

- (NSString *)SSID
{
    return _SSID;
}

- (NSString *)SSIDPrefix
{
    return _SSIDPrefix;
}

- (BOOL)joinOnce
{
    return _joinOnce;
}

- (void)setJoinOnce:(BOOL)joinOnce
{
    _joinOnce = joinOnce;
}

- (NSNumber *)lifeTimeInDays
{
    return _lifeTimeInDays;
}

- (void)setLifeTimeInDays:(NSNumber *)lifeTimeInDays
{
    _lifeTimeInDays = [lifeTimeInDays copy];
}

- (BOOL)hidden
{
    return _hidden;
}

- (void)setHidden:(BOOL)hidden
{
    _hidden = hidden;
}

- (id)copyWithZone:(NSZone *)zone
{
    NEHotspotConfiguration *copy = [[NEHotspotConfiguration allocWithZone:zone] init];
    copy->_SSID = [_SSID copy];
    copy->_SSIDPrefix = [_SSIDPrefix copy];
    copy->_passphrase = [_passphrase copy];
    copy->_isWEP = _isWEP;
    copy->_joinOnce = _joinOnce;
    copy->_lifeTimeInDays = [_lifeTimeInDays copy];
    copy->_hidden = _hidden;
    return copy;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _SSID = [[coder decodeObjectOfClass:[NSString class] forKey:@"SSID"] copy];
        _SSIDPrefix = [[coder decodeObjectOfClass:[NSString class] forKey:@"SSIDPrefix"] copy];
        _joinOnce = [coder decodeBoolForKey:@"joinOnce"];
        _lifeTimeInDays = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"lifeTimeInDays"] copy];
        _hidden = [coder decodeBoolForKey:@"hidden"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_SSID forKey:@"SSID"];
    [coder encodeObject:_SSIDPrefix forKey:@"SSIDPrefix"];
    [coder encodeBool:_joinOnce forKey:@"joinOnce"];
    [coder encodeObject:_lifeTimeInDays forKey:@"lifeTimeInDays"];
    [coder encodeBool:_hidden forKey:@"hidden"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
