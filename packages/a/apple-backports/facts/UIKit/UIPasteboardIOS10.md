# What iOS 10 added to the pasteboard: the four questions, and the one method that is not carried

Introduced in iOS 10.0: `-[UIPasteboard hasStrings]`, `hasURLs`, `hasImages`, `hasColors`, `-setItems:options:`, the
option keys `UIPasteboardOptionLocalOnly` and `UIPasteboardOptionExpirationDate`, and the type `UIPasteboardTypeAutomatic`.

Source: UIKit of the armv7s cache of iOS 10.3.4 and the Pasteboard framework it calls, read for what the methods do;
UIKit of iOS 6.1.3 armv7, read for what the release already has; and the host's own UIKit under Mac Catalyst, run over
`device/pasteboard10-cases.m` by `host/pasteboard10/run.sh`.

## The four questions

- What the release asks: the four `has...` answers are in `UIPasteboard`'s concrete subclass, `_UIConcretePasteboard`;
  the base class answers NO. Each asks a helper for the collection of the pasteboard's items, which for the general
  pasteboard is fetched from the pasteboard service and waited for on a semaphore, and asks that collection
  `-canInstantiateObjectOfClass:` with `NSString`, `NSURL`, `UIImage` or `UIColor`. The collection is the Pasteboard
  framework's `PBItemCollection`, which asks each `PBItem` in turn. So the question is not "which type identifiers are
  on the pasteboard" but "can the pasteboard hand me one of these four".
- What iOS 6 has for it: that same question, without the framework and the service. `UIKit` of 6.1.3 exports
  `UIPasteboardTypeListString`, `UIPasteboardTypeListURL`, `UIPasteboardTypeListImage` and `UIPasteboardTypeListColor`,
  the four lists of type identifiers the release's own `-strings`, `-URLs`, `-images` and `-colors` read items through,
  and `-containsPasteboardTypes:` answers whether any item carries one of a list's types. The port answers each `has...`
  with `-containsPasteboardTypes:` over the list of its own kind, so it is the release asking itself the question its
  own accessors would ask.
- What was measured. The host's answers for the thirteen cases of `device/pasteboard10-cases.m` are in
  `device/pasteboard10-expectations.h`; each case records the four predicates beside whether the four object accessors
  return anything. In all thirteen the two halves agree on the host: nothing it can hand over is missed by the
  predicate, and nothing the predicate claims is missing from the accessors. Worth naming among them: a
  `NSURL` on the pasteboard answers YES to both `hasURLs` and `hasStrings`, because a URL is written as text as well; a
  string that reads as a URL answers YES to `hasURLs` too; an image set over a string replaces it, since both take item
  zero, and only `hasImages` stays; bytes under a type of the application's own answer NO to all four.
- Where it can differ from iOS 10 and cannot be closed here: `PBItemCollection` decides from type identifiers the
  service holds, and its decision follows the conformance of those identifiers. Where an item is written under a type of
  the application's own that *conforms* to `public.image` or `public.text`, iOS 10 can still instantiate the object and
  the release's list, which names identifiers, does not reach it. Such an item is answered NO here and YES there. It is
  the release's own limit, the same one its `-images` and `-strings` have, and not a guess of the port's: what the port
  answers is exactly what the pasteboard of this release can hand over.

## The method that is not carried

- `-setItems:options:` rebuilds the items as representations with loader blocks, checks their values, and passes them with
  the options to `-_setItemsAndSave:options:`, which sets the collection's local-only flag and its expiration date from
  `UIPasteboardOptionLocalOnly` and `UIPasteboardOptionExpirationDate`, checking that they are an `NSNumber` and an
  `NSDate`, and saves the collection through the service. An expiration has to clear the pasteboard when the date comes,
  after the application that set it has gone, which only the service can do; password managers rely on it. A port in the
  application's process cannot keep that promise, and pretending to is worse than not offering the method.
- `UIPasteboardTypeAutomatic` is the type identifier `com.apple.uikit.type-automatic`, which `-setItems:options:` reads to
  choose a representation by the class of the value; it means nothing without that method.

## The option keys are exported

The two option keys exist as `NSString`s with the system's own values (`expirationDate` and `localOnly`, as `host/tail2/run.sh` reads them), so an application that refers to the symbols directly, without a check of the release, loads and does not read a null pointer. Nothing reads them: `-setItems:options:` stays undeclared for the reason above, so an application that asks whether the pasteboard responds to it does not hand over a secret that the port could not clear.
