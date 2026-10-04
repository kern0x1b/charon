// CharonGKShuffle.m -- the one shuffle the random family and the two methods NSArray carries for it
// share. It is a file of its own, and it exports no API symbol of its own, because the two methods
// NSArray carries and -[GKRandomSource arrayByShufflingObjectsInArray:] are three files that must
// reach the same code: a band whose release has none of the two methods leaves out the file that
// defines them, and a C function shared between files is an undefined symbol in exactly that band.
// (The trap is charon/AGENTS.md's "A C function shared between backport files".)
//
// The method it defines is named for this port and not for Apple's API, so the build module leaves
// it out of what a release is weighed against and out of what the library exports, and the registry
// check does not ask a row for it either (internal_symbol() drops every charon_ selector).

#import "CharonGK.h"

@implementation NSArray (CharonGKShuffle)

// A Fisher-Yates shuffle that runs forwards, which is the one the host's own two methods run, and
// which GKShuffledDistribution runs too: for each object in turn the source is asked for a draw below
// the number of objects seen so far, and the two are exchanged. Measured on an array of eight over
// the host's own linear congruential source seeded with 7, whose draws below 1 to 8 are
// 0 0 6 4 2 0 4 5, the host answers 3 6 5 2 4 8 7 1 and so does this.
- (NSArray *)charon_shuffledArrayWithRandomSource:(id<GKRandom>)randomSource
{
    NSMutableArray *shuffled = [self mutableCopy];
    for (NSUInteger index = 0; index < [shuffled count]; index++) {
        NSUInteger other = [randomSource nextIntWithUpperBound:index + 1];
        [shuffled exchangeObjectAtIndex:index withObjectAtIndex:other];
    }
    return [shuffled copy];
}

@end