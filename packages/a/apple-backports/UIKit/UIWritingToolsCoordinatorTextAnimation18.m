// The debug description of a Writing Tools text animation, iOS 18.2
// (facts/UIKit/UIWritingToolsCoordinatorTextAnimation.md).
//
// One object carries one release: the symbol here is first exported by iOS 18.2, so every band
// from 18.2 on re-exports the release's own and the bands below keep this one.

#import <UIKit/UIKit.h>

NSString *UIWritingToolsCoordinatorTextAnimationDebugDescription(UIWritingToolsCoordinatorTextAnimation animationType)
{
    // The name of the case, which is what a debug description of an enumeration is on every Apple
    // platform that has one: -[NSObject debugDescription] and String(describing:) both name the
    // case they are given, and the case here is the Swift enum UIWritingToolsCoordinator.TextAnimation
    // the header's NS_SWIFT_NAME renames this type to. Its three cases are the ones the header
    // declares (UIWritingToolsCoordinator.h:431-447), spelled as the header spells them and carrying
    // no explicit values, so they are 0, 1 and 2 in the order it declares them. A value outside that
    // range is no case of the enumeration, and there is no description to give for it.
    //
    // The release's own spelling of each name was not read: no release that carries this function is
    // held on this machine, and there is no host framework that has it either. What is measured is
    // the case name, from the header. Said again in the facts file.
    switch (animationType) {
    case UIWritingToolsCoordinatorTextAnimationAnticipate:
        return @"Anticipate";
    case UIWritingToolsCoordinatorTextAnimationRemove:
        return @"Remove";
    case UIWritingToolsCoordinatorTextAnimationInsert:
        return @"Insert";
    }
    return nil;
}
