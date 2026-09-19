# What iOS 10 added to the pasteboard, and why it is not carried

Introduced in iOS 10.0: `-[UIPasteboard hasStrings]`, `hasURLs`, `hasImages`, `hasColors`, `-setItems:options:`, the
option keys `UIPasteboardOptionLocalOnly` and `UIPasteboardOptionExpirationDate`, and the type `UIPasteboardTypeAutomatic`.

Source: UIKit of the armv7s cache of iOS 10.3.4 and the Pasteboard framework it calls, read for what the methods do.

- The four `has...` answers are in `UIPasteboard`'s concrete subclass, `_UIConcretePasteboard`; the base class answers NO.
  Each asks a helper for the collection of the pasteboard's items, which for the general pasteboard is fetched from the
  pasteboard service and waited for on a semaphore, and asks that collection `-canInstantiateObjectOfClass:` with
  `NSString`, `NSURL`, `UIImage` or `UIColor`. The collection is the Pasteboard framework's `PBItemCollection`, which
  asks each `PBItem` in turn; what makes an item readable as a class is decided there, from type identifiers the service
  holds, and is not in UIKit. iOS 6 has neither the framework nor the service, and a check of the types it does have
  would decide differently from the release for the same contents.
- `-setItems:options:` rebuilds the items as representations with loader blocks, checks their values, and passes them with
  the options to `-_setItemsAndSave:options:`, which sets the collection's local-only flag and its expiration date from
  `UIPasteboardOptionLocalOnly` and `UIPasteboardOptionExpirationDate`, checking that they are an `NSNumber` and an
  `NSDate`, and saves the collection through the service. An expiration has to clear the pasteboard when the date comes,
  after the application that set it has gone, which only the service can do; password managers rely on it. A port in the
  application's process cannot keep that promise, and pretending to is worse than not offering the method.
- `UIPasteboardTypeAutomatic` is the type identifier `com.apple.uikit.type-automatic`, which `-setItems:options:` reads to
  choose a representation by the class of the value; it means nothing without that method.

So none is carried: `respondsToSelector:` answers NO for each.
