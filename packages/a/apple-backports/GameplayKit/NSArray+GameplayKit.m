// NSArray+GameplayKit.m -- the two methods NSArray carries for GameplayKit, which the framework
// answers by shuffling an array with a random source and with the system's own. The shuffle itself
// is in CharonGKShuffle.m, so that -[GKRandomSource arrayByShufflingObjectsInArray:], which is in
// the same band and may be in a different one, reaches the same code.
//
// Both are declared by the SDK in GKRandomSource.h's own NSArray (GameplayKit) category, so they are
// the two rows registry/GameplayKit/shuffle.json carries: a category on a class the release already
// carries is API the port carries, and entry_of() answers a member with the class's own row only
// when the PORT defines that class (charon/AGENTS.md, "A seam the port owns still needs a registry
// row"; NSArray is the release's, so these two need rows of their own).

#import "CharonGK.h"

@implementation NSArray (GameplayKit)

- (NSArray *)shuffledArrayWithRandomSource:(GKRandomSource *)randomSource
{
    return [self charon_shuffledArrayWithRandomSource:randomSource];
}

- (NSArray *)shuffledArray
{
    return [self charon_shuffledArrayWithRandomSource:[GKRandomSource sharedRandom]];
}

@end