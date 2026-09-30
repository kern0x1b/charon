// CKRecord's parent and its share, which arrived in iOS 10.0, beside the rest of the class's surface
// in CKRecords8.m.
//
// The build refuses one object that holds the API of more than one release, and this is the half of
// CKRecord that is 10.0: the record type, the name, the fields and the copy are 8.0 and are in
// CKRecords8.m. The ivars the two share are in CharonCKRecordPrivate.h, because a class extension in
// one .m file is not visible to the other.
//
// A parent names the record this one hangs under, and the service refuses a parent in another zone
// with NSInternalInconsistencyException - "Parent record must be in the same zone as the current
// record" - which is the host's own wording and is measured. A nil parent clears it. The share is the
// reference the record is published through; it is nil until the service says otherwise.

#import "CharonCloudKit.h"
#import "CharonCKConstants.h"
#import "CharonCKRecordPrivate.h"

@implementation CKRecord (CharonCKParent)

// A property in a named category cannot be @synthesize'd in the category's implementation - the
// compiler rejects it, and the class's own implementation is in another file - so the two accessors
// are written out and read the ivars directly. That is the same shape the port uses for the other
// release-split classes.
- (CKReference *)parent
{
    return _parent;
}

- (void)setParent:(CKReference *)parent
{
    _parent = [parent copy];
}

- (CKReference *)share
{
    return _share;
}

- (void)setParentReferenceFromRecordID:(CKRecordID *)parentRecordID
{
    if (!parentRecordID) {
        _parent = nil;
        return;
    }
    if (![_recordID.zoneID isEqual:parentRecordID.zoneID]) {
        [[NSException exceptionWithName:NSInternalInconsistencyException
                                reason:@"Parent record must be in the same zone as the current record"
                              userInfo:nil] raise];
    }
    _parent = [[CKReference alloc] initWithRecordID:parentRecordID action:CKReferenceActionDeleteSelf];
}

- (void)setParentReferenceFromRecord:(CKRecord *)parentRecord
{
    if (!parentRecord) {
        _parent = nil;
        return;
    }
    [self setParentReferenceFromRecordID:parentRecord.recordID];
}

@end
