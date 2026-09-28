# NSBundleResourceRequest — the family, chosen and started

Worktree `charon/.agent-work/worktrees/api-bundlerequest`, branch `band-api-bundlerequest`, base
`origin/main` = `0e886551`. One commit, this file and the probe. **No code is written and the probe does
not compile yet** — what is left of it is at the bottom, exactly.

## Why this family

`coordination/corpus/ledger` is a snapshot of a tree that does not contain `band-api-presentation`, so
it still lists 25 `NSPresentationIntent` and 14 markdown rows as missing that the 6.1.3 gate's dylib
carries. Ignoring those, the 365 missing Foundation Objective-C rows sit on 155 owners, and **only four
of those owners are classes the release does not have at all** — the other 151 are classes the release
has, with later members missing, which is a different shape of work from a family:

| rows | class | owner |
| --- | --- | --- |
| **11** | **`NSBundleResourceRequest`** | **nobody** — checked every `band-*` branch's tree, none names it, and the 6.1.3 gate's dylib exports 0 matches |
| 10 | `NSURLSessionStreamTask` | d20703c1, `registry/Foundation/nz-stream.json` |
| 9 | `NSDateIntervalFormatter` | nobody, but its wording is the locale's own CLDR data, which is a measurement this tree does elsewhere (`facts/Foundation/NSUnitFormat.md`) |
| 8 | `NSPersonNameComponentsFormatter` | d20703c1, `registry/Foundation/nz-personname.json` |

`NSBundleResourceRequest` is the largest, and it is the same shape as the two families just delivered:
one class the release has none of, with its initialisers, its properties, its two system-facing methods
and two keys.

## The surface, from the 16.4 SDK header the port builds against

`NSBundle.h`, `API_AVAILABLE(ios(9.0)…)`, `API_UNAVAILABLE(macos)` — the class is **not on the host's
macOS surface as a documented one**, which is the first thing the measurement has to work around.

| row | declaration | note from the header |
| --- | --- | --- |
| class | `@interface NSBundleResourceRequest : NSObject <NSProgressReporting>` | it is `NSProgressReporting`, so `-progress` comes from that protocol |
| constant | `NSBundleResourceRequestLoadingPriorityUrgent` | `FOUNDATION_EXPORT double const` |
| constant | `NSBundleResourceRequestLowDiskSpaceNotification` | `FOUNDATION_EXPORT NSNotificationName const` |
| method | `- (instancetype)init` | **`API_UNAVAILABLE(macos, ios, watchos, tvos)`** — unavailable on every platform, and the corpus lists the row anyway |
| method | `- (instancetype)initWithTags:(NSSet<NSString *> *)tags` | "the tag argument is required and it must exist in the manifest of the specified bundle" |
| method | `- (instancetype)initWithTags:bundle:` | `NS_DESIGNATED_INITIALIZER`; "if no bundle is specified then the main bundle is used" |
| method | `-beginAccessingResourcesWithCompletionHandler:` | the handler is called on a non-main serial queue; a cancel calls it with `NSUserCancelledError` |
| method | `-conditionallyBeginAccessingResourcesWithCompletionHandler:` | the handler gets a `BOOL` |
| method | `-endAccessingResources` | "may only be invoked if you have received a callback from -begin…" |
| property | `loadingPriority` | `double`, "between 0 and 1, with 1 being the highest. The default priority is 0.5" |
| property | `tags` | `readonly, copy`, `NSSet<NSString *> *` |
| property | `bundle` | `readonly, strong`, `NSBundle *` |
| property | `progress` | `readonly, strong`, from `NSProgressReporting` |

Two things the header says that are worth writing down before the code:

- **The two constants are `API_UNAVAILABLE(macos)`**, so a program built for the host cannot name them:
  the compiler refuses `NSBundleResourceRequestLoadingPriorityUrgent` with "'…' is unavailable: not
  available on macOS". The only way to read the host's values is `dlsym(RTLD_DEFAULT, "_Name")` — which
  is what the probe does for the class's own sake (to find out whether the class is even there) and will
  have to do for both constants if their values are to be measured rather than assumed.
- **`-init` is unavailable on every platform**, so the corpus row is a declaration with no caller. The
  two families just delivered both answered their `NS_UNAVAILABLE` `-init`s on the host anyway
  (`NSPresentationIntent`, `NSMorphologyPronoun`), and this one is the same case.

## Not in the ledger, in the same header

`-setPreservationPriority:forTags:` and `-preservationPriorityForTag:` in
`@interface NSBundle (NSBundleResourceRequestAdditions)`, both `API_UNAVAILABLE(macos)`, and two
`NSProgress` interactions: "If you cancel an outstanding request (via the cancel method on the NSProgress
object…) the completion handler argument to this method will be called back with an NSUserCancelledError".
The measurement decides whether they are in the family; they are not in the corpus's 11 rows, so they are
not in the count.

## What the measurement has to decide, and what is left of it

The probe is `.agent-work/measure/bundle-resource-request-facts.m`, six steps:

- **0** the class's superclass and conformances, the two keys, and whether each of the eleven members
  answers;
- **1** the three initialisers, what the four properties read back, whether `tags` is the caller's own
  set, whether two requests with the same tags are equal, and what `nil` and an empty set do;
- **2** `loadingPriority` from −1 to 2 in quarters, the copy, and the equality and hash;
- **3** the three system methods, which touch the resource system and are the part that cannot be
  reasoned about;
- **4** the archive: the keys, the byte count, and whether a request comes back equal;
- **5** the two `NSBundle` additions, to decide whether they are in the family.

**The probe does not compile.** Four errors remain, all in the two places where a property is read
through a cast subscript, which is C indexing and not a message send:

```
bundle-resource-request-facts.m:124:73: error: use of undeclared identifier 'givenBundle'
bundle-resource-request-facts.m:194:78: error: cast of 'int64_t' to 'id' is disallowed with ARC
bundle-resource-request-facts.m:194:111: error: expected identifier
bundle-resource-request-facts.m:195:22: error: cast of 'int64_t' to 'id' is disallowed with ARC
```

The fix is to give each a local (`id bundle = (id)[withBoth bundle];` and
`id progress = (id)[one progress];`) instead of a cast subscript; that is what every other read in the
file already does, and the two `totalUnitCount` reads in step 3 need it too. Nothing else is wrong, and
steps 0 to 5 have not run: **there is not one measured number for this family yet**, and the next session
must not treat the header's "0.5" and "0 to 1" as measurements.
