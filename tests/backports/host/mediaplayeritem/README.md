# MPMediaItem: what this Mac's own MediaPlayer answers

The 22 properties the registry declares absent, asked of the host's own framework, on the one receiver a
machine with no media library has: none. A value needs a library; the two things a backport must
reproduce are the accessor being declared and what the value's absence answers, and both are answerable
here.

Run it directly - one `clang` and one process, not a build:

    xcrun clang -fobjc-arc -framework Foundation -framework MediaPlayer -o /tmp/mpitem-probe probe.m
    /tmp/mpitem-probe

Measured on this host (16.4-era MediaPlayer, 2026-09-28):

- **17 of the 22 declare a getter**, and every one answers `nil` on a nil receiver, the same answer
  `valueForProperty:` gives. That is the mapping the properties are: a convenience over the item's own
  property dictionary under the identically named key.
- **none of the 22 declares a setter**. They are read-only, so the backport needs getters only.
- that "5 declare no accessor" was **my probe's fault, not Apple's**. The iOS header declares five of
  them with a `getter=` attribute - `isExplicitItem`, `isCompilation`, `isCloudItem`,
  `hasProtectedAsset`, `isPreorder` - so the property name is not a selector on any platform. The probe now
  reads the header and asks for the getter the header writes, which is the only thing that could ever have
  answered. See the run below for where that stands.

The five are absent by Apple's own account, not by hardware: nothing here needs a sensor or a radio.

## What this probe got wrong first, twice

Both are in the file and both are worth keeping as the reason for its shape:

- the first version called `objc_msgSend` on a nil receiver for **every** property, and **segfaulted** on
  `albumTrackCount` - a scalar return read through a pointer return is not safe. Only the object-returning
  properties are called now; for the rest the answer is the type's zero, and `object_returning` names the
  five from the header rather than guessing.
- and it printed the property name with `%s` from an `NSString *`, which printed the object pointer. It
  prints `name.UTF8String` now, and every line above was read after that was fixed.
