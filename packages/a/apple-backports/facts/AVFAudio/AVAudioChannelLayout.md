# AVAudioChannelLayout

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), over the `AudioChannelLayout` of
`CoreAudioTypes.h`.

**The channel count and the canonical tag are the release's own answers**, not a table the port keeps:
`AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, ...)` answers a layout for a tag
and `kAudioFormatProperty_TagsForNumberOfChannels` answers the tags of a count, and both are answered
by `AudioFormatGetProperty`, which iOS 6.1.3 exports. The table in `CharonAVFAudioCommon.m` is only
the fallback for the tags the release's `AudioFormat` declines, so that a layout AVFAudio names
itself still answers.

Both properties are asked for their size first and filled afterwards: `AudioChannelLayout` has a
variable-length tail of `AudioChannelDescription`, so a buffer of `sizeof(AudioChannelLayout)` is
only enough for a layout with no descriptions.

**The header's two refusals are refusals.** `-initWithLayoutTag:` answers `nil` for
`kAudioChannelLayoutTag_UseChannelDescriptions` and `kAudioChannelLayoutTag_UseChannelBitmap`, which
name a layout only by what the caller supplies. `-initWithLayout:` converts a
`UseChannelDescriptions` layout to a more specific tag where the release has one for that channel
count, and copies the descriptions; the conversion is the release's, because the release is what
knows its tags.

**`-isEqual:`** compares the tag, and then the bitmap for a bitmap layout or the channel
descriptions for a described one, which is the header's "the underlying AudioChannelLayoutTag and
AudioChannelLayout are compared for equality".

**`NSSecureCoding`** is declared by the class in the header, so the two members are answered and the
secure archiver of iOS 6 reads and writes a layout: the tag and the channel count go in, the channel
descriptions are written per index. A decoded layout is the same layout; an archive without a tag
decodes to `nil`.

## Host answers for `-initWithLayout:`

Measured on this macOS host (Darwin 27.0.0, arm64) by `tools/gen-avchannellayout-probe.m`, built by
the `channellayout` target of `tools/gen/host/xmake.lua` and run one input per process against the
host's own AVFAudio. The probe creates the object and reads its tag and channel count; nothing else
is touched.

| input | host answer | layout tag | channels | exception |
|-------|-------------|------------|----------|-----------|
| NULL layout | `nil` | - | - | none |
| tag 0 (UseChannelDescriptions), no descriptions | object | `0x00000000` | 0 | none |
| tag `0xFFFF0003` (no release defines it) | object | `0xFFFF0003` | 3 | none |
| `kAudioChannelLayoutTag_Stereo` (the control) | object | `0x00650002` | 2 | none |

So the header's nonnull declaration of `-initWithLayout:` is not kept by the framework itself for a
NULL layout: the host answers `nil`, with no exception and no crash. The host does not refuse tag 0
or an unknown tag either; it answers an object, and for the unknown tag the channel count is 3, the
low 16 bits of the tag.

The port's `-initWithLayout:` answers `nil` for a NULL layout, when `[super init]` fails, and when its
`calloc` fails, and an object for every other input, the unknown tag and tag 0 among them. Its header
comment also names a refusal for a layout that carries neither a countable tag nor channel
descriptions; the code does not check for it. The port's channel count for an unknown tag is not
measured here.
