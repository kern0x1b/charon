// HKCDADocument, the document a CDA document sample holds.
//
// The class is of iOS 11.0, not of 10.0: the corpus dates HKCDADocumentSample and its members to 10.0 by
// the version of the class they sit in, and the class itself arrived a release later. So the document
// is a file of its own, of 11.0, and the 10.0 group that the corpus dated its five members to does not
// carry them. That is the release check the gate runs, finding HKDocument10.m holding two releases.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@interface HKCDADocument (CharonIOS11)
- (instancetype)charon_initWithDocumentData:(NSData *)documentData
                                      title:(nullable NSString *)title
                                 patientName:(nullable NSString *)patientName
                                  authorName:(nullable NSString *)authorName
                               custodianName:(nullable NSString *)custodianName;
@end

@implementation HKCDADocument {
    NSData *_documentData;
    NSString *_title;
    NSString *_patientName;
    NSString *_authorName;
    NSString *_custodianName;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)charon_initWithDocumentData:(NSData *)documentData
                                      title:(nullable NSString *)title
                                 patientName:(nullable NSString *)patientName
                                  authorName:(nullable NSString *)authorName
                               custodianName:(nullable NSString *)custodianName
{
    HKCDADocument *document = [super init];
    if (document) {
        document->_documentData = [documentData copy];
        document->_title = [title copy];
        document->_patientName = [patientName copy];
        document->_authorName = [authorName copy];
        document->_custodianName = [custodianName copy];
    }
    return document;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    HKCDADocument *document = [super init];
    if (document) {
        document->_documentData = [[coder decodeObjectOfClass:[NSData class] forKey:@"documentData"] copy];
        document->_title = [[coder decodeObjectOfClass:[NSString class] forKey:@"title"] copy];
        document->_patientName = [[coder decodeObjectOfClass:[NSString class] forKey:@"patientName"] copy];
        document->_authorName = [[coder decodeObjectOfClass:[NSString class] forKey:@"authorName"] copy];
        document->_custodianName = [[coder decodeObjectOfClass:[NSString class] forKey:@"custodianName"] copy];
    }
    return document;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_documentData forKey:@"documentData"];
    [coder encodeObject:_title forKey:@"title"];
    [coder encodeObject:_patientName forKey:@"patientName"];
    [coder encodeObject:_authorName forKey:@"authorName"];
    [coder encodeObject:_custodianName forKey:@"custodianName"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[HKCDADocument alloc] charon_initWithDocumentData:_documentData
                                                       title:_title
                                                  patientName:_patientName
                                                   authorName:_authorName
                                                custodianName:_custodianName];
}

- (NSData *)documentData
{
    return _documentData;
}

- (NSString *)title
{
    return _title;
}

- (NSString *)patientName
{
    return _patientName;
}

- (NSString *)authorName
{
    return _authorName;
}

- (NSString *)custodianName
{
    return _custodianName;
}

- (BOOL)isEqual:(id)other
{
    if (self == other)
        return YES;
    if (![other isKindOfClass:[HKCDADocument class]])
        return NO;
    HKCDADocument *that = other;
    return [_documentData isEqualToData:that.documentData] && (_title == that.title || [_title isEqualToString:that.title])
           && (_patientName == that.patientName || [_patientName isEqualToString:that.patientName])
           && (_authorName == that.authorName || [_authorName isEqualToString:that.authorName])
           && (_custodianName == that.custodianName || [_custodianName isEqualToString:that.custodianName]);
}

- (NSUInteger)hash
{
    return _documentData.hash ^ _title.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKCDADocument[%@ %lu bytes]", _title, (unsigned long)_documentData.length];
}

@end
