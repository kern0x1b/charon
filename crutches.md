# Crutches: the things a native fix has not been found for

One entry. Each is a place where the port answers Apple's API by something other than what Apple
does, with the measurement that shows it, and what a native fix would cost.

## 1. `MKAnnotationView.detailCalloutAccessoryView` is answered from the LEFT callout slot

**Measured.** The SDK 16.4 header marks the property `NS_AVAILABLE(10_11, 9_0)`, and a raw
selector search of the armv7 dyld shared cache of **6.1.3** finds **0** occurrences of
`detailCalloutAccessoryView`, **0** of `setDetailCalloutAccessoryView:`, and **0** of `calloutView`.
The release's own `MKAnnotationView` has `leftCalloutAccessoryView` and `rightCalloutAccessoryView`
and no third slot.

**So this port's answer is a substitution and the row says so.** Apple's `detailCalloutAccessoryView`
is the view drawn **under the title, inside the callout**. This port puts the caller's view in the
release's **left** callout slot, which is drawn **beside** the callout, not under its title. A caller
that sets it and expects Apple's placement gets it somewhere else, and the row's `effect` says which
where.

**Why not the native fix, and what it would cost.** The native answer is to not use the release's
callout at all: a `MKAnnotationView` subclass that draws the pin and a callout of this port's own,
with the caller's detail view laid out under the title, in the release's own iOS 6 appearance. That
is a whole callout — the plate, the shadow, the title, the detail area, the accessory slots and the
dismissal — replacing a piece of UIKit's own drawing, and it is the larger piece of the annotation
family rather than a member of it. It is worth doing and it is not done; the row is marked
`inert`-adjacent in its own words (a substitution, in the LEFT slot) so a caller is not misled while
it waits.

**What would unblock it:** a decision to own the callout. Nothing on the machine prevents it.
