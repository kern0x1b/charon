#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import "CharonPhotos.h"

// PHPhotoLibrary's library availability, of iOS 13. One object for one release: the class members of
// the other releases are in their own files, and this one carries nothing of another.
//
// iOS 6 says the state of the photo library in two ways, and these answer from the two: the
// authorization ALAssetsLibrary reports, which the port's +[PHPhotoLibrary authorizationStatus] is
// already made of, and the refusal its own enumeration answers with when the library cannot be read.
// There is no third. The release has no way to be told that a volume went away, and the port does not
// invent one: the codes Apple's header gives for those events (3114, 3142, 3143) are named in
// facts/Photos/Availability.md as unreachable here, with the measurement that says so.
//
// The codes here are the header's own, for the cases the header gives them: PHPhotosErrorAccessUserDenied
// (3311) for a denied process and PHPhotosErrorAccessRestricted (3310) for a restricted one, both in
// the domain the header declares them in, PHPhotosErrorDomain.

@interface PHPhotoLibrary (CharonAvailability)
- (void)charon_availabilityRefreshed;
@end

@implementation PHPhotoLibrary (CharonAvailability)

// 0: available to this process. 1: denied. 2: restricted.
+ (NSInteger)charon_unavailabilityOfRelease
{
    switch ([ALAssetsLibrary authorizationStatus]) {
        case ALAuthorizationStatusRestricted:
            return 2;
        case ALAuthorizationStatusDenied:
            return 1;
        default:
            return 0;
    }
}

+ (NSError *)charon_unavailabilityReasonOf:(NSInteger)state
{
    switch (state) {
        case 1:
            return [NSError errorWithDomain:PHPhotosErrorDomain code:PHPhotosErrorAccessUserDenied
                                   userInfo:@{NSLocalizedDescriptionKey: @"the user has denied access to the photo library"}];
        case 2:
            return [NSError errorWithDomain:PHPhotosErrorDomain code:PHPhotosErrorAccessRestricted
                                   userInfo:@{NSLocalizedDescriptionKey: @"access to the photo library is restricted by system configuration"}];
        default:
            return nil;
    }
}

// A transition, not a state. An observer registered while the library is already unavailable is not
// told about it: "did become unavailable" is about a change, and a registration is otherwise a second
// way of asking for -[PHPhotoLibrary unavailabilityReason], which answers it.
- (void)charon_availabilityBecame:(NSInteger)state
{
    NSArray *observers;
    @synchronized(self) {
        NSInteger before = _lastAvailability;
        _lastAvailability = state;
        if (before == state || before != 0 || state == 0)
            return;
        observers = _availabilityObservers.allObjects;
    }
    if (observers.count == 0)
        return;
    // "This notification is posted on a private queue" (PHPhotoLibrary.h:45), which the header says
    // of the availability observers and of nothing else here; one serial queue of the port's own is.
    dispatch_async(_availabilityDelivery, ^{
        for (id<PHPhotoLibraryAvailabilityObserver> observer in observers)
            [observer photoLibraryDidBecomeUnavailable:[PHPhotoLibrary sharedPhotoLibrary]];
    });
}

- (void)charon_availabilityRefreshed
{
    [self charon_availabilityBecame:[PHPhotoLibrary charon_unavailabilityOfRelease]];
}

- (NSError *)unavailabilityReason
{
    // Reading the reason is one of the two ways the port learns of a change: a denied process is told
    // no more than that, since the release posts nothing it cannot read.
    [self charon_availabilityRefreshed];
    return [PHPhotoLibrary charon_unavailabilityReasonOf:[PHPhotoLibrary charon_unavailabilityOfRelease]];
}

- (void)registerAvailabilityObserver:(id<PHPhotoLibraryAvailabilityObserver>)observer
{
    if (!observer)
        return;
    @synchronized(self) {
        if (!_availabilityObservers) {
            _availabilityObservers = [NSHashTable weakObjectsHashTable];
            _availabilityDelivery = dispatch_queue_create("space.kern0x1b.photos.availability", DISPATCH_QUEUE_SERIAL);
            _lastAvailability = [PHPhotoLibrary charon_unavailabilityOfRelease];
            __weak PHPhotoLibrary *weakSelf = self;
            _availabilityListening = [[NSNotificationCenter defaultCenter] addObserverForName:ALAssetsLibraryChangedNotification
                                                                                           object:[CharonPhotosStore library]
                                                                                            queue:nil
                                                                                       usingBlock:^(NSNotification *note) {
                (void)note;
                [weakSelf charon_availabilityRefreshed];
            }];
        }
        [_availabilityObservers addObject:observer];
    }
}

- (void)unregisterAvailabilityObserver:(id<PHPhotoLibraryAvailabilityObserver>)observer
{
    @synchronized(self) {
        [_availabilityObservers removeObject:observer];
    }
}

@end
