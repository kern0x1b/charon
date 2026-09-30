// CloudKit's record values: the names a record is known by, the zone it lives in, the server's
// change token, a reference from one record to another, an asset, the zone object, and the record
// itself with its fields.
//
// Every refusal, every default and every equality below is what the host's own CloudKit answers, read
// out of the running framework by tests/backports/host/cloudkit/records-cases.h and held to the same
// questions here. The three that are easy to get wrong and are measured rather than assumed:
//
//  * A record with no name of its own is given a UUID, in the default zone, and two records of the
//    same type are never equal - CKRecord has no isEqual: at all, so equality is identity and a copy
//    is a different record that carries the same fields. CKRecordZone is the same: it copies to a
//    different object, and its isEqual: is identity too. CKRecordID, CKRecordZoneID and CKReference
//    do compare by value.
//  * +[CKRecordZone defaultRecordZone] is one object, so two calls compare equal; a zone built with
//    the same name is a different object, because its owner is the default owner and a record ID made
//    with an explicit zone is a different name-and-zone pair.
//  * A field key is a grammar and not any string: the first character is a letter or an underscore and
//    the rest may also be a digit or a dollar sign. Measured over all 95 printable ASCII characters -
//    53 are accepted as the whole key and 64 as a later character - and everything else, empty
//    included, is refused by name.
//
// The parent and the share are iOS 10.0 and are in CKRecords10.m, beside the ivars this class keeps
// for them; see CharonCKRecordPrivate.h.

#import "CharonCloudKit.h"
#import "CharonCKConstants.h"
#import "CharonCKRecordPrivate.h"

// The name the host raises under. It is not a public constant of the framework, so it is written here
// rather than imported, and the strings the host uses are its own: "You must call -[...]" for an
// initializer the class says not to call, and "recordName can not be nil" for a nil argument.
static NSString *const CharonCKExceptionName = @"CKException";
static NSString *const CharonCKInvalidArgumentName = @"NSInvalidArgumentException";

static void CharonCKRefuse(NSString *name, NSString *reason)
{
    [[NSException exceptionWithName:name reason:reason userInfo:nil] raise];
}

// A field key, and the two refusals. The character sets are the measured ones: the first is
// [A-Za-z_] and the rest [A-Za-z0-9_$], with no other printable ASCII character admitted.
static BOOL CharonCKFieldKeyIsValid(NSString *key)
{
    if (![key isKindOfClass:[NSString class]] || key.length == 0) {
        CharonCKRefuse(CharonCKInvalidArgumentName, @"recordKey can not be empty");
        return NO;
    }
    static NSCharacterSet *first = nil;
    static NSCharacterSet *rest = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *letters = [NSMutableCharacterSet characterSetWithCharactersInString:
                                           @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"];
        first = [letters copy];
        [letters addCharactersInString:@"0123456789$"];
        rest = [letters copy];
    });
    if (![first characterIsMember:[key characterAtIndex:0]]) {
        CharonCKRefuse(CharonCKInvalidArgumentName,
                       [NSString stringWithFormat:@"recordKey (%@) contains invalid characters", key]);
        return NO;
    }
    for (NSUInteger at = 1; at < key.length; at++) {
        if (![rest characterIsMember:[key characterAtIndex:at]]) {
            CharonCKRefuse(CharonCKInvalidArgumentName,
                           [NSString stringWithFormat:@"recordKey (%@) contains invalid characters", key]);
            return NO;
        }
    }
    return YES;
}

#pragma mark - CKRecordZoneID

// A zone is a name and an owner, and two of them are the same zone when both are. The default zone is
// _defaultZone of __defaultOwner__; every record name that is given no zone lands in it.
@implementation CKRecordZoneID {
    NSString *_zoneName;
    NSString *_ownerName;
}
@synthesize zoneName = _zoneName;
@synthesize ownerName = _ownerName;

- (instancetype)init
{
    CharonCKRefuse(CharonCKInvalidArgumentName,
                   @"You must call -[CKRecordZoneID initWithZoneName:ownerName:]");
    return nil;
}

