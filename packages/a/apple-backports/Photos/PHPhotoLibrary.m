#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void charon_deliver_authorization(void (^handler)(PHAuthorizationStatus status))
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        handler((PHAuthorizationStatus)[ALAssetsLibrary authorizationStatus]);
    });
}

@implementation PHPhotoLibrary

@dynamic currentChangeToken, unavailabilityReason;

+ (PHPhotoLibrary *)sharedPhotoLibrary
{
    static PHPhotoLibrary *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = ((id (*)(id, SEL))objc_msgSend)([self alloc], sel_registerName("init"));
    });
    return shared;
}

+ (PHAuthorizationStatus)authorizationStatus
{
    return (PHAuthorizationStatus)[ALAssetsLibrary authorizationStatus];
}

+ (void)requestAuthorization:(void (^)(PHAuthorizationStatus status))handler
{
    void (^kept)(PHAuthorizationStatus) = [handler copy];
    if ([ALAssetsLibrary authorizationStatus] != ALAuthorizationStatusNotDetermined) {
        charon_deliver_authorization(kept);
        return;
    }
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    __block BOOL answered = NO;
    void (^answer)(void) = ^{
        if (answered)
            return;
        answered = YES;
        charon_deliver_authorization(kept);
    };
    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        *stop = YES;
        answer();
    } failureBlock:^(NSError *error) {
        answer();
    }];
}

+ (PHAuthorizationStatus)authorizationStatusForAccessLevel:(PHAccessLevel)accessLevel
{
    return [self authorizationStatus];
}

+ (void)requestAuthorizationForAccessLevel:(PHAccessLevel)accessLevel handler:(void (^)(PHAuthorizationStatus status))handler
{
    [self requestAuthorization:handler];
}

@end
