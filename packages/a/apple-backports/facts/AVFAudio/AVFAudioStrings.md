# The string constants of AVFAudio this library carries

Twenty-five of them, in five object files, one file per release the strings arrived in - an object is
carried from one release on (`modules/apple/backports.lua`, `minimums()`: an object whose registry
entries name different minimums is refused), so a 7.0 string cannot sit in a 14.0 file.

**Every value was read out of a real release. None was written from the name.** Two readers, and
where both cover a name they agree:

| Reader | How |
| --- | --- |
| the arm64e shared cache of iOS 18.0 | `.agent-work/plan-and-analysis/avfaudio/cfconst.lua`, the symbol's address from `libAVFAudio.dylib`'s export trie, then the pointer it holds, then the `__cfstring` that pointer names, then the bytes - with `cache.pointer_at` applying the cache's own slide info. The control for the reader is `UIApplicationOpenSettingsURLString` in the same cache, which it answers `app-settings:`. |
| the arm64 caches of iOS 7.0 and 12.0 | the same reader, on a cache that is one file, where the image is `/System/Library/Frameworks/AVFoundation.framework/libAVFAudio.dylib`. |
| the host's own AVFAudio | `.agent-work/plan-and-analysis/avfaudio/probe3.c`, `dlsym` for the symbol and `CFStringGetCString` for the bytes. |

`tools/cfconst.py` in the repository root reads a **32-bit** cache header and a 16-byte symbol entry
and cannot read the 64-bit split caches 16.0 and 18.0 are; the reader above is the same walk over
`modules/apple/dyld.lua`'s `open_cache`/`pointer_at`, which is what the header layout of those caches
needs. Its one known gap is the `.dyldlinkedit` sub-cache of a split cache: the export trie of
16.0's and 18.0's AVFAudio image has the older names, and the image's symbol table that holds the
rest is in the linkedit sub-cache, which `read_address` maps but the image's own `__LINKEDIT` offsets
do not reach. That gap is why the six 14.0 port names below have the host as their only source.

| Constant | Value | Read from |
| --- | --- | --- |
| `AVAudioUnitTypeOutput` | `Output` | 18.0 cache, host |
| `AVAudioUnitTypeMusicDevice` | `Music Device` | 18.0 cache, host |
| `AVAudioUnitTypeMusicEffect` | `Music Effect` | 18.0 cache, host |
| `AVAudioUnitTypeFormatConverter` | `Format Converter` | 18.0 cache, host |
| `AVAudioUnitTypeEffect` | `Effect` | 18.0 cache, host |
| `AVAudioUnitTypeMixer` | `Mixer` | 18.0 cache, host |
| `AVAudioUnitTypePanner` | `Panner` | 18.0 cache, host |
| `AVAudioUnitTypeGenerator` | `Generator` | 18.0 cache, host |
| `AVAudioUnitTypeOfflineEffect` | `Offline Effect` | 18.0 cache, host |
| `AVAudioUnitTypeMIDIProcessor` | `MIDI Processor` | 18.0 cache, host |
| `AVAudioUnitManufacturerNameApple` | `Apple` | 18.0 cache, host |
| `AVAudioUnitComponentTagsDidChangeNotification` | `AVAudioUnitComponentTagsDidChangeNotification` | 18.0 cache, host |
| `AVAudioUnitComponentManagerRegistrationsChangedNotification` | `AVAudioUnitComponentManagerRegistrationsChangedNotification` | host |
| `AVAudioSessionModeSpokenAudio` | `AVAudioSessionModeSpokenAudio` | 7.0 cache, 12.0 cache, host |
| `AVAudioSessionModeVoicePrompt` | `AVAudioSessionModeVoicePrompt` | 7.0 cache, 12.0 cache, host |
| `AVAudioSessionPortCarAudio` | `CarAudio` | 7.0 cache, 12.0 cache, host |
| `AVAudioSessionPortAVB` | `AVB` | host |
| `AVAudioSessionPortDisplayPort` | `DisplayPort` | host |
| `AVAudioSessionPortFireWire` | `FireWire` | host |
| `AVAudioSessionPortPCI` | `PCI` | host |
| `AVAudioSessionPortThunderbolt` | `Thunderbolt` | host |
| `AVAudioSessionPortVirtual` | `Virtual` | host |
| `AVAudioSessionPortContinuityMicrophone` | `ContinuityMicrophone` | host |
| `AVAudioApplicationMuteStateKey` | `AVAudioApplicationMuteStateKey` | host |
| `AVAudioApplicationInputMuteStateChangeNotification` | `AVAudioApplicationInputMuteStateChangeNotification` | host |

`AVAudioSessionModeDualRoute` and `AVAudioSessionModeShortFormVideo` are **not** carried here: the
corpus lists both as `code+lift`, but no release among those held exports either name
(`dyld.load` over 7.0, 12.0, 16.0 and 18.0 - see `.agent-work/plan-and-analysis/avfaudio/whoknows.lua`),
so there is no value to read and none was invented. They belong with the session's mode handling,
where the corpus's own classification of them can be settled with a release that does export them.

The five names of iOS 18.2 and later (`AVAudioApplicationMuteStateKey`,
`AVAudioApplicationInputMuteStateChangeNotification`) are readable only from the host, because 18.2
is a release no cache is held for and 18.0 is the earliest that has them. Their shape - the
constant's own name - is the shape AVFAudio uses for a notification and a userInfo key, and
`AVAudioUnitComponentTagsDidChangeNotification` and `AVAudioSessionModeVoicePrompt`, read out of a
cache, are that same shape; the host's answers agree with both.
