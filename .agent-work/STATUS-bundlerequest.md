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

---

## The finding that changes the plan: the host's class is a stub

The probe now compiles and steps 0 and 1 have run. Step 0 answers the question the header could not:

```
class NSBundleResourceRequest
  super NSObject
```

so the class is there, with `NSObject` as its superclass. **And then it raises.**

```
$ ./.agent-work/runs/facts 1
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'init is unavailable'
	2   Foundation   -[NSBundleResourceRequest initWithTag:] + 0
	3   facts        main + 1544
```

**The host's `-initWithTags:` forwards to an internal `-initWithTag:`, and that raises
`NSInvalidArgumentException` with the reason `init is unavailable`** — the same reason string
`-[NSPresentationIntent init]`'s unavailability would produce. The class is `API_UNAVAILABLE(macos)`,
and on macOS it is a declaration's worth of class with a raising initialiser: there is no instance of it
on the host to measure anything from.

That is the same position the previous family was in with `-rangeInString:`, where the answer was to
measure through the host's own Markdown parser. **There is no such second route here.** Nothing on the
host produces an `NSBundleResourceRequest`, so:

- the four properties, `-copy`, `-isEqual:` and the archive have **no host oracle**;
- the three system methods call a resource system that does not exist on the host at all, and their
  documented behaviour ("the completion block will be invoked on a non-main serial queue", "a cancel
  calls it back with an `NSUserCancelledError` in the `NSCocoaErrorDomain`") is the *only* statement
  available;
- the only measured facts are structural: the class name, `NSObject` as its superclass, which
  selectors it implements (step 0's `class_copyMethodList` half is written and has not run, because
  `class_getMetaClass` will not compile in this file — see below), and the raising initialiser.

**So the family needs a decision before code is written**, and it is the coordinator's:

1. **Carry it as a declared value class with the header as its contract.** The four properties store
   what a caller sets, `-copy` and `-isEqual:` are by the four, the archive carries the host's own keys
   — but *which* keys is unmeasured, because no host archive exists, so the keys would come from the
   26.2 lift's `NSKeyedArchiver` behaviour, which is a source of truth of a different kind. The proof
   would be a call test on the emulator, not a host differential. That is honest and it is less than the
   two families just delivered.
2. **Leave the eleven rows `absent` with the reason measured here** — "the class is declared for iOS 9,
   `API_UNAVAILABLE(macos)`, and the host's own initialiser raises, so there is nothing to hold a port
   to" — and take the next family. The wall is real: the release has no on-demand resource system either,
   so even a stored value class would hand an application a request object that can never complete.
3. **Carry it with a written difference** (the registry's `implemented` with an `effect` that says the
   three system methods complete immediately and the archive keys are the port's), which is the
   "carried with a difference" shape the package README already has for other classes.

I am not choosing this one. Option 2 is the reading the measurements support most plainly, and option 1
is the reading the row count supports; the difference is 11 rows and whether a call test alone is a
proof this package accepts for a Foundation value class.

## The probe's state

`.agent-work/measure/bundle-resource-request-facts.m` compiles; `.agent-work/measure/brr-step0.m` does
not, and its only error is `class_getMetaClass` being undeclared in a file that imports
`<objc/runtime.h>` — a toolchain oddity, not a logic error. Steps 0 and 1 of the first probe have run and
their output is above; steps 2 to 5 have not run at all.

---

## The ruling, and what it adds to the facts

**Carry it natively on the app's own bundle.** Tags are read from the bundle's `OnDemandResources.plist`
— the `NSBundleResourceRequestTags` map, tag to asset packs, each pack with its path inside the bundle. A
request whose tags all resolve completes at once with no error and `conditionallyBeginAccessing…` answers
YES; an unknown tag completes with `NSBundleOnDemandResourceInvalidTagError` in `NSCocoaErrorDomain`; and
`loadingPriority`, `progress` (completed at once) and the preservation priority are held as values. No
download ever happens, because every resolvable pack is local. That is the documented behaviour when the
packs are in the bundle, not an invention.

**The two facts this family has, and where each came from:**

- the three error codes, **measured out of the header** (`FoundationErrors.h`, iOS 9.0, the
  `NSCocoaErrorDomain` group, identical in the 16.4 and 26.2 SDKs):
  `NSBundleOnDemandResourceOutOfSpaceError` = **4992**,
  `NSBundleOnDemandResourceExceededMaximumSizeError` = **4993**,
  `NSBundleOnDemandResourceInvalidTagError` = **4994** — the last of which is the ruling's, and the
  header's own comment names the manifest it is about: "the system could not find in the application tag
  manifest";
- the plist key names, **not from any header**: `NSBundleResourceRequestTags`, `OnDemandResources` and the
  asset-pack path key are absent from every Foundation header in the 16.4 and 26.2 SDKs on this machine.
  They are the documented asset-pack format the ruling supplies, and the facts file has to say that is
  where they come from rather than implying a measurement. **This is a correction to the plan I wrote
  above, which assumed the header would carry them.**

**Two more members in the same header, not in the eleven rows the ledger prices** (iOS 9.0, both
`API_UNAVAILABLE(macos)`, in `@interface NSBundle (NSBundleResourceRequestAdditions)`):

```objc
- (void)setPreservationPriority:(double)priority forTags:(NSSet<NSString *> *)tags;   // :235
- (double)preservationPriorityForTag:(NSString *)tag;                                   // :236
```

with the header's own sentence for the first: "This method will throw an exception if the receiver
bundle has no on demand resource tag information." The ruling names the preservation priority as a value
held, so these two belong with the class; whether they are a twelfth and a thirteenth row or part of the
class's eleven is the coordinator's call, and I would register them as their own two rows rather than fold
them in.

**And there is no registry entry for any of it** — `NSBundleResourceRequest`, the notification and the
urgent priority are named in no file under `registry/Foundation/`, which is why the ledger prices the
class `missing` with `needs: code`. So the family is not "flip eleven `absent` entries"; it is thirteen
new entries plus a class, a category on `NSBundle`, and two symbols.

## Not started

No code for this family is written. The state is: the family chosen and approved, the eleven rows
counted, the eleven members read out of the 16.4 header, the stub on the host measured (the class is
there, `NSObject` is its superclass, and its initialisers raise `NSInvalidArgumentException` with the
reason `init is unavailable`), the error codes measured, the plist keys established as *not* a header
fact, the two `NSBundle` additions found, and the ruling's shape recorded above.

The proof the ruling names — the call test plus the emulator run — is not available to this band: the
emulator run's last step is handed to the emulate band in
`charon/.agent-work/worktrees/api-presentation/.agent-work/handoffs/2026-09-28-emulate-daemon-payload.md`
and queued in `coordination/api-queue.md` for `7e035ac0`, because the daemon has no `LC_LOAD_DYLIB` for
the backports library and nothing this band adds to the project will put one there.

---

## The second measurement, and it changes two of the plan's assumptions

`.agent-work/measure/brr-plist.m` asks the host what the class *is*, and the bundle side. Four facts,
each one a change to what I wrote above.

**1. The host's class is not only a stub — it is a stub with Apple's own structure in it.** The method
list, measured:

```
instance:  -tags  -bundle  -progress  -init  -dealloc  -loadingPriority  -setLoadingPriority:
           -beginAccessingResourcesWithCompletionHandler:
           -conditionallyBeginAccessingResourcesWithCompletionHandler:  -endAccessingResources
           -initWithTag:  -initWithTags:  -initWithTags:bundle:
class:     +_connection  +_setConnection:  +_addExtensionEndpoint:  +_assetPackBundleForBundle:withAssetPackID:
           +_extensionEndpoint  +_extensionEndpointForMainBundleOfHostApplication:
           +_flushCacheForBundle:forBundle:  +_manifestWithBundle:error:
```

**`+_manifestWithBundle:error:` is the manifest reader**, and `+_assetPackBundleForBundle:withAssetPackID:`
is the pack lookup — so the shape of the implementation is visible even where the instance cannot be
built, and it is the shape the port should have: a manifest per bundle, read once, and a pack resolved
by its id inside the bundle. `-initWithTag:` (singular) is the internal initialiser the public one
forwards to, which is why the public one's exception names it.

**2. The two `NSBundle` additions answer on the host**, both of them, despite
`API_UNAVAILABLE(macos)`:

```
setPreservationPriority:forTags: answers
preservationPriorityForTag:  answers
```

**So they are measurable after all** — including the refusal the header promises ("This method will
throw an exception if the receiver bundle has no on demand resource tag information"), which is a host
measurement and not a header sentence. That makes them two rows that the host *can* hold the port to,
and the plan above is wrong to have set them aside.

**3. A bundle's `OnDemandResources.plist` is reachable with the release's own `NSBundle`** — measured on
a bundle written on the spot:

```
NSBundle reads it back: /tmp/…/brr/OnDemandResources.plist
urlForResource:withExtension: -> file:///tmp/…/brr/OnDemandResources.plist
```

So the port needs no new machinery to *find* the manifest: `[bundle pathForResource:@"OnDemandResources"
ofType:@"plist"]` is an iOS 2 call. What the port must add is the *parsing* — `NSBundleResourceRequestTags`
is a tag → array-of-packs map, each pack a dictionary with `NSBundleResourceRequestPath` — and neither
name is in any header on this machine, so both are the documented asset-pack format, and the facts file
has to say that twice now: for the top-level key and for the per-pack one.

**4. Neither of the family's two symbols is on the host at all:**

```
NSBundleResourceRequestLoadingPriorityUrgent:    no symbol on the host
NSBundleResourceRequestLowDiskSpaceNotification: no symbol on the host
```

Both are `API_UNAVAILABLE(macos)`, and a constant behind that attribute is not emitted in the macOS
framework — so **there is no value of either to measure on this host, and the two rows cannot be held to
it.** What the header gives is the name, and the header's own sentences give the values' meaning: the
urgent priority is "the maximum amount of resources available to finishing this request as soon as
possible", the property's range is "between 0 and 1, with 1 being the highest", and a notification's
name is its own string. So the two values are **documented, not measured**, and the facts file must
label them that way rather than imply a measurement the host cannot give. This is the same shape as the
`NSInlinePresentationIntentAttributeName` key, whose value *was* measurable because its type is not
platform-restricted.

## What this leaves for the code

Measured and holdable: the 13 members' structure and the two initialisers' refusal, `+_manifestWithBundle:error:`
as the manifest's shape, the two `NSBundle` additions and their refusal, the manifest's location, and
the error codes 4992/4993/4994.
Documented and not holdable: the plist's two key names, the urgent priority, and the notification's
name. Rule-as-ruled: every resolvable tag completes at once, an unknown one completes with 4994, no
download ever happens, and `progress` is completed at once.

---

## The third measurement: the private initialiser answers, and the two NSBundle additions are inert

`.agent-work/measure/brr-init.m`, and it decides three things the plan above left open.

**1. `-init` raises, and the reason is the header's own phrase.** Measured, not inferred:

```
-init           -> NSInvalidArgumentException: init is unavailable
-initWithTag:   -> an object
```

The header marks `-init` `API_UNAVAILABLE(macos, ios, watchos, tvos)`, and the host's copy of that
unavailability is the exception above. So the port's `-init` raises `NSInvalidArgumentException` with
the reason `init is unavailable` — which is a *row* of the corpus that the host answers by refusing, and
the port answers the same way.

**2. `-initWithTag:` (singular, private) *answers*, so there is a host oracle after all.** The public
`-initWithTags:` forwards to it and the *forwarding* is what raises, but the private initialiser itself
builds an object. **That is what the differential compares:** the port's public `-initWithTags:` and the
host's private `-initWithTag:`, over all four properties — `tags`, `bundle`, `loadingPriority` and
`progress`. The earlier conclusion in this file, that no host oracle exists for the class, is **too
strong** and is corrected here: there is none for the *public* initialiser and one for the state.

**3. The two `NSBundle` additions are inert on the host, and the port must follow the header instead.**
Measured, on a bundle with no On-Demand Resources at all and on one that has a manifest:

```
setPreservationPriority:forTags: on a bundle with no tags      -> answered
an out-of-range priority (2.0)                                  -> answered
on a bundle with level1, for a tag the bundle does not have     -> answered
preservationPriorityForTag: on a bundle with no tags            -> 0
on a bundle with level1, reading level1 back                    -> 0
```

Every one of those answers, and every one reads back 0, where the header says "This method will throw
an exception if the receiver bundle has no on demand resource tag information." The host is not
implementing them — they are `API_UNAVAILABLE(macos)`, so what macOS ships is a stub. **So these two rows
cannot be held to the host at all**: the port implements what the header says, and the facts file states
that the host answers where the header promises a refusal. This is the "carried with a difference from the
host" shape the package README already has for other classes, and it is the honest one here.

## The counts, stated so they are not confused

Thirteen rows: the class, six methods of it, four properties of it, the two `NSBundle` methods, and the
two constants. Of those, **eleven are holdable and two are not**: `NSBundleResourceRequestLoadingPriorityUrgent`
and `NSBundleResourceRequestLowDiskSpaceNotification` are constants behind `API_UNAVAILABLE(macos)`, which
the macOS framework does not emit at all, so neither value can be measured on this host and both come
from the header's own words. The two plist key names — `NSBundleResourceRequestTags` and
`NSBundleResourceRequestPath` — are not API rows and are not measured; they are the documented
asset-pack format, read out of the plist the ruling describes.
