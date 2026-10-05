# Audio.swift: left out of the RealityFoundation overlay, and why

`files/RealityFoundation/Audio.swift` (468 lines, five public types: `AudioResource`,
`AudioFileResource`, `AudioListener`, `AudioPlaybackController`, `AudioEngine`, and the enums and event
types inside them) is in the package and is not compiled into the `RealityFoundation` overlay.
`packages/s/swift-runtime/xmake.lua` says so beside the source list, and this is that note's long form.

## The cause, measured

`Audio.swift` writes `AVAudioPlayerNode.volume` twice:

- `AudioPlaybackController.gain`'s setter, which turns decibels into a linear level
- `AudioEngine.__place(_:on:)`, which does the same from the listener's position

The port has no such property on that class, and the SDK marks the protocol that declares it as iOS 8.0.
So the sources are wrong for the release this runtime is built for, not the flags:

- Apple's `AVFAudio.framework/Headers/AVAudioMixing.h:80` declares
  `@property (nonatomic) float volume;` and the same file at line 45 marks the protocol
  `API_AVAILABLE(macos(10.10), ios(8.0), watchos(2.0), tvos(9.0))`. `AVAudioPlayerNode`'s own header
  declares the conformance (`@interface AVAudioPlayerNode : AVAudioNode <AVAudioMixing>`) and no volume.
- The lift leaves that protocol alone because no registry row names it. The header the lift keeps,
  `AVAudioMixing.h` in its result folder, differs from the SDK's in five places -
  `AVAudio3DMixingRenderingAlgorithmAuto` lowered, the `AVAudio3DMixingRenderingAlgorithm` enum's own
  `NS_ENUM_AVAILABLE`, `AVAudioMixingDestination`'s class mark, `init` un-unavailable, and two members
  added to it - and the protocol's own mark is not one of them.
- The port's own player node has no volume either.
  `packages/a/apple-backports/AVFoundation/CharonAVAudioEngine.h:73` declares exactly six members on
  `@interface AVAudioPlayerNode`: `scheduleBuffer:completionHandler:`,
  `scheduleBuffer:atTime:options:completionHandler:`, `play`, `pause`, `stop` and `isPlaying`. The
  registry row for the class (`packages/a/apple-backports/registry/AVFoundation/ios8avaudioengine.json`)
  carries those six as `implemented` at `6.0` and no volume, so nothing claims it and nothing builds it.
  (`AVAudioUnitMixing9.m` answers the same surface on `AVAudioUnit`, where each value is the mixer's own
  `k3DMixerParam_`; a player node is not that - `AVAudioPlayerNode.m:4` says it carries no AudioUnit of
  its own, it is a buffer queue read from a render callback.)

One probe per member, at `armv7-apple-ios6.1.3` with this build's own lifted headers
(`probe-members.sh`, `probe-members-lift.txt`), which is what says that this one property and not the
protocol as a whole is what the sources reach:

    volume               exit 1  error: 'volume' is only available in iOS 8.0 or newer
    rate                 exit 0  clean
    pan                  exit 1  error: 'pan' is only available in iOS 8.0 or newer
    reverbBlend          exit 0  clean
    obstruction          exit 0  clean
    occlusion            exit 0  clean

`Audio.swift` writes `volume` and reaches nothing else the release lacks: with its two writes of that
property taken out in a copy of the file, the other 17 files of the overlay compile at the port's release
with 0 errors and 50 warnings (`probe-audio.sh`, `probe-audio/compile.txt`).

## Why nothing was marked away instead

`AudioPlaybackController.gain` is the level the sound is heard at. Marking the setter `@available(iOS
8.0, *)` would leave `gain` readable and unwritable at 6.1.3, or would take the whole controller out of
the module, and either way a caller who sets it would hear the sound at its own level - a silent fake.
Guarding the two writes with `if #available(iOS 8.0, *)` is the same fake with more ceremony. Neither is
what this port ships, so the sound half is not built.

## What puts it back

A registry row and an implementation for `-[AVAudioPlayerNode volume]` in `apple-backports`, at the
level the release's own mixer parameters already use (the `k3DMixerParam_` set `AVAudioUnitMixing9.m`
asks of scope 0), applied to the samples the node's render callback delivers, with a host differential
and a device call test. That is apple-backports' work, over API it owns, and this package's overlay is
the consumer of it. When the row lands, delete the note in `xmake.lua` and the `without` table beside it
and the file compiles again unchanged: nothing in `Audio.swift` is wrong for a release that carries the
property.

The alternative was deleting `Audio.swift` from the package, which the brief allows. That would throw
away correct-for-later work over one missing row in another framework, so the reversible form was taken
instead; the coordinator has the call.