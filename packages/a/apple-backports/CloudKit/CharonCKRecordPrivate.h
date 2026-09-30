// CKRecord's private storage, shared by the two objects that carry the class.
//
// CKRecord's own surface arrived in two releases: the record type, the name, the fields and the copy
// are iOS 8.0, and the parent and the share are iOS 10.0. The build refuses one object that holds the
// API of more than one release, so the class is in two - CKRecords8.m and CKRecords10.m - and what
// spans them is declared here: the properties are the SDK's readonly ones redeclared readwrite, which
// is what gives each of them an ivar both files can see, and each accessor is written out rather than
// @synthesize'd because a synthesized ivar is private to its own @implementation.
//
// This header is not installed. The class's own surface is the device SDK's, and nothing here is
// CloudKit API.

#import "CharonCloudKit.h"

@interface CKRecord () {
    // The ivars, declared here rather than left to @synthesize, because a synthesized ivar is private
    // to the @implementation that made it and CKRecords10.m has to read two of these.
    NSString *_recordType;
    CKRecordID *_recordID;
    NSString *_recordChangeTag;
    CKRecordID *_creatorUserRecordID;
    NSDate *_creationDate;
    CKRecordID *_lastModifiedUserRecordID;
    NSDate *_modificationDate;
    // The parent of the record, and the share that publishes it. Both are 10.0, both are nil until set,
    // and both are the references the setters in CKRecords10.m build.
    CKReference *_parent;
    CKReference *_share;
    // The fields, in the order they were first set, and the keys that were ever set - which is not the
    // same set: a field set and then removed stays in changedKeys and leaves allKeys. Measured, not
    // assumed: after setting six fields and removing one, allKeys holds five and changedKeys holds six.
    NSMutableDictionary *_fields;
    NSMutableArray *_changedKeys;
}
// The SDK declares these readonly; they are readwrite here so the accessors written out in the two
// object files are implementations of something rather than a second definition of the property.
@property (nonatomic, copy) NSString *recordType;
@property (nonatomic, copy) CKRecordID *recordID;
@property (nonatomic, copy, nullable) NSString *recordChangeTag;
@property (nonatomic, copy, nullable) CKRecordID *creatorUserRecordID;
@property (nonatomic, copy, nullable) NSDate *creationDate;
@property (nonatomic, copy, nullable) CKRecordID *lastModifiedUserRecordID;
@property (nonatomic, copy, nullable) NSDate *modificationDate;
// `share` and `parent` are not redeclared: the SDK already declares them, and both are implemented by
// hand in CKRecords10.m, so what that file needs from here is the ivar, which is above.
@end

// The service's own answers about a record, written for the decoders in CharonCKRecords.m. They are
// the class's private state and its properties are readonly, so the record's own object file writes
// them and the decoders ask. This is internal to the package and is not a CloudKit API.
extern void CharonCKRecordApplyServerFields(CKRecord *record, NSString *_Nullable changeTag,
                                            CKRecordID *_Nullable creatorUserRecordID,
                                            NSDate *_Nullable creationDate,
                                            CKRecordID *_Nullable lastModifiedUserRecordID,
                                            NSDate *_Nullable modificationDate);
