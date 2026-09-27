// The debug description of a Writing Tools text animation, iOS 18.2
// (facts/UIKit/UIWritingToolsCoordinatorTextAnimation.md).
//
// One object carries one release: the symbol here is first exported by iOS 18.2, so every band
// from 18.2 on re-exports the release's own and the bands below keep this one.
//
// Every string below was measured by calling the Mac Catalyst UIKit's own function on macOS 27
// (the probe and its output are in .agent-work/runs/uikit-c/), not taken from a header and not
// guessed from the case names.

#import <UIKit/UIKit.h>

NSString *UIWritingToolsCoordinatorTextAnimationDebugDescription(UIWritingToolsCoordinatorTextAnimation animationType)
{
    // The three cases SDK 26.2's header declares (UIWritingToolsCoordinator.h:431-447), which carry
    // no explicit values and are 0, 1 and 2 in the order it declares them, and the answer the
    // framework gives for a value that is none of them - which is a name, not nil.
    switch (animationType) {
    case UIWritingToolsCoordinatorTextAnimationAnticipate:
        return @"Awaiting-new-text animation";
    case UIWritingToolsCoordinatorTextAnimationRemove:
        return @"Text removal animation";
    case UIWritingToolsCoordinatorTextAnimationInsert:
        return @"Text insertion animation";
    }
    return @"Unknown text animation";
}
