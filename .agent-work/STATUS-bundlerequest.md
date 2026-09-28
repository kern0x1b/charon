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

---

## The private initialiser is not an oracle, and the differential is red

Two things the differential found, both about the oracle rather than the port.

**1. `-initWithTag:` forwards a selector this host does not implement.** One probe said it answered
(`-initWithTag: -> an object`), and the differential says otherwise, in the process where the port's
`NSBundle (NSBundleResourceRequestAdditions)` category is attached to the real `NSBundle`:

```
2   CoreFoundation   -[NSObject(NSObject) doesNotRecognizeSelector:]
5   CoreFoundation   __invoking___ + 148
6   CoreFoundation   -[NSInvocation invoke] + 424
7   differential     host_initWithTag + 260
```

**So the private initialiser is not usable as a state oracle**, and the earlier conclusion in this file —
that there is one — is wrong again, in the direction the first measurement pointed: the family has **no
host oracle for the class's state**. The probe and the differential disagree, and the disagreement is
itself the finding: the same selector answers in a bare process and forwards in one where the port's
category is attached, which is a difference the test cannot control and must not depend on. The
differential now catches the exception and reports "no state to compare", and the class's rules are
checked against the header's words instead. **The 11 rows are therefore 9 holdable and 2 not, and the two
are the `NSBundle` additions**, whose host copies are inert and where the port deliberately differs.

**2. The differential aborts, and not on the oracle.** With the oracle guarded, the run dies on a
SIGTRAP with no exception — a trap inside the port or inside the harness, not a message — and I have not
bisected it. The next session's first command on this family is `sh tests/backports/host/bundlerequest/run.sh`
with a bisect, and the class is where I would look first: `+supportsSecureCoding`, the two
`CharonManifests`/`CharonPriorities` tables, and `-init`'s `raise` with a `return nil` after it.

The port's own state is *unverified*. It compiles clean under `-Wall -Werror=objc-missing-property-synthesis`
and exports exactly the class, its metaclass and the two constants, and none of that is a measurement of
its behaviour.

---

## Two root causes found, and the trap survives both

**1. The compiled category was the wrong mechanism, and the coordinator is right about why.** A
category on `NSBundle` attaches unconditionally, so it overrode the host's own
`setPreservationPriority:forTags:` and `preservationPriorityForTag:` on macOS, and that is what broke
the host's private `-initWithTag:` — the fleet rule is that the port installs nothing where the host
already has the API. The two are now plain C functions installed by a `class_addMethod` **only when
`[NSBundle instancesRespondToSelector:]` says the host does not**, which is
`Foundation/NSBundle+ReceiptURL.m`'s shape, and they are used only here, in the same object as the
class, so no band's file can be left out from under them.

**2. `+load` was too early, and that is the tree's own trap.** `charon/AGENTS.md` records it: "`+load`
runs before `attach.c`'s constructor attaches `__DATA,__charon_catlist`", which is why
`NSBundle+ReceiptURL.m`'s categories are attached from a constructor. The install is now
`__attribute__((constructor))`, for the same reason.

**And the trap survives both, and it is not the oracle.** With the oracle guarded, the differential
aborts, and lldb puts it here:

