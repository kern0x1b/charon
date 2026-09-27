// HKSourceRevision and HKDeletedObject: which revision of which source wrote an object, and that an
// object of the store is gone. Both arrived in iOS 9.0, so both are files of their own.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@implementation HKSourceRevision {
    HKSource *_source;
    NSString *_version;
}
// iOS 11.0 added -productType and -operatingSystemVersion, and this delivery carries the 9.0 group,
// so both are @dynamic and the compiler emits no accessor for either.
@dynamic productType;
@dynamic operatingSystemVersion;


+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithSource:(HKSource *)source version:(nullable NSString *)version
{
    if (![source isKindOfClass:[HKSource class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@ is not a source; a source revision is a revision of a source.", source];
        return nil;
    }
    HKSourceRevision *revision = [super init];
    if (revision) {
        revision->_source = (HKSource *)[source copy];
        revision->_version = [version copy];
    }
    return revision;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    HKSource *source = [coder decodeObjectOfClass:[HKSource class] forKey:@"source"];
    NSString *version = [coder decodeObjectOfClass:[NSString class] forKey:@"version"];
    return [self initWithSource:source ?: [HKSource charon_sourceWithName:@"" bundleIdentifier:@""] version:version];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_source forKey:@"source"];
    [coder encodeObject:_version forKey:@"version"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[HKSourceRevision alloc] initWithSource:_source version:_version];
}

- (HKSource *)source
{
    return _source;
}

// The version of the source, which the header says is taken from the source's CFBundleVersion and
// "may be nil for older data". Nil stays nil, so a caller can tell a source that reported no version
// from one that reported an empty one.
- (nullable NSString *)version
{
    return _version;
}

- (BOOL)isEqual:(id)other
{
    if (self == other)
        return YES;
    if (![other isKindOfClass:[HKSourceRevision class]])
        return NO;
    HKSourceRevision *that = other;
    return [_source isEqual:that.source] && (_version == that.version || [_version isEqualToString:that.version]);
}

- (NSUInteger)hash
{
    return _source.hash ^ _version.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKSourceRevision[%@ %@]", _source, _version];
}

@end

#pragma mark - HKDeletedObject

@implementation HKDeletedObject {
    NSUUID *_UUID;
}
// iOS 11.0 added -metadata, and this delivery carries the 9.0 group, so the member is @dynamic and
// the compiler emits no accessor for it.
@dynamic metadata;


+ (BOOL)supportsSecureCoding
{
    return YES;
}

// The store makes one of these for every object it removed, out of its own deleted table, so that an
// anchored query can hand an application the identifier of what is gone as the release hands it an
// HKDeletedObject rather than a bare UUID.
- (instancetype)charon_initWithUUID:(NSUUID *)uuid
{
    HKDeletedObject *deleted = [super init];
    if (deleted)
        deleted->_UUID = [uuid copy];
    return deleted;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    HKDeletedObject *deleted = [super init];
    if (deleted)
        deleted->_UUID = [[coder decodeObjectOfClass:[NSUUID class] forKey:@"UUID"] copy];
    return deleted;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_UUID forKey:@"UUID"];
}

- (NSUUID *)UUID
{
    return _UUID;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKDeletedObject %@", _UUID.UUIDString];
}

@end
