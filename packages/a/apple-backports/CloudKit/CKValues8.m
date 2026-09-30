// The value and identifier classes of CloudKit's first release: the record, the zone, the query and
// the notification information, and the four classes that name them.
//
// Everything here is a value: it is built, copied, compared, archived and printed, and it reads
// back what it was given. Nothing here reaches the network - the requests the operations make are a
// later delivery - so what each of these answers is exactly what the host's own CloudKit answers,
// measured with the differential of facts/CloudKit/Values.md, including the exception and the words
// for every initializer CloudKit refuses.
//
// The defaults are CloudKit's own and not this port's choice: a record that is made of a type and
// nothing else lands in the default zone of the current user, and a zone made of a name and nothing
// else has no capabilities until a caller says so.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CloudKit/CloudKit.h>

#import "CharonCKConstants.h"
#import "CharonCKValue.h"

// The keys these classes archive under. Apple's own names are the keys the release's own archive
// uses, and an archive is what a caller hands between two processes, so the names cannot be the
// port's; they are the ones the measured -description output and the host's own archive round trip
// agree on, and they are listed in facts/CloudKit/Values.md.
static NSString *const CharonCKKeyZoneName = @"zoneName";
static NSString *const CharonCKKeyOwnerName = @"ownerName";
static NSString *const CharonCKKeyRecordName = @"recordName";
static NSString *const CharonCKKeyRecordZoneID = @"recordZoneID";
static NSString *const CharonCKKeyRecordType = @"recordType";
static NSString *const CharonCKKeyValues = @"values";
static NSString *const CharonCKKeyCapabilities = @"capabilities";
static NSString *const CharonCKKeyRecordTypeKey = @"recordType";
static NSString *const CharonCKKeySubscriptionID = @"subscriptionID";
static NSString *const CharonCKKeyReferenceAction = @"referenceAction";
static NSString *const CharonCKKeyFileURL = @"fileURL";
static NSString *const CharonCKKeySortDescriptors = @"sortDescriptors";
static NSString *const CharonCKKeyRelativeLocation = @"relativeLocation";

#pragma mark - CKRecordZoneID

@implementation CKRecordZoneID

- (instancetype)initWithZoneName:(NSString *)zoneName ownerName:(NSString *)ownerName
{
    self = [super init];
    if (self) {
        _zoneName = [zoneName copy];
        _ownerName = [ownerName copy];
    }
    return self;
}

+ (instancetype)new
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKRecordZoneID initWithZoneName:ownerName:]", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKRecordZoneID initWithZoneName:ownerName:]", nil];
    return nil;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_zoneName forKey:CharonCKKeyZoneName];
    [coder encodeObject:_ownerName forKey:CharonCKKeyOwnerName];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithZoneName:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyZoneName]
                         ownerName:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyOwnerName]];
}

- (id)copyWithZone:(NSZone *)zone
{
    // Immutable, so the copy is the receiver: this is what NSObject's own copyWithZone: does for a
    // class that does not override it, and it is what the host's own answers are measured against.
    return self;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKRecordZoneID class]]) {
        return NO;
    }
    CKRecordZoneID *zone = other;
    return [_zoneName isEqualToString:zone.zoneName] && [_ownerName isEqualToString:zone.ownerName];
}

- (NSUInteger)hash
{
    return [_zoneName hash] ^ [_ownerName hash];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordZoneID: %p; zoneName=%@, ownerName=%@>", self, _zoneName, _ownerName];
}

@end

#pragma mark - CKRecordID

@implementation CKRecordID

- (instancetype)initWithRecordName:(NSString *)recordName
{
    return [self initWithRecordName:recordName
                            zoneID:[[CKRecordZoneID alloc] initWithZoneName:CKRecordZoneDefaultName
                                                                  ownerName:CKOwnerDefaultName]];
}

- (instancetype)initWithRecordName:(NSString *)recordName zoneID:(CKRecordZoneID *)zoneID
{
    self = [super init];
    if (self) {
        _recordName = [recordName copy];
        _zoneID = [zoneID copy];
    }
    return self;
}