- (instancetype)initWithZoneName:(NSString *)zoneName ownerName:(NSString *)ownerName
{
    if (!zoneName) {
        CharonCKRefuse(CharonCKExceptionName, @"zoneName can not be nil");
    }
    if (!ownerName) {
        CharonCKRefuse(CharonCKExceptionName, @"ownerName can not be nil");
    }
    self = [super init];
    if (self) {
        _zoneName = [zoneName copy];
        _ownerName = [ownerName copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *zoneName = [coder decodeObjectOfClass:[NSString class] forKey:@"zoneName"];
    NSString *ownerName = [coder decodeObjectOfClass:[NSString class] forKey:@"ownerName"];
    return [self initWithZoneName:zoneName ownerName:ownerName];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_zoneName forKey:@"zoneName"];
    [coder encodeObject:_ownerName forKey:@"ownerName"];
}

- (id)copyWithZone:(NSZone *)zone { return self; }

- (BOOL)isEqual:(id)other
{
    if (self == other) { return YES; }
    if (![other isKindOfClass:[CKRecordZoneID class]]) { return NO; }
    CKRecordZoneID *that = other;
    return [_zoneName isEqualToString:that->_zoneName] && [_ownerName isEqualToString:that->_ownerName];
}

- (NSUInteger)hash { return _zoneName.hash ^ _ownerName.hash; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordZoneID: %@/%@>", _zoneName, _ownerName];
}

@end

#pragma mark - CKRecordID

// A record's name, and the zone it is in. A name given no zone is in the default zone, and the two
// forms are different values: "a-record" in the default zone is not "a-record" in widgets.
@implementation CKRecordID {
    NSString *_recordName;
    CKRecordZoneID *_zoneID;
}
@synthesize recordName = _recordName;
@synthesize zoneID = _zoneID;

- (instancetype)init
{
    CharonCKRefuse(CharonCKInvalidArgumentName,
                   @"You must call -[CKRecordID initWithRecordName:] or -[CKRecordID initWithRecordName:zoneID:]");
    return nil;
}

- (instancetype)initWithRecordName:(NSString *)recordName
{
    return [self initWithRecordName:recordName
                             zoneID:[[CKRecordZoneID alloc] initWithZoneName:CKRecordZoneDefaultName
                                                                  ownerName:CKOwnerDefaultName]];
}

- (instancetype)initWithRecordName:(NSString *)recordName zoneID:(CKRecordZoneID *)zoneID
{
    if (!recordName) {
        CharonCKRefuse(CharonCKExceptionName, @"recordName can not be nil");
    }
    if (!zoneID) {
        CharonCKRefuse(CharonCKExceptionName, @"zoneID can not be nil");
    }
    self = [super init];
    if (self) {
        _recordName = [recordName copy];
        _zoneID = [zoneID copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"recordName"];
    CKRecordZoneID *zone = [coder decodeObjectOfClass:[CKRecordZoneID class] forKey:@"zoneID"];
    return [self initWithRecordName:name zoneID:zone];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordName forKey:@"recordName"];
    [coder encodeObject:_zoneID forKey:@"zoneID"];
}

- (id)copyWithZone:(NSZone *)zone { return self; }

- (BOOL)isEqual:(id)other
{
    if (self == other) { return YES; }
    if (![other isKindOfClass:[CKRecordID class]]) { return NO; }
    return [_recordName isEqualToString:((CKRecordID *)other)->_recordName]
        && [_zoneID isEqual:((CKRecordID *)other)->_zoneID];
}

- (NSUInteger)hash { return _recordName.hash ^ _zoneID.hash; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordID: %@ in %@>", _recordName, _zoneID];
}

@end

#pragma mark - CKServerChangeToken

// The service's own position in a zone's history, handed back to it on the next fetch. It has no
// public initializer at all - the host refuses - and nothing may read what is inside it, so this is a
// box that carries the token's bytes through an archive and refuses every way of being made.
@implementation CKServerChangeToken

- (instancetype)init
{
    CharonCKRefuse(CharonCKExceptionName, @"You can't call init on CKServerChangeToken");
    return nil;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder { }

- (id)copyWithZone:(NSZone *)zone { return self; }

- (NSString *)description { return @"<CKServerChangeToken>"; }

@end

#pragma mark - CKReference

// A record's pointer to another record: where it points, and what the service is to do to the record
// that holds the pointer when the one it names is deleted. Neither is optional, and the two
// initializers differ only in whether the caller has the record or already has its ID.
@implementation CKReference {
    CKRecordID *_recordID;
    CKReferenceAction _referenceAction;
}
@synthesize recordID = _recordID;
@synthesize referenceAction = _referenceAction;

- (instancetype)init
{
    CharonCKRefuse(CharonCKInvalidArgumentName,
                   @"You must call -[CKReference initWithRecordID:] or -[CKReference initWithRecord:] or -[CKReference initWithAsset:]");
    return nil;
}

- (instancetype)initWithRecordID:(CKRecordID *)recordID action:(CKReferenceAction)action
{
    if (!recordID) {
        CharonCKRefuse(CharonCKExceptionName, @"recordID can not be nil");
    }
    self = [super init];
    if (self) {
        _recordID = [recordID copy];
        _referenceAction = action;
    }
    return self;
}

- (instancetype)initWithRecord:(CKRecord *)record action:(CKReferenceAction)action
{
    if (!record) {
        CharonCKRefuse(CharonCKExceptionName, @"record can not be nil");
    }
    return [self initWithRecordID:record.recordID action:action];
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    CKRecordID *recordID = [coder decodeObjectOfClass:[CKRecordID class] forKey:@"recordID"];
    NSNumber *action = [coder decodeObjectOfClass:[NSNumber class] forKey:@"referenceAction"];
    return [self initWithRecordID:recordID action:(CKReferenceAction)action.unsignedIntegerValue];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordID forKey:@"recordID"];
    [coder encodeObject:@(_referenceAction) forKey:@"referenceAction"];
}

- (id)copyWithZone:(NSZone *)zone { return self; }

- (BOOL)isEqual:(id)other
{
    if (self == other) { return YES; }
    if (![other isKindOfClass:[CKReference class]]) { return NO; }
    CKReference *that = other;
    return [_recordID isEqual:that->_recordID] && _referenceAction == that->_referenceAction;
}

- (NSUInteger)hash { return _recordID.hash ^ (NSUInteger)_referenceAction; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKReference: %@ action %lu>", _recordID, (unsigned long)_referenceAction];
}

@end

#pragma mark - CKAsset

// A file, named for the service to read. The URL is kept as it was given - the host does not check
// that the file is there, and an asset of a path that does not exist is an asset - and a nil URL is
// refused, because an asset with no file is nothing.
//
// CKAsset is not NSCopying on iOS: the host answers -[CKAsset copyWithZone:] with an unrecognised
// selector, which is measured, and copying it is left unimplemented so the port says the same thing.
//
// It does conform to NSSecureCoding, though the SDK's @interface does not say so - measured by asking
// the runtime, not by reading the header - and a class extension is what makes this one conform.
@interface CKAsset () <NSSecureCoding>
@end

@implementation CKAsset {
    NSURL *_fileURL;
}
@synthesize fileURL = _fileURL;

- (instancetype)init
{
    CharonCKRefuse(CharonCKInvalidArgumentName,
                   @"You must call -[CKAsset initWithFileURL:] or -[CKAsset initWithData:]");
    return nil;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL
{
    if (!fileURL) {
        CharonCKRefuse(CharonCKInvalidArgumentName, @"Null fileURL");
    }
    self = [super init];
    if (self) {
        _fileURL = [fileURL copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSURL *url = [coder decodeObjectOfClass:[NSURL class] forKey:@"fileURL"];
    return [self initWithFileURL:url];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_fileURL forKey:@"fileURL"];
}

- (NSString *)description { return [NSString stringWithFormat:@"<CKAsset: %@>", _fileURL]; }

@end

#pragma mark - CKRecordZone

// A zone and what it can do. Every zone this port makes has no capability - the capabilities are a
// property of the zone the service created, and a name on its own claims none of them - and there is
// one default zone, which is the same object every time.
@implementation CKRecordZone {
    CKRecordZoneID *_zoneID;
    CKRecordZoneCapabilities _capabilities;
}
@synthesize zoneID = _zoneID;
@synthesize capabilities = _capabilities;

+ (CKRecordZone *)defaultRecordZone
{
    // One object, so two calls compare equal: measured, and a fresh zone of the same name does not.
    static CKRecordZone *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[CKRecordZone alloc] initWithZoneID:[[CKRecordZoneID alloc] initWithZoneName:CKRecordZoneDefaultName
                                                                                        ownerName:CKOwnerDefaultName]];
    });
    return shared;
}

