# The URL resource keys and their neighbours, with the values real releases shipped

44 exported string constants of Foundation that arrived between iOS 7 and iOS 18: the file protection
group, the volume and shared-item keys, the iCloud user defaults notifications, the URL resource keys
of 8.0, the attribute names of 15.0, the credential storage key of 7.0, the one stream service type,
and the six that no release below 18.0 exports.

Source: the SDK 26.2 headers for the declarations and their availability; for every value, the dyld
shared cache of a real release, read through `tools/corpus/cache-value.lua` over the project's own
cache reader. **No value is taken from a header comment, from the host framework, or from the
identifier's own spelling** — and the three that differ from their own name below are the reason.

## The values, as the releases shipped them

| the constant | the value a release holds | read from |
| --- | --- | --- |
| `NSPresentationIntentAttributeName` | `NSPresentationIntent` | 16.0 |
| `NSReplacementIndexAttributeName` | `NSReplacementIndex` | 16.0 |
| `NSUserDefaultsSizeLimitExceededNotification` | `com.apple.CFPreferences.byteCountLimitReached` | 9.3 |
| `NSStreamNetworkServiceTypeCallSignaling` | `kCFStreamNetworkServiceTypeCallSignaling` | 10.0.1 |
| `NSURLIsApplicationKey` | `_NSURLIsApplicationKey` | 9.0 |
| every other one here | its own name | the release in the table below |

Five of the 44 are not the string their own name suggests, and one of them is not even an
`NSURL…` name: the notification a user defaults posts when the store is full is a
`CFPreferences` name, and the attribute names of 15.0 drop the `AttributeName` ending. Guessing any
of these from the header would have been wrong, which is the whole reason they were read.

## Which release first exports each of them, and where the port stops carrying it

Measured over every held release the machine has a cache for — 3.1.3 to 9.3.6 on armv7, 10.0.1 and
10.3.4 on armv7s, 10.0.1 to 12.0 on arm64 and 16.0 and 18.0 on arm64e — by asking every image of
each release whether it exports the symbol. The first release that does is where the release itself
carries the constant, and the port's object must be out of the band from there on: a band that both
defines and links a symbol the release has is a duplicate at load.

| first release that exports it | the keys | the port's `maximum` |
| --- | --- | --- |
| 7.0 | `NSURLCredentialStorageRemoveSynchronizableCredentials` | 6.1.6 |
| 8.0 | the URL resource keys of 8.0, `NSThumbnail1024x1024SizeKey`, the two iCloud keys | 7.1.2 |
| 8.3 | `NSURLUbiquitousItemIsSharedKey`, the two `…SharedItemRole…` | 8.2 |
| 9.0 | the five `NSURLFileProtection…`, `NSURLIsApplicationKey`, `NSURLUbiquitousSharedItemOwnerNameComponentsKey` | 8.4.1 |
| 9.3 | the three `NSUbiquitousUserDefaults…`, `NSUserDefaultsSizeLimitExceededNotification` | 9.2.1 |
| 10.0.1 | the volume keys, the `…SharedItem…` permissions and roles, `NSURLCanonicalPathKey`, `NSStreamNetworkServiceTypeCallSignaling` | 9.3.6 |
| 16.0 | the three attribute names, the progress file operation kind | 12.0 |
| 18.0 | `NSURLFileProtectionCompleteWhenUserInactive`, `NSURLVolumeMountFromLocationKey`, `NSURLVolumeSubtypeKey`, `NSURLVolumeTypeNameKey`, `NSURLFileIdentifierKey`, `NSURLDirectoryEntryCountKey` | 16.0 |

Three of these are not what the SDK's availability suggests, and they are the reason the ladder was
walked rather than read off the headers: `NSURLUbiquitousItemIsSharedKey` is a 10.0 API whose
*symbol* a release exports from **8.3**; `NSURLFileProtectionCompleteWhenUserInactive` is a 10.0 API
that **18.0** is the first to export, and `NSURLVolumeMountFromLocationKey`, `NSURLVolumeSubtypeKey`,
`NSURLVolumeTypeNameKey`, `NSURLFileIdentifierKey` and `NSURLDirectoryEntryCountKey` with it. A
`maximum` read off the availability would have put the port's own definition into a band where the
release already has the symbol.

## One object per group

The eight files are one release group each, and that is the rule rather than taste: an object stays
in a band while any of its entries is in range, so a file holding the 9.0 group and the 9.3 group
would still be compiled in the 9.3 band, where the release exports the 9.0 symbols itself, and
define them a second time. `tools/release-split.lua` measures the same thing from the objects
themselves after a build.

## What these keys are for, on the port's own release

A key is a name, and a name answers nothing by itself: what a key is worth is
`-[NSURL getResourceValue:forKey:error:]` and `-[NSURLResourceValues …]` answering for it. The keys
above are carried whole so that an application of 2024 links and runs; the reading of them is the
existing `NSURLResourceKeys14.m` and `NSURLVolumeKeys.m`, and the rows for the *values* — which of
these a 6.1.3 file system can answer at all — are separate rows, measured separately. The
protection keys, the volume keys and the canonical path are readable on 6.1.3 through `getattrlist`
and `statfs`; the iCloud container's own state (whether an item is shared, who its owner is, whether
a download was asked for) is the `cloudd` daemon's state, and 6.1.3 has no API that reports it, so
those keys answer the documented "no value" rather than a guess.