+ (instancetype)new
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKRecordID initWithRecordName:] or -[CKRecordID initWithRecordName:zoneID:]", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKRecordID initWithRecordName:] or -[CKRecordID initWithRecordName:zoneID:]", nil];
    return nil;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordName forKey:CharonCKKeyRecordName];
    [coder encodeObject:_zoneID forKey:CharonCKKeyRecordZoneID];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    CKRecordZoneID *zoneID = [coder decodeObjectOfClass:[CKRecordZoneID class] forKey:CharonCKKeyRecordZoneID];
    return [self initWithRecordName:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyRecordName]
                             zoneID:zoneID];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKRecordID class]]) {
        return NO;
    }
    CKRecordID *record = other;
    return [_recordName isEqualToString:record.recordName] && [_zoneID isEqual:record.zoneID];
}

- (NSUInteger)hash
{
    return [_recordName hash] ^ [_zoneID hash];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordID: %p; recordName=%@, zoneID=%@:%@>", self,
            _recordName, _zoneID.zoneName, _zoneID.ownerName];
}

@end

#pragma mark - CKServerChangeToken

@implementation CKServerChangeToken
{
    NSData *_token;
}

+ (instancetype)new
{
    [NSException raise:@"CKException" format:@"You can't call init on CKServerChangeToken", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:@"CKException" format:@"You can't call init on CKServerChangeToken", nil];
    return nil;
}

// The token is the opaque string the changes endpoints hand back and want again, so it is kept and
// handed back byte for byte. There is no other content: the host's own token is a string of the
// service's own shape, and facts/CloudKit/Values.md records that a value of this class is only ever
// made by the service.
+ (instancetype)tokenWithData:(NSData *)data
{
    CKServerChangeToken *token = [[self alloc] initWithData:data];
    return token;
}

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (self) {
        _token = [data copy];
    }
    return self;
}

- (NSData *)data
{
    return _token;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_token forKey:@"token"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithData:[coder decodeObjectOfClass:[NSData class] forKey:@"token"]];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKServerChangeToken class]]) {
        return NO;
    }
    return [_token isEqualToData:((CKServerChangeToken *)other)->_token];
}

- (NSUInteger)hash
{
    return _token.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKServerChangeToken: %p>", self];
}

@end

#pragma mark - CKRecordZone

@implementation CKRecordZone

- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID
{
    self = [super init];
    if (self) {
        _zoneID = [zoneID copy];
    }
    return self;
}

- (instancetype)initWithZoneName:(NSString *)zoneName
{
    return [self initWithZoneID:[[CKRecordZoneID alloc] initWithZoneName:zoneName
                                                               ownerName:CKOwnerDefaultName]];
}

- (instancetype)init
{
    return [self initWithZoneID:[[CKRecordZoneID alloc] initWithZoneName:CKRecordZoneDefaultName
                                                               ownerName:CKOwnerDefaultName]];
}

+ (CKRecordZone *)defaultRecordZone
{
    return [[self alloc] initWithZoneID:[[CKRecordZoneID alloc] initWithZoneName:CKRecordZoneDefaultName
                                                                        ownerName:CKOwnerDefaultName]];
}

+ (instancetype)new
{
    // Measured: the host answers +[CKRecordZone new] with a zone, and its own header marks neither
    // -init nor +new unavailable, so this port does the same and hands back the default zone.
    return [[self alloc] init];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_zoneID forKey:CharonCKKeyRecordZoneID];
    [coder encodeInteger:(NSInteger)_capabilities forKey:CharonCKKeyCapabilities];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self initWithZoneID:[coder decodeObjectOfClass:[CKRecordZoneID class] forKey:CharonCKKeyRecordZoneID]];
    if (self) {
        _capabilities = (CKRecordZoneCapabilities)[coder decodeIntegerForKey:CharonCKKeyCapabilities];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    // capabilities is readonly, so the copy is built with it through the initialiser that takes a zone.
    return [[CKRecordZone allocWithZone:zone] initWithZoneID:_zoneID];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKRecordZone class]]) {
        return NO;
    }
    CKRecordZone *zone = other;
    return [_zoneID isEqual:zone.zoneID] && _capabilities == zone.capabilities;
}

- (NSUInteger)hash
{
    return _zoneID.hash ^ (NSUInteger)_capabilities;
}

