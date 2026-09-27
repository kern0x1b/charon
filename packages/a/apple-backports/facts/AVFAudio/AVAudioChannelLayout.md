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