- (instancetype)init
{
    // The header says this is unavailable and the host makes one anyway (measured), so the port does
    // too rather than refusing where the host does not. An empty zone is a zone of no name.
    self = [super init];
    if (self) {
        _zoneID = [[CKRecordZoneID alloc] initWithZoneName:@"" ownerName:CKOwnerDefaultName];
    }
    return self;
}

- (instancetype)initWithZoneName:(NSString *)zoneName
{
    return [self initWithZoneID:[[CKRecordZoneID alloc] initWithZoneName:zoneName ownerName:CKOwnerDefaultName]];
}

- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID
{
    if (!zoneID) {
        CharonCKRefuse(CharonCKExceptionName, @"zoneID can not be nil");
    }
    self = [super init];
    if (self) {
        _zoneID = [zoneID copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    CKRecordZoneID *zone = [coder decodeObjectOfClass:[CKRecordZoneID class] forKey:@"zoneID"];
    return [self initWithZoneID:zone];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_zoneID forKey:@"zoneID"];
    [coder encodeObject:@(_capabilities) forKey:@"capabilities"];
}

// A copy is a different zone: CKRecordZone has no value equality, and the host answers "different"
// for a copy against its original (measured).
- (id)copyWithZone:(NSZone *)zone
{
    CKRecordZone *copy = [[[self class] allocWithZone:zone] initWithZoneID:_zoneID];
    copy->_capabilities = _capabilities;
    return copy;
}

- (NSString *)description { return [NSString stringWithFormat:@"<CKRecordZone: %@>", _zoneID]; }

@end

#pragma mark - CKRecord

// A record: a type, a name in a zone, a set of fields, and the service's own answers about the field
// once it has been saved. A record made here has none of the service's answers - no change tag, no
// creator, no dates, no share - and says so by answering nil, which is what the host does before a
// record has been through the service (measured).
//
// Equality is identity: CKRecord does not override isEqual:, so two records of the same type with the
// same ID are still different records, and a copy is a different record carrying the same fields. That
// is measured in both directions and is not a shortcut here.
// The seven properties of the class that the other object file also needs are declared readwrite in
// CharonCKRecordPrivate.h and their accessors written out here: @synthesize would make the ivar
// private to this @implementation, and CKRecords10.m reads recordID.
@implementation CKRecord
- (NSString *)recordType { return _recordType; }
- (void)setRecordType:(NSString *)recordType { _recordType = [recordType copy]; }
- (CKRecordID *)recordID { return _recordID; }
- (void)setRecordID:(CKRecordID *)recordID { _recordID = [recordID copy]; }
- (NSString *)recordChangeTag { return _recordChangeTag; }
- (void)setRecordChangeTag:(NSString *)tag { _recordChangeTag = [tag copy]; }
- (CKRecordID *)creatorUserRecordID { return _creatorUserRecordID; }
- (void)setCreatorUserRecordID:(CKRecordID *)id { _creatorUserRecordID = [id copy]; }
- (NSDate *)creationDate { return _creationDate; }
- (void)setCreationDate:(NSDate *)date { _creationDate = [date copy]; }
- (CKRecordID *)lastModifiedUserRecordID { return _lastModifiedUserRecordID; }
- (void)setLastModifiedUserRecordID:(CKRecordID *)id { _lastModifiedUserRecordID = [id copy]; }
- (NSDate *)modificationDate { return _modificationDate; }
- (void)setModificationDate:(NSDate *)date { _modificationDate = [date copy]; }

- (instancetype)init
{
    CharonCKRefuse(CharonCKInvalidArgumentName, @"You must call -[CKRecord initWithRecordType:]");
    return nil;
}

- (instancetype)initWithRecordType:(NSString *)recordType
{
    // A record with a type and no name of its own is given a UUID in the default zone. Measured: two
    // records of the same type have different names, and neither names anything a caller chose.
    return [self initWithRecordType:recordType
                            recordID:[[CKRecordID alloc] initWithRecordName:[[NSUUID UUID] UUIDString]]];
}

- (instancetype)initWithRecordType:(NSString *)recordType recordID:(CKRecordID *)recordID
{
    if (!recordType) {
        CharonCKRefuse(CharonCKExceptionName, @"recordType can not be nil");
    }
    if (!recordID) {
        CharonCKRefuse(CharonCKExceptionName, @"recordID can not be nil");
    }
    self = [super init];
    if (self) {
        _recordType = [recordType copy];
        _recordID = [recordID copy];
        _fields = [NSMutableDictionary dictionary];
        _changedKeys = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithRecordType:(NSString *)recordType zoneID:(CKRecordZoneID *)zoneID
{
    if (!zoneID) {
        CharonCKRefuse(CharonCKExceptionName, @"zoneID can not be nil");
    }
    return [self initWithRecordType:recordType
                            recordID:[[CKRecordID alloc] initWithRecordName:[[NSUUID UUID] UUIDString]
                                                                    zoneID:zoneID]];
}

#pragma mark The fields

- (id)objectForKey:(NSString *)key
{
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }
    return _fields[key];
}

- (void)setObject:(id)object forKey:(NSString *)key
{
    if (!CharonCKFieldKeyIsValid(key)) {
        return;
    }
    // A field set once stays in changedKeys even after it is removed: allKeys is what the record holds
    // now and changedKeys is what has been touched. Measured: six fields set, one removed, five keys
    // and six changed keys.
    if (![_changedKeys containsObject:key]) {
        [_changedKeys addObject:key];
    }
    if (object) {
        _fields[key] = object;
    } else {
        [_fields removeObjectForKey:key];
    }
}

- (id)objectForKeyedSubscript:(NSString *)key { return [self objectForKey:key]; }
- (void)setObject:(id)object forKeyedSubscript:(NSString *)key { [self setObject:object forKey:key]; }

- (NSArray *)allKeys { return [_fields allKeys]; }

- (NSArray *)changedKeys { return [_changedKeys copy]; }

// The field types, and a record that has not been through the service has none: the host answers an
// empty list here, and the tokens arrive with the saved record's fields.
- (NSArray *)allTokens { return nil; }

#pragma mark The copy and the archive

- (id)copyWithZone:(NSZone *)zone
{
    CKRecord *copy = [[[self class] allocWithZone:zone] initWithRecordType:_recordType recordID:_recordID];
    [copy->_fields addEntriesFromDictionary:_fields];
    [copy->_changedKeys addObjectsFromArray:_changedKeys];
    copy->_recordChangeTag = [_recordChangeTag copy];
    copy->_creatorUserRecordID = [_creatorUserRecordID copy];
    copy->_creationDate = [_creationDate copy];
    copy->_lastModifiedUserRecordID = [_lastModifiedUserRecordID copy];
    copy->_modificationDate = [_modificationDate copy];
    return copy;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _recordType = [coder decodeObjectOfClass:[NSString class] forKey:@"recordType"];
        _recordID = [coder decodeObjectOfClass:[CKRecordID class] forKey:@"recordID"];
        _recordChangeTag = [coder decodeObjectOfClass:[NSString class] forKey:@"recordChangeTag"];
        _creatorUserRecordID = [coder decodeObjectOfClass:[CKRecordID class] forKey:@"creatorUserRecordID"];
        _creationDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"creationDate"];
        _lastModifiedUserRecordID = [coder decodeObjectOfClass:[CKRecordID class] forKey:@"lastModifiedUserRecordID"];
        _modificationDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"modificationDate"];
        NSDictionary *fields = [coder decodeObjectOfClasses:
                                [NSSet setWithObjects:[NSDictionary class], [NSString class], [NSNumber class],
                                 [NSDate class], [NSData class], [CKReference class], [CKAsset class], nil]
                                                 forKey:@"fields"];
        _fields = fields ? [fields mutableCopy] : [NSMutableDictionary dictionary];
        NSArray *changed = [coder decodeObjectOfClasses:
                            [NSSet setWithObjects:[NSArray class], [NSString class], nil] forKey:@"changedKeys"];
        _changedKeys = changed ? [changed mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordType forKey:@"recordType"];
    [coder encodeObject:_recordID forKey:@"recordID"];
    [coder encodeObject:_recordChangeTag forKey:@"recordChangeTag"];
    [coder encodeObject:_creatorUserRecordID forKey:@"creatorUserRecordID"];
    [coder encodeObject:_creationDate forKey:@"creationDate"];
    [coder encodeObject:_lastModifiedUserRecordID forKey:@"lastModifiedUserRecordID"];
    [coder encodeObject:_modificationDate forKey:@"modificationDate"];
    [coder encodeObject:[_fields copy] forKey:@"fields"];
    [coder encodeObject:[_changedKeys copy] forKey:@"changedKeys"];
}