- (NSString *)description
{
    NSString *capabilities = @"(none)";
    if (_capabilities != 0) {
        NSMutableArray *named = [NSMutableArray array];
        if (_capabilities & CKRecordZoneCapabilityFetchChanges) {
            [named addObject:@"FetchChanges"];
        }
        if (_capabilities & CKRecordZoneCapabilityAtomic) {
            [named addObject:@"Atomic"];
        }
        if (_capabilities & CKRecordZoneCapabilitySharing) {
            [named addObject:@"Sharing"];
        }
        if (_capabilities & CKRecordZoneCapabilityZoneWideSharing) {
            [named addObject:@"ZoneWideSharing"];
        }
        capabilities = [NSString stringWithFormat:@"(%@)", [named componentsJoinedByString:@"|"]];
    }
    return [NSString stringWithFormat:@"<CKRecordZone: %p; zoneID=%@:%@, capabilities=%@>", self,
            _zoneID.zoneName, _zoneID.ownerName, capabilities];
}

@end

#pragma mark - CKAsset

@implementation CKAsset

- (instancetype)initWithFileURL:(NSURL *)fileURL
{
    self = [super init];
    if (self) {
        _fileURL = [fileURL copy];
    }
    return self;
}

+ (instancetype)new
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKAsset initWithFileURL:] or -[CKAsset initWithData:]", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKAsset initWithFileURL:] or -[CKAsset initWithData:]", nil];
    return nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKAsset: %p; fileURL=%@>", self, _fileURL];
}

@end

#pragma mark - CKReference

@implementation CKReference

- (instancetype)initWithRecordID:(CKRecordID *)recordID action:(CKReferenceAction)action
{
    self = [super init];
    if (self) {
        _recordID = [recordID copy];
        _referenceAction = action;
    }
    return self;
}

- (instancetype)initWithRecord:(CKRecord *)record action:(CKReferenceAction)action
{
    return [self initWithRecordID:record.recordID action:action];
}

+ (instancetype)new
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKReference initWithRecordID:] or -[CKReference initWithRecord:] or -[CKReference initWithAsset:]", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException
                format:@"You must call -[CKReference initWithRecordID:] or -[CKReference initWithRecord:] or -[CKReference initWithAsset:]", nil];
    return nil;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordID forKey:CharonCKKeyRecordZoneID];
    [coder encodeInteger:(NSInteger)_referenceAction forKey:CharonCKKeyReferenceAction];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithRecordID:[coder decodeObjectOfClass:[CKRecordID class] forKey:CharonCKKeyRecordZoneID]
                            action:(CKReferenceAction)[coder decodeIntegerForKey:CharonCKKeyReferenceAction]];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[CKReference allocWithZone:zone] initWithRecordID:_recordID action:_referenceAction];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKReference class]]) {
        return NO;
    }
    CKReference *reference = other;
    return [_recordID isEqual:reference.recordID] && _referenceAction == reference.referenceAction;
}

- (NSUInteger)hash
{
    return _recordID.hash ^ (NSUInteger)_referenceAction;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKReference: %p; recordID=%@, action=%lu>", self, _recordID,
            (unsigned long)_referenceAction];
}

@end

#pragma mark - CKRecord

@implementation CKRecord
{
    NSMutableDictionary *_values;
    NSMutableSet *_changed;
    NSMutableDictionary *_original;
    CKReference *_parent;
    CKReference *_share;
}

