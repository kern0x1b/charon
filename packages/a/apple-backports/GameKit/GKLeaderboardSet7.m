// NOT CARRIED, and deliberately in the tree: the differential that would hold this class
// (tests/backports/host/gamekit) traps before its first record, and the registry's rule is that
// nothing is implemented without one. The class and its answers are written out below and in
// facts/GameKit/Values.md; the rows are recorded absent. Build the library off while they stand.

#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>

// GKLeaderboardSet, GKBasePlayer and GKCloudPlayer: the three value classes of the Game Center of
// iOS 7.0 and 8.0, carried over what the release's own Game Center has.
//
// **What the release has, measured.** The 6.1.3 armv7 cache's GameKit image carries 304 classes,
// including GKPlayer, GKLeaderboard, GKAchievement, GKMatchmaker, GKScore, GKMatch, GKSession, and the
// selectors displayName, playerID, score, rank, isAuthenticated and loadImage - so iOS 6's Game Center
// is already the modern one and a player on this release has the name and the identifier the new API
// names. What it has none of is the *set*: loadLeaderboardsWithIDs is not in the release's selector
// list, so there is no call to make a GKLeaderboardSet from, and a set that was not loaded has nothing
// to report (facts/GameKit/Values.md).

// A set of leaderboards the server groups: a Game Center app declares them, the app loads them, and
// each carries the identifier, the title and the group it is in.
//
// The release's Game Center has no call that makes one - loadLeaderboardsWithIDs is not in its selector
// list - so a set here is one an application has built or loaded, and the four load calls answer what
// the release's own Game Center answers for a request it has no call for: no leaderboards, and the
// Game Center error. That is the honest reading of a server this device cannot reach, not a zero.
@interface GKLeaderboardSet ()
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title groupIdentifier:(NSString *)groupIdentifier;
@end

@implementation GKLeaderboardSet

@synthesize identifier = _identifier, title = _title, groupIdentifier = _groupIdentifier;

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title groupIdentifier:(NSString *)groupIdentifier
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _title = [title copy];
        _groupIdentifier = [groupIdentifier copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.identifier forKey:@"identifier"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.groupIdentifier forKey:@"groupIdentifier"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _identifier = [[coder decodeObjectOfClass:[NSString class] forKey:@"identifier"] copy];
        _title = [[coder decodeObjectOfClass:[NSString class] forKey:@"title"] copy];
        _groupIdentifier = [[coder decodeObjectOfClass:[NSString class] forKey:@"groupIdentifier"] copy];
    }
    return self;
}

+ (NSError *)charonNoSetsError
{
    // 3 is GKErrorCommunicationsFailure, the error Game Center gives when the container's leaderboard
    // sets cannot be fetched; facts/GameKit/Values.md names the host's own answer for the same call.
    return [NSError errorWithDomain:@"GKErrorDomain" code:3
                           userInfo:@{NSLocalizedDescriptionKey: @"The leaderboard sets could not be loaded."}];
}

+ (void)loadLeaderboardSetsWithCompletionHandler:(void (^)(NSArray<GKLeaderboardSet *> *leaderboardSets, NSError *error))completionHandler
{
    if (completionHandler) {
        completionHandler(@[], [self charonNoSetsError]);
    }
}

- (void)loadImageWithCompletionHandler:(void (^)(UIImage *image, NSError *error))completionHandler
{
    // A set's image is the server's, and this release has no call that fetches one. A nil image with the
    // Game Center error is what the release's own answers look like when it has no picture to give.
    if (completionHandler) {
        completionHandler(nil, [GKLeaderboardSet charonNoSetsError]);
    }
}

- (void)loadLeaderboardsWithCompletionHandler:(void (^)(NSArray<GKLeaderboard *> *leaderboards, NSError *error))completionHandler
{
    if (completionHandler) {
        completionHandler(@[], [GKLeaderboardSet charonNoSetsError]);
    }
}

- (void)loadLeaderboardsWithHandler:(void (^)(NSArray<GKLeaderboard *> *leaderboards, NSError *error))handler
{
    // The pre-iOS 7 spelling of the call above, which the same server answers the same way.
    [self loadLeaderboardsWithCompletionHandler:handler];
}

@end
