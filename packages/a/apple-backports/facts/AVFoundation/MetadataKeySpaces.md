# The metadata key-space names

Thirty constants, in the four key spaces Apple's own tables name: the QuickTime metadata key space
(`mdta/`), the ISO user data space (`uiso/`), the QuickTime user data space (`udta/`), the common
space (`common/`), and the object types a machine-readable code names. `packages/a/apple-backports/AVFoundation/`
carries them in three files, one per release they arrived in.

## How the values were read

Not out of a header. Each name was resolved as an exported symbol in the **host's own AVFoundation**
with `dlsym(RTLD_DEFAULT, name)` and the `NSString *const` it points at printed, twice: once as text
and once as bytes, so that a value with a non-ASCII byte could not be mistaken for a rendering
accident. All 28 answered; none was absent from the host.

Then the same table was read out of two builds and the two were diffed, which is what
`tests/backports/host/avf-metadata/run.sh` does: once linked against Apple's framework alone, and
once with the port's three files in the same binary, every name renamed to `charon_host_<name>` so
the port's definition and Apple's sit side by side. The port's table is byte-identical to the host's.

Two things that measurement settled, and which a header reading would have got wrong:

- **`AVMetadataIdentifierQuickTimeUserDataAccessibilityDescription` is the eleven ASCII characters
  `udta/%A9ade`.** The `%A9` is literal text - a percent, a capital A, a nine - not a copyright sign
  and not the byte 0xA9. The byte dump reads `75 64 74 61 2f 25 41 39 61 64 65`, all of them below
  0x80.
- **`AVMetadataObjectTypeCodabarCode` is `Codabar`**, a capital C, while the five GS1 and ISO types
  beside it are lower-case dotted names. The mutant in the differential is exactly that one letter,
  because a case difference in a UTI is the kind of thing no address comparison would see.

## The values

| constant | value the host answered | bytes |
| --- | --- | --- |
| `AVMetadataCommonIdentifierAccessibilityDescription` | "common/accessibilityDescription" | 31 |
| `AVMetadataCommonKeyAccessibilityDescription` | "accessibilityDescription" | 24 |
| `AVMetadataISOUserDataKeyAccessibilityDescription` | "ades" | 4 |
| `AVMetadataIdentifierISOUserDataAccessibilityDescription` | "uiso/ades" | 9 |
| `AVMetadataIdentifierQuickTimeMetadataAccessibilityDescription` | "mdta/com.apple.quicktime.accessibility.description" | 50 |
| `AVMetadataIdentifierQuickTimeMetadataAutoLivePhoto` | "mdta/com.apple.quicktime.live-photo.auto" | 40 |
| `AVMetadataIdentifierQuickTimeMetadataDetectedCatBody` | "mdta/com.apple.quicktime.detected-cat-body" | 42 |
| `AVMetadataIdentifierQuickTimeMetadataDetectedDogBody` | "mdta/com.apple.quicktime.detected-dog-body" | 42 |
| `AVMetadataIdentifierQuickTimeMetadataDetectedHumanBody` | "mdta/com.apple.quicktime.detected-human-body" | 44 |
| `AVMetadataIdentifierQuickTimeMetadataDetectedSalientObject` | "mdta/com.apple.quicktime.detected-salient-object" | 48 |
| `AVMetadataIdentifierQuickTimeMetadataLivePhotoVitalityScore` | "mdta/com.apple.quicktime.live-photo.vitality-score" | 50 |
| `AVMetadataIdentifierQuickTimeMetadataLivePhotoVitalityScoringVersion` | "mdta/com.apple.quicktime.live-photo.vitality-scoring-version" | 60 |
| `AVMetadataIdentifierQuickTimeMetadataLocationHorizontalAccuracyInMeters` | "mdta/com.apple.quicktime.location.accuracy.horizontal" | 53 |
| `AVMetadataIdentifierQuickTimeMetadataSpatialOverCaptureQualityScore` | "mdta/com.apple.quicktime.spatial-overcapture.quality-score" | 58 |
| `AVMetadataIdentifierQuickTimeMetadataSpatialOverCaptureQualityScoringVersion` | "mdta/com.apple.quicktime.spatial-overcapture.quality-scoring-version" | 68 |
| `AVMetadataIdentifierQuickTimeUserDataAccessibilityDescription` | "udta/%A9ade" | 11 |
| `AVMetadataObjectTypeCatBody` | "catBody" | 7 |
| `AVMetadataObjectTypeCodabarCode` | "Codabar" | 7 |
| `AVMetadataObjectTypeDogBody` | "dogBody" | 7 |
| `AVMetadataObjectTypeGS1DataBarCode` | "org.gs1.GS1DataBar" | 18 |
| `AVMetadataObjectTypeGS1DataBarExpandedCode` | "org.gs1.GS1DataBarExpanded" | 26 |
| `AVMetadataObjectTypeGS1DataBarLimitedCode` | "org.gs1.GS1DataBarLimited" | 25 |
| `AVMetadataObjectTypeHumanBody` | "humanBody" | 9 |
| `AVMetadataObjectTypeMicroPDF417Code` | "org.iso.MicroPDF417" | 19 |
| `AVMetadataObjectTypeMicroQRCode` | "org.iso.MicroQR" | 15 |
| `AVMetadataObjectTypeSalientObject` | "salientObject" | 13 |
| `AVMetadataQuickTimeMetadataKeyAccessibilityDescription` | "com.apple.quicktime.accessibility.description" | 45 |
| `AVMetadataQuickTimeUserDataKeyAccessibilityDescription` | "@ade" | 4 |

## What is not here

The metadata *objects* - `AVMetadataItemFilter`, `AVMetadataGroup`, `AVDateRangeMetadataGroup`,
`AVMutableDateRangeMetadataGroup`, `AVMetadataItemValueRequest` and the five body-object classes -
are owed and are written down in [AVFoundationOwed.md](AVFoundationOwed.md) with the measurement that
says why this file does not carry them. Two of the reasons are worth repeating here because they
decided the shape of this slice:

- **The host will not build one.** `+[AVMetadataItem metadataItemWithIdentifier:value:extraAttributes:]`
  does not exist on the host build, `-[AVMetadataGroup initWithItems:]` does not, and
  `-[AVMetadataItemFilter initWithIdentifiers:]` does not. A differential needs both sides to answer
  the same question from the same input, and there is no public way to hand Apple's classes an input,
  so there is nothing to compare. The current spelling of that filter's member is `allowList`, and
  the 7.0-era `identifiers` is not in the host build at all.
- **The body-object classes carry state a detection produces.** Measured on the host:
  `AVMetadataBodyObject` has 5 own methods and an instance size of 24, `AVMetadataHumanBodyObject`
  has 8 and an instance size of 40, and the three others have 6 or 7. An empty class of that name
  would resolve every `isKindOfClass:` and answer nothing, which is the silent shape this registry
  calls out by name; those rows want `inert` with the effect written down, or a real body-object
  behind a capture pipeline this port does not have.

## Reuse, and what was searched for first

`AVMetadataItem+Identifiers8.m` already carries the 8.0 identifiers and the three properties, and its
facts file `AVMetadataItemIdentifiers.md` records the key-space arithmetic they do. Nothing here
duplicates it: the 8.0 names are not in this slice and the 13.0+ names do not collide with them. The
existing constant files (`AVFoundationConstants90.m` … `AVFoundationConstants120.m`) are the pattern
followed for the shape of a constants file, and the missing names there are why these rows were
`absent` rather than written down earlier.
