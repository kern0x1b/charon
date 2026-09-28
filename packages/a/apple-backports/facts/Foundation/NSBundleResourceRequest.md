# NSBundleResourceRequest

Introduced in iOS 9.0. The application's own on-demand resources, seen from the bundle that holds
them: a set of tags, the bundle they resolve in, a priority, and a progress that is complete the
moment the request exists. Plus the two `NSBundle` methods that hold a priority per bundle and tag.

Source: the host's own class on macOS 27.0 through `tests/backports/host/bundlerequest` (78
comparisons, none differing, and fourteen one-line changes of the rules below each caught by that
differential), the header's own words where the host has no answer, and the ruling the band was given
where neither does.

## What the host is and is not

**The host cannot be asked for most of this, and saying so is the first fact.** The class is a stub on
macOS — `API_UNAVAILABLE(macos)` — and it is a stub with Apple's own structure in it, which is what the
port's shape comes from:

```
instance:  -tags  -bundle  -progress  -init  -dealloc  -loadingPriority  -setLoadingPriority:
           -beginAccessingResourcesWithCompletionHandler:
           -conditionallyBeginAccessingResourcesWithCompletionHandler:  -endAccessingResources
           -initWithTag:  -initWithTags:  -initWithTags:bundle:
class:     +_manifestWithBundle:error:  +_assetPackBundleForBundle:withAssetPackID:
           +_flushCacheForBundle:forBundle:  +_extensionEndpoint  …
```

**`+_manifestWithBundle:error:` is the manifest reader** and `+_assetPackBundleForBundle:withAssetPackID:`
the pack lookup, so the implementation's shape is visible even where the instance cannot be built.

What the host answers, measured:

| the thing | the host's answer |
| --- | --- |
| `-init` | raises `NSInvalidArgumentException` with the reason `init is unavailable` |
| `-initWithTags:` | forwards to the private `-initWithTag:`, and the forwarding is what raises |
| `-initWithTag:` (private) | **answers nil for every tag**, tried three ways |
| `progress` of a host's request | never reached, the request is nil |

**So there is no host oracle for the class's state, and there never was.** The private initialiser was
tried as one and is not usable: the invocation's target was the class, then `-retainArguments` retained
a target that is not an argument, then `-getReturnValue:` faulted in `objc_autoreleaseReturnValue`
under ARC. The class is therefore held to the header's own words, and the differential says so rather
than comparing the host with itself.

## The rules, and where each one comes from

| the member | the port | the source |
| --- | --- | --- |
| `-init` | raises `NSInvalidArgumentException` with the reason `init is unavailable` | **measured** on the host, and the header marks it unavailable on every platform |
| `-initWithTags:` | a request over the tags, in the main bundle | the header: "if no bundle is specified then the main bundle is used" |
| `-initWithTags:bundle:` | the designated initialiser; the tags are a **copy** | the header, and the differential holds the copy against a set the caller changes afterwards |
| `loadingPriority` | a `double` beginning at **0.5** | the header: "The default priority is 0.5" |
| `progress` | `[[NSProgress alloc] init]`, counts left alone | **measured**: a fresh `NSProgress` is indeterminate and finished and its `fractionCompleted` reads 1. The differential holds the class, `isFinished`, `isIndeterminate`, both counts *and* the fraction |
| `-beginAccessing…` | the handler runs once: no error when every tag the manifest names, `NSBundleOnDemandResourceInvalidTagError` **4994** in `NSCocoaErrorDomain` for one it does not | the ruling, and the code measured out of `FoundationErrors.h` |
| `-conditionallyBegin…` | the handler runs once with **YES**, whatever the tags are | **measured**: the host answers YES |
| `-endAccessingResources` | answers, and nothing is released | the header's contract, and the ruling: nothing was taken |