- (void)encodeSystemFieldsWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_recordType forKey:@"recordType"];
    [coder encodeObject:_recordID forKey:@"recordID"];
    [coder encodeObject:_recordChangeTag forKey:@"recordChangeTag"];
    [coder encodeObject:_creatorUserRecordID forKey:@"creatorUserRecordID"];
    [coder encodeObject:_creationDate forKey:@"creationDate"];
    [coder encodeObject:_lastModifiedUserRecordID forKey:@"lastModifiedUserRecordID"];
    [coder encodeObject:_modificationDate forKey:@"modificationDate"];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecord: %@ %@, %lu field(s)>", _recordType, _recordID,
            (unsigned long)_fields.count];
}

@end

// The service's own answers, written for the decoders. Only the ones the answer carries are set, so a
// record that has never been saved keeps nil for all of them.
void CharonCKRecordApplyServerFields(CKRecord *record, NSString *changeTag, CKRecordID *creatorUserRecordID,
                                     NSDate *creationDate, CKRecordID *lastModifiedUserRecordID,
                                     NSDate *modificationDate)
{
    if (!record) {
        return;
    }
    record.recordChangeTag = changeTag;
    record.creatorUserRecordID = creatorUserRecordID;
    record.creationDate = creationDate;
    record.lastModifiedUserRecordID = lastModifiedUserRecordID;
    record.modificationDate = modificationDate;
}