- (instancetype)initWithRecordType:(CKRecordType)recordType recordID:(CKRecordID *)recordID
{
    self = [super init];
    if (self) {
        _recordType = [recordType copy];
        _recordID = [recordID copy];
        _values = [NSMutableDictionary dictionary];
        _changed = [NSMutableSet set];
        _original = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithRecordType:(CKRecordType)recordType zoneID:(CKRecordZoneID *)zoneID
{
    return [self initWithRecordType:recordType
                            recordID:[[CKRecordID alloc] initWithRecordName:[[NSUUID UUID] UUIDString] zoneID:zoneID]];
}

- (instancetype)initWithRecordType:(CKRecordType)recordType
{
    return [self initWithRecordType:recordType
                            recordID:[[CKRecordID alloc] initWithRecordName:[[NSUUID UUID] UUIDString]]];
}

+ (instancetype)new
{
    [NSException raise:NSInvalidArgumentException format:@"You must call -[CKRecord initWithRecordType:]", nil];
    return nil;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"You must call -[CKRecord initWithRecordType:]", nil];
    return nil;
}

// A field that is not there answers nil, and a field set to nil is not a change to send: that is the
// rule the host's own -allKeys and -changedKeys agree on, and it is what makes a save idempotent.
- (id)objectForKey:(CKRecordFieldKey)key
{
    return _values[key];
}

- (void)setObject:(id)object forKey:(CKRecordFieldKey)key
{
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"A record field needs a key", nil];
        return;
    }
    if (!object) {
        if (_values[key] == nil) {
            return;
        }
        [_original setObject:_values[key] forKey:key];
        [_values removeObjectForKey:key];
        [_changed removeObject:key];
        return;
    }
    if (!_original[key]) {
        [_original setObject:(id)[NSNull null] forKey:key];
        [_changed addObject:key];
    }
    _values[key] = object;
}

- (id)objectForKeyedSubscript:(CKRecordFieldKey)key
{
    return [self objectForKey:key];
}

- (void)setObject:(id)object forKeyedSubscript:(CKRecordFieldKey)key
{
    [self setObject:object forKey:key];
}

- (NSArray<CKRecordFieldKey> *)allKeys
{
    return [_values.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)allTokens
{
    // Measured: only the string fields, because a token is a string CloudKit can put in a query.
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *key in [self allKeys]) {
        id value = _values[key];
        if ([value isKindOfClass:[NSString class]]) {
            [tokens addObject:value];
        }
    }
    return tokens;
}

- (NSArray<CKRecordFieldKey> *)changedKeys
{
    return [_changed.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (void)encodeSystemFieldsWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordID.recordName forKey:CharonCKKeyRecordName];
    [coder encodeObject:_recordID.zoneID.zoneName forKey:CharonCKKeyZoneName];
    [coder encodeObject:_recordID.zoneID.ownerName forKey:CharonCKKeyOwnerName];
    [coder encodeObject:_recordType forKey:CharonCKKeyRecordTypeKey];
    [coder encodeObject:_creatorUserRecordID.recordName forKey:CKRecordCreatorUserRecordIDKey];
    [coder encodeObject:_lastModifiedUserRecordID.recordName forKey:CKRecordLastModifiedUserRecordIDKey];
    [coder encodeObject:_creationDate forKey:CKRecordCreationDateKey];
    [coder encodeObject:_modificationDate forKey:CKRecordModificationDateKey];
    [coder encodeObject:_recordChangeTag forKey:@"recordChangeTag"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [self encodeSystemFieldsWithCoder:coder];
    [coder encodeObject:_values forKey:CharonCKKeyValues];
    [coder encodeObject:_parent forKey:CKRecordParentKey];
    [coder encodeObject:_share forKey:CKRecordShareKey];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *recordName = [coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyRecordName];
    CKRecordZoneID *zoneID = [[CKRecordZoneID alloc] initWithZoneName:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyZoneName]
                                                             ownerName:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyOwnerName]];
    self = [self initWithRecordType:[coder decodeObjectOfClass:[NSString class] forKey:CharonCKKeyRecordTypeKey]
                            recordID:[[CKRecordID alloc] initWithRecordName:recordName zoneID:zoneID]];
    if (self) {
        _recordChangeTag = [coder decodeObjectOfClass:[NSString class] forKey:@"recordChangeTag"];
        _creationDate = [coder decodeObjectOfClass:[NSDate class] forKey:CKRecordCreationDateKey];
        _modificationDate = [coder decodeObjectOfClass:[NSDate class] forKey:CKRecordModificationDateKey];
        NSString *creator = [coder decodeObjectOfClass:[NSString class] forKey:CKRecordCreatorUserRecordIDKey];
        if (creator) {
            _creatorUserRecordID = [[CKRecordID alloc] initWithRecordName:creator zoneID:zoneID];
        }
        NSString *lastModified = [coder decodeObjectOfClass:[NSString class] forKey:CKRecordLastModifiedUserRecordIDKey];
        if (lastModified) {
            _lastModifiedUserRecordID = [[CKRecordID alloc] initWithRecordName:lastModified zoneID:zoneID];
        }
        NSMutableSet *classes = [NSMutableSet setWithArray:@[[NSDictionary class], [NSString class], [NSNumber class],
                                                         [NSDate class], [NSData class], [NSArray class],
                                                         [CKReference class], [CKAsset class], [CLLocation class]]];
        NSDictionary *values = [coder decodeObjectOfClasses:classes forKey:CharonCKKeyValues];
        if (values) {
            _values = [values mutableCopy];
        }
        _parent = [coder decodeObjectOfClass:[CKReference class] forKey:CKRecordParentKey];
        _share = [coder decodeObjectOfClass:[CKReference class] forKey:CKRecordShareKey];
    }
    return self;
}

