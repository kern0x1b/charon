// CharonTraitObservers.m - the listeners a trait change is told to, and the two calls into and out of
// the list they are held in.
//
// The list is here, apart from UITraitCollection.m, because the two files that need it are carried
// from two different releases and no band can hold a pair whose releases differ: UITraitCollection.m
// implements a class a release exports from 8.0, so the band from 8.0 re-exports that release's own
// object instead of linking this one, while UITraitOverrides17.m is carried from the release that
// exports the twenty-two traits of iOS 17 and is in every band below it. A C function defined in one
// of them and called from the other is therefore an undefined symbol in every band from 8.0 on - the
// fourth band of a build with the uikit config stopped on exactly that, with
// "_charon_add_trait_change_observer, referenced from +[CharonOverrides load] in
// UITraitOverrides17.o". An object that exports no API symbol of its own is carried from the
// deployment on, which is what this one is: both names it defines are internal, so no release is
// measured to export them and no band point is derived from it.
//
// Nothing here changed behaviour: the same array, grown the same way, called in the same order with
// the same arguments, in the same place of the delivery - the call the listener list makes is now a
// call out to this file, and it happens between the change and the traitCollectionDidChange: walk,
// which is where it was.

#import <UIKit/UIKit.h>
#import "CharonTraitStyle.h"

// A function pointer is not an object, so the listeners are held in a plain array of them, one
// allocation, grown as they register; there are at most a handful and a registration happens once
// per class load.
static CharonTraitChangeObserver *charon_trait_change_observers;
static NSUInteger charon_trait_change_observer_count;

void charon_add_trait_change_observer(CharonTraitChangeObserver observer)
{
    if (!observer)
        return;
    CharonTraitChangeObserver *grown =
        realloc(charon_trait_change_observers, (charon_trait_change_observer_count + 1) * sizeof(*grown));
    if (!grown)
        return;
    charon_trait_change_observers = grown;
    charon_trait_change_observers[charon_trait_change_observer_count++] = observer;
}

// The listeners of a trait change, called once the change is made, with the environments that were
// told and the collection each had before, in the order they registered. UITraitCollection.m's own
// delivery is the only place a trait moves on this release, so it is where the registration of iOS
// 17 fires.
void charon_call_trait_change_observers(NSArray *environments, NSArray *previous)
{
    for (NSUInteger index = 0; index < charon_trait_change_observer_count; index++)
        charon_trait_change_observers[index](environments, previous);
}