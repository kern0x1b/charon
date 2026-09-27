# HomeKit's string constants

Every `NSString *const` the HomeKit headers declare is a value the release holds, not a name the
header invents: the accessory category a light bulb belongs to is the HAP UUID
`57D56F4D-3302-41F7-AB34-5365AA180E81`, the service type of a light bulb is
`00000043-0000-1000-8000-0026BB765291`, and the metadata format of a boolean characteristic is the
string `bool`. None of that is derivable from the name, and a porter who writes it from the name gets
a value that looks right and pairs with nothing. So all 255 of them are read out of a real
HomeKit.framework, one value per symbol, and written down here.

## How each value was read

`modules/apple/dyld.lua` is the project's own cache reader, and the read is three steps per symbol:

1. the export table gives the symbol's own address inside HomeKit.framework;
2. `pointer_at` resolves the pointer stored there through that cache's slide information (version 1,
   2, 3 or 5, whatever the cache holds) to the address of the `__CFConstantString`;
3. the `__CFConstantString`'s `char *` at +16 (arm64) or +8 (armv7) gives the characters, and its
   length at the next word gives how many there should be.

The last step is the check that makes the other two trustworthy: **the length the `__CFConstantString`
claims equals the number of bytes the C string actually runs to, in every case, in every cache.**
255 symbols, 0 mismatches. A wrong unsliding lands inside some other mapping and reads *a* string;
it lands on one whose own length field disagrees with its bytes, which is what a length field is for.

Three caches were read and compared: `12.0/dyld_shared_cache_arm64` (arm64),
`16.0/dyld_shared_cache_arm64e` (arm64e) and `18.0/dyld_shared_cache_arm64e` (arm64e), so the 64-bit
reader's two paths are both exercised and neither is trusted alone. 281 of the 284 symbols the two
frameworks declare are held by at least one of them, and **all three agree on every value they hold**
— no cache disagrees with another on any of the 255.

## The two releases that changed a value

`HMServiceTypeMicrophone` and `HMServiceTypeSpeaker` are the two, and both are a real change of
Apple's rather than a difference of reading:

| constant | 8.4.1 armv7s | 10.3.4 armv7s | 12.0 arm64 | 16.0 / 18.0 |
| --- | --- | --- | --- | --- |
| `HMServiceTypeMicrophone` | `00000046-0000-1000-8000-0026BB765291` | `00000112-0000-1000-8000-0026BB765291` | `00000112-…` | `00000112-…` |
| `HMServiceTypeSpeaker` | `00000048-0000-1000-8000-0026BB765291` | `00000113-0000-1000-8000-0026BB765291` | `00000113-…` | `00000113-…` |

The later value is what the port carries, for the same reason the rest of the surface carries SDK
26.2's value: an application built against 26.2 compares against what 26.2 exports. The 8.4.1 value is
recorded here rather than dropped, because it is what a release this port runs on would have paired
against, and the difference is a fact about the protocol rather than about the reader.

## Where the header's availability is later than the release that exports it

The files are named for the release `tools/release-split.lua` **measures** as the first that exports
each symbol, because that is what the band machinery places an object by, and not for the release the
26.2 header annotates. For 63 of the 255 the two differ, and in every case the header is the later of
the two: a release already exported the symbol before the SDK says it arrived. The measurement is what
the band needs, so the port follows the measurement and records the difference here, which is what
COORDINATION.md's "the header can be wrong" is about. What is carried is the value every one of these
releases agrees on, so the choice of file changes which release carries the symbol, never its value.

| the header says | the release first exporting it | how many |
| --- | --- | --- |
| 10.0 | 8.0 | 2 |
| 8.0 | 9.0 | 2 |
| 10.0 | 10.0.1 | 21 |
| 18.0 | 10.0.1 | 1 |
| 11.0 | 10.3.4 | 1 |
| 18.0 | 11.0 | 2 |
| 11.2 | 12.0 | 12 |
| 18.0 | 12.0 | 1 |
| 18.0 | 16.0 | 21 |

The full list, one name per row, is in the delivery report; the two that change a band boundary by
more than a patch release are `HMServiceTypeMicrophone` and `HMServiceTypeSpeaker`, whose values also
changed, above.

## Where the release itself holds a placeholder

Eleven of the values are the symbol's own name, and that is Apple's, measured in all three caches:

    HMActionSetTypeHomeArrival  = HMActionSetTypeHomeArrival
    HMActionSetTypeSleep        = HMActionSetTypeSleep
    HMCharacteristicPropertyWritable = HMCharacteristicPropertyWritable
    HMErrorDomain              = HMErrorDomain

This is not the port filling in a name. HomeKit's action set types, its characteristic property names
and its error domain are opaque identifiers to every implementation, including Apple's: the release
stores the name as the string, and comparisons in the framework use pointer identity or the same
literal. The port stores what the release stores, and the length field agreeing with the bytes is the
check that this is a real value and not a misread.

## What the three iOS 26.2 constants are

`ASGeneratedPasswordKindStrong`, `ASGeneratedPasswordKindAlphanumeric` and
`ASGeneratedPasswordKindPassphrase` are declared in AuthenticationServices and arrived in iOS 26.2,
which no firmware this machine holds ships. There is therefore **no release to read them from**, and
the port does not invent one: it is reported as not carried, in
`registry/AuthenticationServices/ios26.json`, with the reason that no release exists to read.

## What this does not cover

The 324 `header-ok` rows of HomeKit's constant surface are enum cases, which need no symbol by
construction, and the 63 enum types likewise; the ledger's own `header-ok` says so and this file adds
nothing to it.

The model — `HMHome`, `HMRoom`, `HMAccessory` and the rest — is a separate family and is not in this
delivery. `CharonHomeKitStore.m` and `CharonHAPBignum.m` are here because they are what the model and
the HAP transport are written on, and both are the port's own symbols, so no band drops them.