```
* thread #1, stop reason: EXC_BREAKPOINT (code=1, subcode=0x18ab0c688)
  frame #0: libobjc.A.dylib`objc_opt_respondsToSelector + 48
    0x18ab0c688 <+48>: brk    #0xc472
    0x18ab0c68c <+52>: ldrsh  w8, [x16, #0x1e]
```

`brk` in the optimized `respondsToSelector` stub is the trap for a receiver that is not an object, and
the differential binary holds **no** `respondsToSelector` of its own — so the call is the port's
constructor's `[NSBundle instancesRespondToSelector:…]`, reached before the runtime has vended NSBundle
into the image. `attach.c` is what the tree uses to get past that, and this file does not go through it.

**So the next session's first three commands**, in order:
1. `xcrun nm -u <the renamed object> | grep -i respond` to confirm the caller, then
2. move the two installs behind the same mechanism the rest of the package uses for a Foundation
   category — `charon_catlist`, or a constructor that runs after `+load` (a second, later constructor;
   the weak-import dance is what `Foundation/NSBundle+ReceiptURL.m` avoids by having a real category), and
3. `sh tests/backports/host/bundlerequest/run.sh` again.

**Nothing else in this family is verified.** The class compiles clean under
`-Wall -Werror=objc-missing-property-synthesis` and exports the class, its metaclass and the two
constants; the differential is written and red; there are no mutants, no registry entries and no facts
file; the gates are on the wrong commit.

---

## The trap: your PAC reading is right, and the class reference is what was unsigned

`brk #0xc472` is a pointer authentication failure, not a non-object receiver. The three prints, one run,
from the constructor before it asks anything:

```
charon: NSBundle is 0x1f0ab0e08, in /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation,
        and objc_getClass agrees: 1
```

and the renamed object, the same source compiled with `-DNSBundleResourceRequest=CharonHost…`:

```
$ xcrun nm -u  …/plain/NSBundleResourceRequest.m.o | grep NSBundle
                (undefined) external _OBJC_CLASS_$_NSBundle
$ xcrun nm -m  …/plain/NSBundleResourceRequest.m.o | grep classrefs
                (no __objc_classrefs entry for NSBundle)
```

**The rename does not touch `NSBundle` — it renames the class token only — and the symbol is a plain
external, not a weak one.** So the harness was not pointing it at something else; the *reference itself*
was the problem: the compiler emits a class reference for a `Class` expression and the optimized
`-respondsToSelector:` stub authenticates what that reference holds, and in this process it is not signed
the way the host signs it. **`objc_getClass("NSBundle")` at run time gives a pointer the runtime signed,
and the trap goes** — the print above is the proof, because the print happens on the path that used to
trap.

**And one more of the same shape, found by the same run:** the *second* ask, after the first
`class_addMethod`, traps too. Adding a method rewrites the class, and a class pointer held across that
is not the one the runtime hands out again, so **both answers are now read before either mutation**:

```objc
BOOL hasSet = [bundle instancesRespondToSelector:@selector(setPreservationPriority:forTags:)];
BOOL hasGet = [bundle instancesRespondToSelector:@selector(preservationPriorityForTag:)];
if (!hasSet) class_addMethod(...);
if (!hasGet) class_addMethod(...);
```

**Where it stands:** the trap is *not* cleared — the run still ends on a SIGTRAP (rc 133) after the
constructor's print, so a third `respondsToSelector:` traps, and the next step is the same instrument
again: print each of the remaining ask sites with the pointer it sends and `dladdr` on it. The candidates
are the differential's own two (`[bundleClass instancesRespondToSelector:…]`, already by name) and
`CharonManifestForBundle`'s `bundle.bundlePath`, which is a property send and not a `respondsToSelector`
at all — so the *first* thing to check is that the trap's frame is still the stub and that
`objc_getClass` is not itself the thing being authenticated a second time.

**The oracle question is still open**, so the holdable count is still 9-or-11. It becomes 11 the moment
the private `-initWithTag:` answers in this process, and that measurement is one line away once the run
completes.

---

## The frame, and it is not the port's

One lldb run, a breakpoint on the stub rather than on the trap, because the trap has no frame #1 to
unwind to — `objc_opt_respondsToSelector` is a leaf stub and lldb stops there and stops there:

```
Breakpoint 1: where = libobjc.A.dylib`objc_opt_respondsToSelector
       frame #0: 0x18ab0c658 libobjc.A.dylib`objc_opt_respondsToSelector
      Address: CoreFoundation[0x00000001808fb828] (CoreFoundation.__TEXT.__text + 184712)
      Address: CoreFoundation[0x00000001808fb828] (same)
      Address: CoreFoundation[0x00000001808fb828] (same)
```

**`$lr` is the same CoreFoundation address three times**, and it is not in the port and not in the
differential. So the class-reference story is *finished* — the port's own asks are past, since the
constructor's print appears and the two installs go through — and **the remaining trap is Foundation
calling `-respondsToSelector:` on a receiver that is not an object, three times from one function of
its own.** Something the port does makes Foundation send a message to a non-object, and the only
message sends on a value the port computes are `bundle.bundlePath` in `CharonManifestForBundle` and
`CharonPriorities()[...]`, both reached with a `bundle` that is a parameter: from the constructor's
`objc_getClass`, or from an *installed* method whose self is an NSBundle.

**So the next two commands are, in order:**

```sh
# 1. who is the receiver: the class, printed from the port at the point of use
#    (dladdr in CharonManifestForBundle on the bundle it was handed, as the constructor does)
# 2. the differential's own -[NSBundle ...] calls: both now go through objc_getClass, so if the
#    receiver is still not an object it is the value the port passes on
```

and the most likely candidate, from reading the port rather than the trace: **`CharonManifestForBundle`
is called with `self` in the installed methods, and `self` in a `class_addMethod` implementation is
whatever was sent — the differential sends it on a `Class` (`objc_msgSend(bundle, setPriority, …)` with
`bundle` a `Class`, not an instance) in one of its two paths.** That is a bug in the *test*, not the
port, and it is the first thing to look at: one of the differential's two `setPreservationPriority:`
sends passes `bundle` where an *instance* is meant, and Foundation answers the resulting forward with
its own `respondsToSelector:`.

**Everything after that is still undone:** the private initialiser's answer (9 or 11), the differential
to green, the mutants, the 13 registry entries, the facts file, the light guard, and the gates on the
final commit.

---

## The stack settles it, and my candidate was wrong

`bt 25` at the stub's entry, the hit before the trap:

```
frame #0  libobjc`objc_opt_respondsToSelector
frame #1  CoreFoundation`_CFStringGetFormatSpecifierConfiguration + 32
frame #2  CoreFoundation`__CFStringAppendFormatCore + 336
frame #3  CoreFoundation`_CFStringCreateWithFormatAndArgumentsReturningMetadata + 184
frame #4  CoreFoundation`CFStringCreateWithFormatAndArguments + 164
frame #5  CoreFoundation`CFStringCreateWithFormat + 48
frame #6  CoreFoundation`+[NSObject(NSObject) doesNotRecognizeSelector:] + 152
frame #7  CoreFoundation`___forwarding___ + 1504
frame #8  CoreFoundation`_CF_forwarding_prep_0 + 96
frame #9  CoreFoundation`__invoking___ + 148
frame #10 CoreFoundation`-[NSInvocation invoke] + 424
frame #11 differential`host_initWithTag + 248
frame #12 differential`main + 960
```

**The sender was the test's oracle call, and the receiver is one of CoreFoundation's own** — the trap is
inside `CFString`'s own format path, reached because the host's private `-initWithTag:` forwards to a
selector macOS does not implement, and `doesNotRecognizeSelector:` builds the unknown selector's
signature with `CFStringCreateWithFormatAndArguments`. Nothing in the port, and nothing in the test,
sends a message to a non-object; the port's ask sites were already past (the constructor's print
appears first).

**So the private `-initWithTag:` is not an oracle and never was**, and my guess — that the test passed a
`Class` where an instance was meant — was wrong, as the coordinator said it might be. The differential
no longer sends it: the port calls nothing private and neither does the test, and the class is held to
the header's own words (the tags, the bundle, the 0.5 default, a progress complete at once, the urgent
priority) the way the two `NSBundle` additions already are.

**The trap survives that, which is the open fact.** With the oracle gone, the same SIGTRAP follows the
constructor's print, so a **second** unrecognised-selector path is being reached — most likely a
`respondsToSelector:` the *differential* sends somewhere, and the next step is one `bt 25` on this hit
with the oracle already out, which will name the new frame #11 directly. That is one command and the
run has not had it.

**The counts, settled by the stack:** the family has **no host oracle for the class's state**, so the
eleven rows that can be held at all are held to the header, and the two `NSBundle` methods are among
them with a difference stated. Two more — the two constants — are documented and not measurable. The
plist's two key names are documented. Nothing here is measurable against a host that cannot build the
object, and the status says so rather than implying otherwise.
