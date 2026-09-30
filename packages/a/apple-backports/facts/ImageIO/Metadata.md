# The metadata tag container of iOS 7, on a release whose ImageIO has no metadata tree

`CGImageMetadata` and `CGImageMetadataTag` arrived in iOS 7. iOS 6.1.3 and 4.3 have neither the
container nor the tags, and they are carried in `Graphics/ImageIOMetadata7.m`.

## Why the whole surface is one object

`tools/cache-index/first-rung.py`, asked for each of the 26 `CGImageMetadata*` and `CGImageSource*`
symbols the iOS 7 headers declare, over the 50 held rungs (2026-09-30,
`.agent-work/runs/io-rungs.txt`): **every one of them first appears on the 7.0 rung** and on no rung
below it. The three rungs below 7.0 that carry the ladder's low end - 3.0, 4.0, 4.3, 5.0, 5.1.1,
6.0, 6.1, 6.1.3, 6.1.4, 6.1.6 - carry none of them. So one object holds all 26 and `release-split`
has nothing to split.

What iOS 6 does export is used, not defined: `CGImageSourceCopyMetadataAtIndex` and the eight
`kCGImageMetadataNamespace...` names are the release's own (`registry/ImageIO/exported.json`,
`facts/ImageIO/ImageIOExports.md`), and the prefixes are carried as strings by
`Graphics/ImageIONames70.m` and `Graphics/ImageIONames113.m`. The default-prefix table in the object
asks which public namespace constant the caller passed, so no namespace URI is written in this
library at all.

## What the host answers, and where the port differs

`tests/backports/host/imageio-metadata/` is the differential: `cases.m` is compiled twice, once
against the host's own ImageIO and once against this object, and `run.sh` compares the two outputs
line by line. Measured 2026-09-30: `33 cases compared, 1 declared differences, mutation RED`.

**A function has one name in both libraries, so the two builds are two programs.** Linking this
object and the host's ImageIO into one program cannot be done - the linker sees one definition twice -
which is why the port's own object is read out of the executable by `dladdr` and the run fails if any
of these functions is still ImageIO's. That check is in the port build itself, not assumed.

`tests/backports/host/imageio/run.sh` is not a differential for this family and never was: it links
the host's ImageIO on both sides of all five of its checks, so it compares the host with itself. The
four `ImageIO` name pages that carried headline counts named no harness at all.

### A tag created with a NULL prefix takes the public prefix of its namespace

`CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, "Name", ...)` answers `prefix=exif`,
and the same for all ten public namespaces (`default-prefix exif..xmpRights`, ten cases, both builds).
A namespace with no public prefix and no prefix of its own cannot be resolved, and the port answers
NULL - which is the one declared difference:

| case | host | port |
| --- | --- | --- |
| `tag unknown-ns-no-prefix` | a non-NULL tag whose every accessor answers nil and whose type is `-1` | NULL |

The port follows `CGImageMetadata.h`: "Returns NULL if a tag could not be created with the specified
parameters."

### `kCGImageMetadataTypeDefault` reads the type off the CFType of the value

`default string 1`, `default number 1`, `default array 3`, `default dictionary 6`, both builds. A
number becomes a string, as the host does.

### An array's or a structure's bare strings become tags, and an array element is named by its position

`value default array elements`: a tag built from `@[@"a", @"b"]` answers an array of two
`CGImageMetadataTag`s named `[0]` and `[1]`, in the tag's own namespace and prefix; a structure's
value answers `{F = <tag F>}`. The header says the elements "must be either a CFStringRef or
CGImageMetadataTagRef"; the host resolves a bare string into a tag, so the port does the same.

### The two opaque types are identified, and anything else is refused

iOS 6 exports `CGImageSourceCopyMetadataAtIndex` and answers an object of the **release's own class**,
which is not a metadata container this library laid out. Every entry point asks `CFGetTypeID` first
and answers NULL for anything else (`PORTONLY foreign-tag`, `foreign-metadata`, `foreign-copy`), so a
caller that mixes the release's metadata with this container is told no instead of being made to read
memory that is not ours.

The host traps (SIGTRAP) on the three `_Nonnull` arguments `CGImageMetadataTagCreate` declares
(`xmlns`, `name`, `value`); the port refuses with NULL, and those three refusals are recorded as
port-only records because there is no host answer to compare.

## What this commit does not carry

Nine `CGImageMetadata*` functions of the same iOS 7 surface - the path, matching, enumeration and XMP
half - arrive in the next commits of this slice, and their registry rows still say `absent`. What is
refused here and why is in each row.