- (void)setParentReferenceFromRecord:(CKRecord *)parentRecord
{
    _parent = parentRecord ? [[CKReference alloc] initWithRecordID:parentRecord.recordID
                                                            action:CKReferenceActionDeleteSelf] : nil;
}

- (void)setParentReferenceFromRecordID:(CKRecordID *)parentRecordID
{
    _parent = parentRecordID ? [[CKReference alloc] initWithRecordID:parentRecordID
                                                              action:CKReferenceActionDeleteSelf] : nil;
}

- (id<CKRecordKeyValueSetting>)encryptedValues
{
    // The private fields of a record, which the service holds encrypted and which an application
    // reads back through this and cannot write: a write raises, as the host's own does.
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    CKRecord *copy = [[CKRecord allocWithZone:zone] initWithRecordType:_recordType recordID:_recordID];
    copy->_values = [_values mutableCopy];
    copy->_changed = [_changed mutableCopy];
    copy->_original = [_original mutableCopy];
    copy->_recordChangeTag = _recordChangeTag;
    copy->_creationDate = _creationDate;
    copy->_modificationDate = _modificationDate;
    copy->_creatorUserRecordID = _creatorUserRecordID;
    copy->_lastModifiedUserRecordID = _lastModifiedUserRecordID;
    copy->_parent = _parent;
    copy->_share = _share;
    return copy;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[CKRecord class]]) {
        return NO;
    }
    CKRecord *record = other;
    // CloudKit compares a record by its identity and its system fields, not by the values it holds:
    // two records of the same name in the same zone are the same record whoever wrote them.
    return [_recordID isEqual:record.recordID] && [_recordType isEqualToString:record.recordType] &&
           (_recordChangeTag == record.recordChangeTag ||
            [_recordChangeTag isEqualToString:record.recordChangeTag]);
}

- (NSUInteger)hash
{
    return _recordID.hash ^ _recordType.hash;
}

- (NSString *)description
{
    NSMutableString *text = [NSMutableString stringWithFormat:@"<CKRecord: %p; recordType=%@, recordID=%@:(%@:%@), values={",
                             self, _recordType, _recordID.recordName, _recordID.zoneID.zoneName,
                             _recordID.zoneID.ownerName];
    NSArray *keys = [self allKeys];
    for (NSUInteger index = 0; index < keys.count; index++) {
        [text appendFormat:@"\n    %@ = %@;", keys[index], _values[keys[index]]];
    }
    [text appendString:@"\n}>"];
    return text;
}

@end

// CKShareParticipant is a value of the first release, and the participant a share carries is
// one of them: built, kept and read back, with nothing reaching the network. It sat in
// CKValues10.m beside CKUserIdentity, which is 8.3, and a file carrying 8.0, 8.3 and 10.0.1
// symbols belongs to no band.

#pragma mark - CKShareParticipant

@implementation CKShareParticipant
{
    NSString *_participantID;
}

- (instancetype)initWithType:(CKShareParticipantType)type
{
    self = [super init];
    if (self) {
        _type = type;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKShareParticipant: %p; userIdentity=%@, permission=%ld, role=%ld, type=%ld, acceptanceStatus=%ld, participantID=%@>",
            self, _userIdentity, (long)_permission, (long)_role, (long)_type, (long)_acceptanceStatus, _participantID];
}

@end
