// What the SDK this port builds with does not carry, declared from the SDK the API comes from.
//
// The goal is SDK 26.2's FileProvider. The SDK the port lifts is 16.4, and the known-folders API is
// not in it at all:
//
//   $ grep -rn "claimKnownFolders" <16.4 SDK>/…/FileProvider.framework/Headers/*.h
//   (no output)
//
// while SDK 26.2 declares it in NSFileProviderKnownFolders.h, with
// `FILEPROVIDER_API_AVAILABILITY_DESKTOP` - which is what makes the corpus list it at 11.0 and the
// 16.4 headers silent about it. So it is declared here, in the 26.2 spelling, and the .m
// implements it. The pattern is VideoToolbox's CharonVideoToolbox.h: a header of the port's own
// that carries what the lifted SDK does not.
//
// FACTS ONLY, from the 26.2 headers and the corpus - not Apple's implementation and not a
// behaviour: the spellings, the types, and the availability macro, copied.

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>

/**
 Specifying a list of known folders.
 FILEPROVIDER_API_AVAILABILITY_DESKTOP
 */
typedef NS_OPTIONS(NSUInteger, NSFileProviderKnownFolders) {
    NSFileProviderDesktop = 1 << 0,
    NSFileProviderDocuments = 1 << 1
};

/**
 The locations of the known folders an extension claims, keyed by the folders themselves.
 26.2's NSFileProviderKnownFolders.h: `NSFileProviderKnownFolderLocations`, an object the
 claimKnownFolders: and releaseKnownFolders: methods take. A dictionary of
 NSFileProviderKnownFolders to NSFileProviderKnownFolderLocation, which is why the claim is
 "claim ~/Desktop and ~/Documents together".
 */
@interface NSFileProviderKnownFolderLocation : NSObject
@end

@interface NSFileProviderKnownFolderLocations : NSObject
@end

@interface NSFileProviderManager (CharonKnownFolders)
/**
 Claim the given known folders, with a reason shown to the user.
 26.2's NSFileProviderKnownFolders.h:106-110, verbatim in its spelling and its availability.
 */
- (void)claimKnownFolders:(NSFileProviderKnownFolderLocations *)knownFolders
          localizedReason:(NSString *)localizedReason
        completionHandler:(void (^)(NSError * _Nullable))completionHandler
                NS_SWIFT_NAME(claimKnownFolders(_:localizedReason:completionHandler:));
/* 26.2 gates this with FILEPROVIDER_API_AVAILABILITY_DESKTOP, which the lifted SDK does not
   define - naming it here would make this a bare identifier and the header would not parse. The
   corpus lists the member at 11.0; the availability is therefore recorded, not applied. */

/**
 Release the given known folders back to whoever held them.
 */
- (void)releaseKnownFolders:(NSFileProviderKnownFolderLocations *)knownFolders
           localizedReason:(NSString *)localizedReason
             completionHandler:(void (^)(NSError * _Nullable))completionHandler
                     NS_SWIFT_NAME(releaseKnownFolders(_:localizedReason:completionHandler:));
/* FILEPROVIDER_API_AVAILABILITY_DESKTOP in 26.2; recorded for the reason above. */
@end

/**
 The reason a domain is disconnected, and the options it is disconnected with. The 16.4 SDK has
 neither: `disconnectWithReason:options:completionHandler:` is declared by that SDK's
 NSFileProviderManager.h and names two types the SDK does not define, which is the same gap as the
 known folders and is filled here for the same reason. Spelled as 26.2 spells them - the port's
 header carries the spellings, the macro and the behaviour.
 */
typedef NS_ENUM(NSInteger, NSFileProviderDisconnectReason) {
    NSFileProviderDisconnectReasonUnknown = 0,
    NSFileProviderDisconnectReasonSignedOut = 1,
    NSFileProviderDisconnectReasonQuotaExceeded = 2,
    NSFileProviderDisconnectReasonServerUnreachable = 3
};

typedef NS_OPTIONS(NSUInteger, NSFileProviderDisconnectOptions) {
    NSFileProviderDisconnectOptionNone = 0,
    NSFileProviderDisconnectOptionDropPending = 1 << 0
};
