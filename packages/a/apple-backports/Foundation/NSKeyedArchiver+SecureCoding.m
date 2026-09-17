#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NSError *charon_coder_error(NSException *exception, NSInteger code);

static char CharonArchiverDataKey;
static char CharonArchiverFinishedKey;

@implementation NSKeyedArchiver (CharonSecureCoding)

- (instancetype)initRequiringSecureCoding:(BOOL)requiresSecureCoding
{
    NSMutableData *data = [NSMutableData data];
    if ((self = [self initForWritingWithMutableData:data])) {
        self.requiresSecureCoding = requiresSecureCoding;
        objc_setAssociatedObject(self, &CharonArchiverDataKey, data, OBJC_ASSOCIATION_RETAIN);
    }
    return self;
}

- (NSData *)encodedData
{
    NSMutableData *data = objc_getAssociatedObject(self, &CharonArchiverDataKey);
    if (!data)
        [NSException raise:NSInvalidArgumentException format:@"*** -[%@ %@]: the archiver was not created with -initRequiringSecureCoding:", [self class], NSStringFromSelector(_cmd)];
    if (!objc_getAssociatedObject(self, &CharonArchiverFinishedKey)) {
        objc_setAssociatedObject(self, &CharonArchiverFinishedKey, @YES, OBJC_ASSOCIATION_RETAIN);
        [self finishEncoding];
    }
    return [data copy];
}

+ (NSData *)archivedDataWithRootObject:(id)object requiringSecureCoding:(BOOL)requiresSecureCoding error:(NSError **)error
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    archiver.requiresSecureCoding = requiresSecureCoding;
    @try {
        [archiver encodeObject:object forKey:NSKeyedArchiveRootObjectKey];
        [archiver finishEncoding];
    } @catch (NSException *exception) {
        if (error) {
            NSError *underlying = charon_coder_error(exception, NSCoderReadCorruptError);
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSCoderInvalidValueError userInfo:@{NSUnderlyingErrorKey: underlying}];
        }
        return nil;
    }
    return data;
}

@end
