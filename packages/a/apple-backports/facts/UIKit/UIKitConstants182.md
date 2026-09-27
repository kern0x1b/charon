# The UIKit constants of iOS 18.2

`UIKit/UIKitConstants182.m`: the error domain and its two keys of
`-[UIApplication defaultStatusForCategory:error:]`, and the attributed-string key that marks text
Writing Tools must leave alone.

## Where the values come from

No iOS release on this machine carries these. The held release ladder
(`$HOME/.charon/dyld`, `dyld.held_ladder`) ends at iOS 18.0, and the symbols are in none of its 41
caches. They are read instead out of **the Mac Catalyst UIKit of macOS 27**, in the system's own dyld
shared cache (`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`),
with this repository's own reader (`tools/corpus/cache-value.lua` over `modules/apple/dyld.lua`).
Every value below is what that framework holds, read through its `__cfstring`; none is taken from a
header, and none is a guess.

| constant | the image that exports it | the value |
| --- | --- | --- |
| `NSWritingToolsExclusionAttributeName` | `/System/Library/PrivateFrameworks/UIFoundation.framework/Versions/A/UIFoundation` | `WTWritingToolsPreserved` |
| `UIApplicationCategoryDefaultErrorDomain` | `/System/iOSSupport/System/Library/PrivateFrameworks/UIKitCore.framework/Versions/A/UIKitCore` | `UIApplicationCategoryDefaultErrorDomain` |
| `UIApplicationCategoryDefaultRetryAvailabilityDateErrorKey` | the same | `UIApplicationCategoryDefaultRetryAvailabilityDateErrorKey` |
| `UIApplicationCategoryDefaultStatusLastProvidedDateErrorKey` | the same | `UIApplicationCategoryDefaultStatusLastProvidedDateErrorKey` |

The first of those is the reason this file exists: the constant's *name* is nothing like its value,
and the value is not derivable from anything but the framework that holds it. A port that had
guessed - `NSWritingToolsExclusion`, the obvious spelling - would have marked text with a key no
Writing Tools ever asks about, and the exclusion would silently never apply.

The other three are their own names, so the read is also its own check: a reader that followed a
neighbouring object would name a different string, and this one names itself in all three cases.