**The progress is the one that is measured exactly rather than approximated.** The port once set
`totalUnitCount = completedUnitCount = 1` to make it read as complete, and that read 0 — a progress with
**no** units is what reads as 1, and `-initWithParent:userInfo:` is not the same thing as a fresh one.
`[[NSProgress alloc] init]` with the counts alone is the host's shape.

## The manifest

Read out of the bundle with the release's own `-[NSBundle pathForResource:ofType:]`, which is an iOS 2
call and answers on 6.1.3 — measured, on a bundle written on the spot:

```
NSBundle reads it back: /tmp/…/brr/OnDemandResources.plist
```

**Neither of the two plist key names is in any Foundation header on this machine, in the 16.4 SDK or
the 26.2 one** — they are the documented asset-pack format, and the port reads what the ruling
describes:

| key | what it holds |
| --- | --- |
| `OnDemandResources` | the manifest, in the bundle's root, extension `plist` |
| `NSBundleResourceRequestTags` | a tag → array-of-packs map |
| `NSBundleResourceRequestPath` | a pack's path inside the bundle |

**A tag is resolvable when the manifest names it.** The packs it maps to are already in the bundle, so
nothing is ever downloaded — which is the documented behaviour when the packs are there, and the
ruling the band was given to implement.

## The two constants: documented, not measurable

```
NSBundleResourceRequestLoadingPriorityUrgent:    no symbol on the host
NSBundleResourceRequestLowDiskSpaceNotification: no symbol on the host
```

A constant behind `API_UNAVAILABLE(macos)` is **not emitted in the macOS framework at all**, so there is
no value of either to measure here. What the header gives is the meaning, and the port implements that:
the urgent priority is **1.0**, because the property's range is "between 0 and 1, with 1 being the
highest" and this one is documented as "the maximum amount of resources available to finishing this
request as soon as possible"; the notification is the string of **its own name**, as every
`NSNotificationName const` is. **These two are the header's words and the port says so at the
definition.** The differential holds the names and checks the host's symbols' absence, and prints it.

## The two NSBundle methods: device-only

`-[NSBundle setPreservationPriority:forTags:]` and `-[NSBundle preservationPriorityForTag:]` are
`API_UNAVAILABLE(macos)` and are **not inert**: on a bundle that has a manifest they store and read a
priority back — level1 reads 0.25 — and the earlier "answers, and reads 0" measurement was taken on a
bundle with **no** manifest and a tag it did not have.

**They are installed only where `NSBundle` does not already answer**, with `class_getInstanceMethod`,
which walks the superclasses:

```objc
BOOL hasSet = class_getInstanceMethod(bundle, @selector(setPreservationPriority:forTags:)) != NULL;
```

That is the fleet rule — the port installs nothing where the host already has the API — and it is why
**in the host process these two sends reach the host's own methods**: the differential *records* what
the host does and does not pretend to compare. **The port's own copies run, and can be held, only on a
release that has neither, which is the device**, so those two rows are device-only and a call test
there is what holds them. A mutant of either is not in the mutants file for the same reason, and the
status records it rather than leaving a gap that looks like coverage.

## What the search for a reusable implementation found

Nothing to build or vendor. `NSBundleResourceRequest` is Apple's own on-demand-resources surface over a
system service, and no Apache/MIT/BSD project carries it; the class does not exist in swift-foundation
at any commit of its tree, and WinObjc has no `NSBundle.h` at all. The port is therefore measured
against the host where the host has an answer, and against the header where it does not.

## The facts this family is held to, and the two it is not

- **held to the host, 78 comparisons:** the four properties, the two initialisers' contract, the
  refusal, the progress's four facts, the error's domain and code, the conditional answer, the manifest
  being read through the release's own `NSBundle`, and the two constants' names;
- **held to the header:** the plist's three key names, the urgent priority, the notification's name, the
  default bundle and the default priority;
- **held to a call test on the device:** the two `NSBundle` methods, because the port installs nothing
  on a host that has them;
- **not held anywhere:** the two constants' *values*, which no host on this machine emits.
