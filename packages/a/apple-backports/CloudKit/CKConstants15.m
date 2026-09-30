// What iOS 15 added: the key that tells a CKErrorZoneNotFound whether the user reset the
// encrypted data of their account, and the record type a zone's whole contents are shared under.
// Both values are the ones the host's own CloudKit hands out; see facts/CloudKit/Values.md.

#import <CloudKit/CloudKit.h>

NSString *const CKErrorUserDidResetEncryptedDataKey = @"CKUserDidResetEncryptedData";
NSString *const CKRecordNameZoneWideShare = @"cloudkit.zoneshare";
