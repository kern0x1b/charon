#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "CharonAVMetadataConstruction.h"

// AVMetadataItemFilter, iOS 7.
//
// A filter is a list of metadata identifiers and nothing else: -identifiers answers it, and
// +metadataItemFilterWithIdentifiers: makes one. There is no public initializer on this build - the
// class cluster's only method is -allowList, and the 7.0 members are gone from the SDK - so the port
// carries the class, the 7.0 spelling and the current spelling, and the header's
// +metadataItemFilterForSharing.
//
// The list is stored once, copied in, and answered under BOTH names. That is the whole design and it
// is what makes the row honest in both directions: an application written for 7.0 calls
// -identifiers and gets the list it passed, and one written for a current release calls -allowList and
// gets the same list, because they are the same ivar and not two that can disagree.

// The ivar, in a class extension: readonly storage that a subclass could override, and nothing else.
@interface AVMetadataItemFilter ()
@property (nonatomic, copy) NSArray<AVMetadataIdentifier> *charonIdentifiers;
@end

@implementation AVMetadataItemFilter

@synthesize charonIdentifiers = _charonIdentifiers;

// The header marks -init NS_UNAVAILABLE, a compile-time steer toward Apple's own factory, which this
// port does not reach and which the release has no use for either. The real -init is what a plain
// objc_msgSend below still needs, so it is called through one.
- (instancetype)charon_initWithIdentifiers:(NSArray<AVMetadataIdentifier> *)identifiers
{
    self = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("init"));
    if (self) {
        _charonIdentifiers = [identifiers copy] ?: @[];
    }
    return self;
}

+ (instancetype)charon_metadataItemFilterWithIdentifiers:(NSArray<AVMetadataIdentifier> *)identifiers
{
    return [[self alloc] charon_initWithIdentifiers:identifiers];
}

- (NSArray<AVMetadataIdentifier> *)identifiers
{
    return self.charonIdentifiers ?: @[];
}

- (NSArray<AVMetadataIdentifier> *)allowList
{
    return self.charonIdentifiers ?: @[];
}

// The header's own: a filter that keeps everything, which is the empty allow list.
+ (instancetype)metadataItemFilterForSharing
{
    return [self charon_metadataItemFilterWithIdentifiers:@[]];
}

@end
